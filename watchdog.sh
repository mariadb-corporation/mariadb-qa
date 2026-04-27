#!/bin/bash
# Created by Roel Van de Paar, MariaDB
#
# watchdog.sh — supervising daemon for ongoing pquery-run + wasabi work.
#
# Each LOOP_SLEEP_SEC iteration:
#   1. Ensure /data/watchdog/ state dirs exist.
#   2. Ensure ~/ds and ~/memory monitors are running.
#   3. Disk gates: pause if /data or /test get dangerously low.
#   4. Invoke ~/mariadb-qa/watchdog_curate.sh — handles P0A/P0B cleanup,
#      P1 starts, P2 hung handling, P3-P5 reduction/report/MTR, P6 0-line
#      repair across BOTH /data/<wd>/<trial>/ (pquery-run pr/ge/sr workdirs)
#      AND /data/NEWBUGS/ (wasabi's FireWorks output).
#
# This is a watcher only. Builds + FireWorks discovery + SQL generation live
# in wasabi.sh; watchdog just observes their output and curates.
#
# Standalone, no required flags. Edit Config below to tune.

# =============== Config ===============
WATCHDOG_LOG='/data/watchdog.log'
VERBOSE=1                       # 0 = errors only, 1 = progress too
LOOP_SLEEP_SEC=60               # Seconds between iterations
DISK_GATE_PCT=99                # /data % at or above this → curation skips writes
CURATE_SCRIPT="${HOME}/mariadb-qa/watchdog_curate.sh"
CURATE_ENABLED=1                # 0 to skip the curation phase

# =============== Internal state ===============
USER="$(whoami)"
LAST_ITER_EPOCH=0
DISK_WRITES_OK=1
set +H

# =============== CLI (--help only) ===============
case "${1:-}" in
  --help|-h)
    cat <<EOF
Usage: $(basename "$0")

Runs standalone with no flags. Edit the Config block at the top of the script
to tune behaviour. The watchdog is non-destructive: it never kills processes
itself (curate may, per its own configured caps and thresholds) and never
wipes any tree.

For the discovery half (builds + FireWorks + SQL generation), run wasabi.sh.
EOF
    exit 0 ;;
esac

# =============== Signal handling ===============
abort(){ wecho 0 'Abort' 'CTRL+c, terminating'; exit 130; }
trap abort SIGINT

# =============== Helpers ===============
wecho(){
  # wecho <verbose_level> <tag> <message>  — level 0 always; level >0 only if VERBOSE=1
  if [ "$1" -eq 0 ] || { [ "$1" -gt 0 ] && [ "${VERBOSE}" -eq 1 ]; }; then
    local INLINE=''
    [ "$1" -gt 0 ] && INLINE=' >'
    local MSG
    MSG="$(date +'%F %T') [$2]${INLINE} $3"
    if [ -d "$(dirname "${WATCHDOG_LOG}")" ]; then
      echo "${MSG}" | tee -a "${WATCHDOG_LOG}"
    else
      echo "${MSG}"
    fi
  fi
}

# =============== Preflight ===============
preflight(){
  [ ! -d "/home/${USER}/mariadb-qa" ] && {
    wecho 0 'Preflight' "*** ERROR: /home/${USER}/mariadb-qa not found"; exit 1; }
  [ ! -d /data ] && { wecho 0 'Preflight' "*** ERROR: /data missing — run ~/mariadb-qa/linkit"; exit 1; }
  [ ! -x "${CURATE_SCRIPT}" ] && { wecho 0 'Preflight' "*** ERROR: ${CURATE_SCRIPT} missing or not executable"; exit 1; }
}

# =============== Dir initialisation ===============
init_dirs(){
  # Curate writes to these; create on first iteration so log lines have a place.
  local DIRS=(
    /data/watchdog
    /data/watchdog/state
    /data/watchdog/logs
    /data/watchdog/ai_queue
  )
  local D
  for D in "${DIRS[@]}"; do
    [ ! -d "${D}" ] && { mkdir -p "${D}" || { wecho 0 'Init' "*** ERROR: could not create ${D}"; exit 1; }; }
  done
}

# =============== Resource monitors ===============
# Restart ~/ds and ~/memory if their screen has died. Detect via screen -ls,
# not ps -ef — the inner process under screen often doesn't show the home-dir
# path in argv, so the previous ps-grep approach silently spawned duplicates.
start_monitors(){
  local S
  for S in ds memory; do
    if screen -ls 2>/dev/null | awk -v n="[.]${S}\$" '$1 ~ n {f=1} END{exit !f}'; then
      continue
    fi
    [ ! -r "/home/${USER}/${S}" ] && { wecho 0 'ResMon' "*** ERROR: ~/${S} not found"; continue; }
    wecho 0 'ResMon' "~/${S} not running — starting"
    screen -admS "${S}" "/home/${USER}/${S}"
  done
}

# =============== Disk gates ===============
check_disk(){
  local AVAIL
  AVAIL=$(df -k -P 2>/dev/null | grep -Ev 'docker.devicemapper' | grep -E ' /data$' | awk '{print $4}')
  if [ -n "${AVAIL}" ] && [ "${AVAIL}" -lt 2000000 ]; then
    wecho 0 'ResMon' "** /data <2GB free, pausing"
    while [ -n "${AVAIL}" ] && [ "${AVAIL}" -lt 2000000 ]; do
      sleep 15
      AVAIL=$(df -k -P 2>/dev/null | grep -Ev 'docker.devicemapper' | grep -E ' /data$' | awk '{print $4}')
    done
    wecho 0 'ResMon' "/data diskspace restored"
  fi
  AVAIL=$(df -k -P 2>/dev/null | grep -Ev 'docker.devicemapper' | grep -E ' /test$' | awk '{print $4}')
  if [ -n "${AVAIL}" ] && [ "${AVAIL}" -lt 3000000 ]; then
    wecho 0 'ResMon' "** /test <3GB free, pausing"
    while [ -n "${AVAIL}" ] && [ "${AVAIL}" -lt 3000000 ]; do
      sleep 15
      AVAIL=$(df -k -P 2>/dev/null | grep -Ev 'docker.devicemapper' | grep -E ' /test$' | awk '{print $4}')
    done
    wecho 0 'ResMon' "/test diskspace restored"
  fi
  local PCT
  PCT=$(df /data --output=pcent 2>/dev/null | tail -1 | tr -dc 0-9)
  if [ -n "${PCT}" ] && [ "${PCT}" -ge "${DISK_GATE_PCT}" ]; then
    wecho 0 'ResMon' "/data at ${PCT}% (>= ${DISK_GATE_PCT}%) — curation will skip writes"
    DISK_WRITES_OK=0
  else
    DISK_WRITES_OK=1
  fi
}

# =============== Curation ===============
# Curate writes its detailed log to /data/watchdog/curate.log. Mirror its
# stdout/stderr to ${WATCHDOG_LOG} so the watchdog console / `~/watchdog log`
# also show curation progress in real time.
curate(){
  [ "${CURATE_ENABLED}" -ne 1 ] && { wecho 1 'Curate' 'CURATE_ENABLED=0 — skipping'; return 0; }
  "${CURATE_SCRIPT}" 2>&1 | tee -a "${WATCHDOG_LOG}"
  # Use first PIPESTATUS so curate's exit code propagates (tee always returns 0).
  return "${PIPESTATUS[0]}"
}

# =============== Main loop ===============
main_loop(){
  while true; do
    LAST_ITER_EPOCH=$(date +'%s')
    wecho 0 'Loop' '=== Iteration start ==='

    init_dirs
    start_monitors
    check_disk
    curate

    local ELAPSED
    ELAPSED=$(( $(date +'%s') - LAST_ITER_EPOCH ))
    wecho 0 'Loop' "=== Iteration end (${ELAPSED}s) ==="

    sleep "${LOOP_SLEEP_SEC}"
  done
}

main(){
  preflight
  init_dirs
  main_loop
}
main "$@"
