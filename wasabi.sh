#!/bin/bash
# Created by Roel Van de Paar, MariaDB
#
# wasabi.sh — automated FireWorks-mode autorunner.
#
# A standalone daemon that drives the find-new-bugs pipeline end-to-end:
#   1. Nightly build cycle. Auto-discovers the newest MariaDB version via
#      /test/gendirs.sh, clones <major> into /test/<major>/, builds opt+dbg.
#      Refreshes every BUILD_MAX_AGE_SEC. Only wipes /test/<major>/ trees that
#      carry a .watchdog-clone stamp (protects hand-managed clones).
#   2. SQL generation via ~/mariadb-qa/generator/generator.sh (count of queries
#      controlled by GENERATOR_LINES). Refreshed every GENERATOR_REFRESH_HOURS;
#      output saved to /data/wasabi/sql/wasabi_input.sql.
#   3. FireWorks discovery — reducer.sh FIREWORKS=1 in screen 'fireworks',
#      reading the generated SQL and depositing newbug_*.{sql,string,
#      reducer.sh,varmod} to /data/NEWBUGS/. Restarted every
#      FIREWORKS_MAX_HOURS or when basedir rotates.
#   4. Curation — invokes ~/mariadb-qa/watchdog_curate.sh each tick, which
#      handles cleanup, reductions, ~/b reports, MTR generation across the
#      newbug output. (watchdog_curate.sh is shared with watchdog.sh; its
#      lock file prevents overlap.)
#
# Standalone, no required flags. Edit Config below to tune.

# =============== Config ===============
WASABI_LOG='/data/wasabi.log'
WASABI_DIR='/data/wasabi'
VERBOSE=1                                   # 0=errors only, 1=progress
LOOP_SLEEP_SEC=60                           # Seconds between iterations

VERSION_OVERRIDE=""                         # If set, use this MariaDB version (e.g. "13.0.1");
                                            # else auto-pick newest from /test/gendirs.sh.
SKIP_BUILDS=0                               # 1 = never clone/build; reuse existing basedir.
BUILD_MAX_AGE_SEC=90000                     # 25h. Refresh watchdog-owned trees older than this.

FIREWORKS_LINES=200000                      # Lines reducer feeds per FIREWORKS chunk.
FIREWORKS_TIMEOUT=450                       # Per-trial timeout inside FIREWORKS.
FIREWORKS_MULTI_THREADS=4                   # Parallel FIREWORKS subreducers.
FIREWORKS_MAX_HOURS=23                      # Restart FIREWORKS run after this many hours.
FIREWORKS_NEW_BUGS_DIR='/data/NEWBUGS'      # Where reducer deposits newbug_*.

GENERATOR_LINES=500000                      # Number of SQL queries to generate per refresh.
GENERATOR_REFRESH_HOURS=23                  # Regenerate SQL when wasabi_input.sql is older than this.

DISK_GATE_PCT=99                            # /data % at or above this → curation skips writes
                                            # (build cycle has its own pause-at-low-disk handling).

CURATE_SCRIPT="${HOME}/mariadb-qa/watchdog_curate.sh"
CURATE_ENABLED=1                            # 0 to skip the curation phase

# =============== Internal state ===============
USER="$(whoami)"
WIP_CLONE=0
WIP_BLD_O=0
WIP_BLD_D=0
WIP_CLONE_START=
TARGET_VERSION=
TARGET_BASEDIR=
LAST_ITER_EPOCH=0
set +H

# =============== CLI (--help only) ===============
case "${1:-}" in
  --help|-h)
    cat <<EOF
Usage: $(basename "$0")

Runs standalone with no flags. Edit Config at the top of the script to tune.

Knobs:
  VERSION_OVERRIDE  empty (auto-pick newest from gendirs) or a version string
  SKIP_BUILDS       1 to skip the clone/build cycle entirely
  BUILD_MAX_AGE_SEC 25h default — refresh watchdog-owned trees older than this
  FIREWORKS_*       reducer FIREWORKS-mode tuning
  GENERATOR_LINES   queries generated per refresh
  GENERATOR_REFRESH_HOURS  regenerate SQL when older than this

Non-destructive: never wipes a tree without a .watchdog-clone stamp.
EOF
    exit 0 ;;
esac

# =============== Signal handling ===============
abort(){ wecho 0 'Abort' 'CTRL+c, terminating'; exit 130; }
trap abort SIGINT

# =============== Helpers ===============
wecho(){
  if [ "$1" -eq 0 ] || { [ "$1" -gt 0 ] && [ "${VERBOSE}" -eq 1 ]; }; then
    local INLINE=''
    [ "$1" -gt 0 ] && INLINE=' >'
    local MSG
    MSG="$(date +'%F %T') [$2]${INLINE} $3"
    if [ -d "$(dirname "${WASABI_LOG}")" ]; then
      echo "${MSG}" | tee -a "${WASABI_LOG}"
    else
      echo "${MSG}"
    fi
  fi
}

check_if_numeric_nofail(){
  FAILED_CHECK=0
  [ -z "${1}" ] && { FAILED_CHECK=1; return; }
  local N
  N="$(echo "${1}" | sed 's|[^0-9]||g')"
  [ "${1}" != "${N}" ] && FAILED_CHECK=1
}

# =============== Preflight ===============
preflight(){
  [ ! -d "/home/${USER}/mariadb-qa" ] && {
    wecho 0 'Preflight' "*** ERROR: /home/${USER}/mariadb-qa not found"; exit 1; }
  [ ! -x "/home/${USER}/mariadb-qa/reducer.sh" ] && {
    wecho 0 'Preflight' "*** ERROR: ~/mariadb-qa/reducer.sh missing or not executable"; exit 1; }
  [ ! -x "/home/${USER}/mariadb-qa/generator/generator.sh" ] && {
    wecho 0 'Preflight' "*** ERROR: ~/mariadb-qa/generator/generator.sh missing or not executable"; exit 1; }
  [ ! -x "/home/${USER}/mariadb-qa/build_mdpsms_dbg.sh" ] && {
    wecho 0 'Preflight' "*** ERROR: ~/mariadb-qa/build_mdpsms_dbg.sh missing"; exit 1; }
  [ ! -x "/home/${USER}/mariadb-qa/build_mdpsms_opt.sh" ] && {
    wecho 0 'Preflight' "*** ERROR: ~/mariadb-qa/build_mdpsms_opt.sh missing"; exit 1; }
  { [ ! -d /data ] || [ ! -d /test ]; } && {
    wecho 0 'Preflight' "*** ERROR: /data or /test missing — run ~/mariadb-qa/linkit"; exit 1; }
  [ ! -r /test/gendirs.sh ] && {
    wecho 0 'Preflight' "*** ERROR: /test/gendirs.sh missing — run ~/mariadb-qa/linkit"; exit 1; }
  [ ! -x "${CURATE_SCRIPT}" ] && {
    wecho 0 'Preflight' "*** ERROR: ${CURATE_SCRIPT} missing — curation will fail"
    # Don't exit — wasabi can still run discovery; curate is optional.
  }
}

# =============== Dir initialisation ===============
init_dirs(){
  local DIRS=(
    "${WASABI_DIR}"
    "${WASABI_DIR}/sql"
    "${WASABI_DIR}/state"
    "${WASABI_DIR}/logs"
    "${WASABI_DIR}/generator"
    "${FIREWORKS_NEW_BUGS_DIR}"
  )
  local D
  for D in "${DIRS[@]}"; do
    [ ! -d "${D}" ] && {
      mkdir -p "${D}" || { wecho 0 'Init' "*** ERROR: could not create ${D}"; exit 1; }
      wecho 1 'Init' "Created ${D}"
    }
  done
}

# =============== Disk gates ===============
check_disk(){
  local AVAIL
  AVAIL=$(df -k -P 2>/dev/null | grep -Ev 'docker.devicemapper' | grep -E ' /data$' | awk '{print $4}')
  if [ -n "${AVAIL}" ] && [ "${AVAIL}" -lt 2000000 ]; then
    wecho 0 'Disk' "** /data <2GB free, pausing"
    while [ -n "${AVAIL}" ] && [ "${AVAIL}" -lt 2000000 ]; do
      sleep 15
      AVAIL=$(df -k -P 2>/dev/null | grep -Ev 'docker.devicemapper' | grep -E ' /data$' | awk '{print $4}')
    done
    wecho 0 'Disk' "/data diskspace restored"
  fi
  AVAIL=$(df -k -P 2>/dev/null | grep -Ev 'docker.devicemapper' | grep -E ' /test$' | awk '{print $4}')
  if [ -n "${AVAIL}" ] && [ "${AVAIL}" -lt 3000000 ]; then
    wecho 0 'Disk' "** /test <3GB free, pausing"
    while [ -n "${AVAIL}" ] && [ "${AVAIL}" -lt 3000000 ]; do
      sleep 15
      AVAIL=$(df -k -P 2>/dev/null | grep -Ev 'docker.devicemapper' | grep -E ' /test$' | awk '{print $4}')
    done
    wecho 0 'Disk' "/test diskspace restored"
  fi
}

# =============== Target version + basedir resolution ===============
# Pick the newest MariaDB version (major.minor.patch) from the regular
# gendirs.sh stable set, unless VERSION_OVERRIDE is set.
resolve_target(){
  if [ -n "${VERSION_OVERRIDE}" ]; then
    TARGET_VERSION="${VERSION_OVERRIDE}"
  else
    TARGET_VERSION=$(cd /test && ./gendirs.sh 2>/dev/null \
      | grep -oE 'mariadb-[0-9]+\.[0-9]+\.[0-9]+' \
      | sed 's|^mariadb-||' | sort -V -u | tail -1)
  fi
  if [ -z "${TARGET_VERSION}" ]; then
    wecho 0 'Target' '*** no MariaDB basedir visible via /test/gendirs.sh — cannot pick target'
    return 1
  fi
  # Newest dbg basedir matching that version.
  local NAME
  NAME=$(cd /test && ./gendirs.sh 2>/dev/null \
           | grep -E "mariadb-${TARGET_VERSION}-linux-x86_64-dbg$" \
           | sort -V | tail -1)
  if [ -n "${NAME}" ] && [ -d "/test/${NAME}" ]; then
    TARGET_BASEDIR="/test/${NAME}"
  else
    TARGET_BASEDIR=
  fi
  wecho 1 'Target' "version=${TARGET_VERSION} basedir=${TARGET_BASEDIR:-<none yet>}"
}

# =============== Build cycle ===============
# Ensures /test/<major>/ clone exists (watchdog-owned) and rebuilds dbg+opt
# every BUILD_MAX_AGE_SEC. Never wipes a tree without a .watchdog-clone stamp.
build_cycle(){
  [ "${SKIP_BUILDS}" -eq 1 ] && { wecho 1 'Build' 'SKIP_BUILDS=1 — disabled'; return 0; }
  [ -z "${TARGET_VERSION}" ] && { wecho 1 'Build' 'No target version — skipping'; return 0; }

  local MAJOR SRC_DIR STAMP
  MAJOR=$(echo "${TARGET_VERSION}" | awk -F. '{print $1"."$2}')
  SRC_DIR="/test/${MAJOR}"
  STAMP="${SRC_DIR}/.watchdog-clone"

  # Decide if a build is needed.
  local DOBUILD=0 LASTBUILD NOW
  if [ -r "${WASABI_DIR}/state/lastbuild" ] && [ -s "${WASABI_DIR}/state/lastbuild" ]; then
    LASTBUILD="$(cat "${WASABI_DIR}/state/lastbuild")"
    check_if_numeric_nofail "${LASTBUILD}"
    if [ "${FAILED_CHECK}" -eq 1 ]; then
      wecho 0 'Build' '** lastbuild non-numeric — treating as fresh'; DOBUILD=1
    else
      NOW="$(date +'%s')"
      if [ $(( NOW - LASTBUILD )) -gt "${BUILD_MAX_AGE_SEC}" ]; then
        wecho 1 'Build' "Previous build >$(( BUILD_MAX_AGE_SEC / 3600 ))h old, triggering"
        DOBUILD=1
      else
        wecho 1 'Build' "Previous build $(( NOW - LASTBUILD ))s old; no rebuild"
      fi
    fi
  else
    wecho 1 'Build' 'No previous build record — building now'
    DOBUILD=1
  fi

  if [ "${DOBUILD}" -eq 1 ] && [ "${WIP_CLONE}" -eq 0 ] && [ "${WIP_BLD_O}" -eq 0 ] && [ "${WIP_BLD_D}" -eq 0 ]; then
    if [ -d "${SRC_DIR}" ] && [ ! -f "${STAMP}" ]; then
      wecho 0 'Build' "*** REFUSING to clone: ${SRC_DIR} exists without ${STAMP} (not watchdog-owned)"
      wecho 0 'Build' "***   leaving it intact; to hand it to wasabi:  touch ${STAMP}"
      date +'%s' | tr -d '\n' > "${WASABI_DIR}/state/lastbuild"
    else
      [ -d "${SRC_DIR}" ] && [ -f "${STAMP}" ] && {
        wecho 0 'Build' "Wiping prior watchdog-owned ${SRC_DIR} for fresh clone"
        rm -Rf "${SRC_DIR}"
      }
      wecho 0 'Build' "Cloning MariaDB branch ${MAJOR} → ${SRC_DIR}"
      screen -dmS clone git clone --depth=1 --recurse-submodules -j10 \
        --branch "${MAJOR}" https://github.com/MariaDB/server.git "${SRC_DIR}"
      WIP_CLONE=1
      WIP_CLONE_START=$(date +'%s')
      date +'%s' | tr -d '\n' > "${WASABI_DIR}/state/lastbuild"
    fi
  fi

  if [ "${WIP_CLONE}" -eq 1 ]; then
    if [ -z "$(screen -ls 2>/dev/null | grep '\.clone\b')" ]; then
      WIP_CLONE=0
      sync
      if [ ! -d "${SRC_DIR}" ] || [ ! -r "${SRC_DIR}/VERSION" ]; then
        wecho 0 'Build' "*** clone failed quality check — will retry"
        rm -Rf "${SRC_DIR}"
      else
        wecho 0 'Build' "Clone OK ($(( $(date +'%s') - WIP_CLONE_START ))s) — stamping + launching opt + dbg builds"
        { echo "created_by=wasabi.sh"; echo "created_at=$(date -Iseconds)"; echo "version=${TARGET_VERSION}"; } > "${STAMP}"
        ( cd "${SRC_DIR}" && "${HOME}/mariadb-qa/build_mdpsms_opt.sh" ) &
        WIP_BLD_O=1
        sleep 30 && sync
        ( cd "${SRC_DIR}" && "${HOME}/mariadb-qa/build_mdpsms_dbg.sh" ) &
        WIP_BLD_D=1
      fi
    elif [ $(( $(date +'%s') - WIP_CLONE_START )) -gt 900 ]; then
      wecho 0 'Build' "*** clone >15min — terminating screen, will retry"
      screen -S clone -X quit 2>/dev/null
      rm -Rf "${SRC_DIR}"
      WIP_CLONE=0
    fi
  fi

  # Crude completion detection: bg jobs settled and a built binary appeared.
  if [ "${WIP_BLD_O}" -eq 1 ] && [ -z "$(jobs -p)" ]; then
    if [ -x "${SRC_DIR}/bin/mariadbd" ] || [ -x "${SRC_DIR}/bin/mysqld" ]; then
      wecho 0 'Build' 'opt build complete'; WIP_BLD_O=0
    fi
  fi
  if [ "${WIP_BLD_D}" -eq 1 ] && [ -z "$(jobs -p)" ]; then
    if [ -x "${SRC_DIR}/bin/mariadbd" ] || [ -x "${SRC_DIR}/bin/mysqld" ]; then
      wecho 0 'Build' 'dbg build complete'; WIP_BLD_D=0
    fi
  fi
}

# =============== SQL generation ===============
# Generate fresh fuzzed SQL via ~/mariadb-qa/generator/generator.sh. Run from a
# wasabi-local copy of the generator dir so we don't collide with concurrent
# pquery-run users sharing the canonical generator/. Output lands at
# ${WASABI_DIR}/sql/wasabi_input.sql.
generate_sql(){
  local TGT="${WASABI_DIR}/sql/wasabi_input.sql"
  local STATE="${WASABI_DIR}/state/lastgen"
  local NEED=0

  if [ ! -s "${TGT}" ]; then
    NEED=1
  elif [ -r "${STATE}" ] && [ -s "${STATE}" ]; then
    local LAST NOW
    LAST="$(cat "${STATE}")"
    check_if_numeric_nofail "${LAST}"
    if [ "${FAILED_CHECK}" -eq 1 ]; then
      NEED=1
    else
      NOW="$(date +'%s')"
      [ $(( ( NOW - LAST ) / 3600 )) -ge "${GENERATOR_REFRESH_HOURS}" ] && NEED=1
    fi
  else
    NEED=1
  fi

  [ "${NEED}" -eq 0 ] && { wecho 1 'Gen' "wasabi_input.sql is fresh; no regen"; return 0; }

  # Sync the generator dir (cheap: only newer files copy via -u).
  cp -ru "${HOME}/mariadb-qa/generator/." "${WASABI_DIR}/generator/" 2>/dev/null

  local GEN_DIR="${WASABI_DIR}/generator"
  [ ! -x "${GEN_DIR}/generator.sh" ] && {
    wecho 0 'Gen' "*** generator.sh not present in ${GEN_DIR}"; return 1
  }

  wecho 0 'Gen' "Generating ${GENERATOR_LINES} queries (cwd=${GEN_DIR})"
  local START
  START=$(date +'%s')
  ( cd "${GEN_DIR}" && rm -f out.sql; ./generator.sh "${GENERATOR_LINES}" >/dev/null 2>&1 )
  if [ ! -s "${GEN_DIR}/out.sql" ]; then
    wecho 0 'Gen' "*** generator.sh produced no out.sql"
    return 1
  fi
  mv "${GEN_DIR}/out.sql" "${TGT}"
  date +'%s' > "${STATE}"
  wecho 0 'Gen' "Wrote ${TGT}: $(wc -l < "${TGT}") lines in $(( $(date +'%s') - START ))s"
}

# =============== FireWorks discovery ===============
# Persistent reducer.sh FIREWORKS=1 in a 'fireworks' screen against
# TARGET_BASEDIR with INPUTFILE=wasabi_input.sql. Restart on any of:
#   - no 'fireworks' screen alive
#   - run age >= FIREWORKS_MAX_HOURS
#   - basedir rotated (a newer one appeared in gendirs)
#   - input SQL was regenerated (lastgen newer than fireworks_started)
discover_fireworks(){
  [ -z "${TARGET_BASEDIR}" ] && { wecho 1 'FW' "No target basedir for ${TARGET_VERSION:-?} yet"; return 0; }
  if [ ! -x "${TARGET_BASEDIR}/bin/mariadbd" ] && [ ! -x "${TARGET_BASEDIR}/bin/mysqld" ]; then
    wecho 1 'FW' "Target basedir ${TARGET_BASEDIR} has no mariadbd/mysqld binary yet"; return 0
  fi
  local INFILE="${WASABI_DIR}/sql/wasabi_input.sql"
  if [ ! -s "${INFILE}" ]; then
    wecho 1 'FW' "${INFILE} not yet generated — skipping discovery this iteration"
    return 0
  fi

  local ALIVE STARTED CURRENT_BD AGE_H NEED_RESTART=0 LAST_GEN
  ALIVE=$(screen -ls 2>/dev/null | awk '$1 ~ /\.fireworks$/ {print $1}' | head -1)
  [ -r "${WASABI_DIR}/state/fireworks_started" ] && [ -s "${WASABI_DIR}/state/fireworks_started" ] \
    && STARTED="$(cat "${WASABI_DIR}/state/fireworks_started")"
  [ -r "${WASABI_DIR}/state/fireworks_basedir" ] \
    && CURRENT_BD="$(cat "${WASABI_DIR}/state/fireworks_basedir")"
  [ -r "${WASABI_DIR}/state/lastgen" ] && [ -s "${WASABI_DIR}/state/lastgen" ] \
    && LAST_GEN="$(cat "${WASABI_DIR}/state/lastgen")"

  if [ -z "${ALIVE}" ]; then
    wecho 0 'FW' 'Not running — will start'; NEED_RESTART=1
  elif [ -n "${STARTED}" ] && [ $(( ( $(date +'%s') - STARTED ) / 3600 )) -ge "${FIREWORKS_MAX_HOURS}" ]; then
    AGE_H=$(( ( $(date +'%s') - STARTED ) / 3600 ))
    wecho 0 'FW' "${AGE_H}h old — rotating (>= ${FIREWORKS_MAX_HOURS}h)"; NEED_RESTART=1
  elif [ -n "${CURRENT_BD}" ] && [ "${CURRENT_BD}" != "${TARGET_BASEDIR}" ]; then
    wecho 0 'FW' "Basedir rotated (${CURRENT_BD} → ${TARGET_BASEDIR})"; NEED_RESTART=1
  elif [ -n "${LAST_GEN}" ] && [ -n "${STARTED}" ] && [ "${LAST_GEN}" -gt "${STARTED}" ]; then
    wecho 0 'FW' 'Input SQL regenerated — restarting against fresh input'; NEED_RESTART=1
  fi
  [ "${NEED_RESTART}" -eq 0 ] && return 0

  [ -n "${ALIVE}" ] && { screen -S "${ALIVE}" -X quit 2>/dev/null; sleep 2; }

  local FW="${WASABI_DIR}/state/fireworks_reducer.sh"
  cp "${HOME}/mariadb-qa/reducer.sh" "${FW}"
  sed -i \
    -e "s|^INPUTFILE=.*|INPUTFILE=\"${INFILE}\"|" \
    -e "s|^BASEDIR=.*|BASEDIR=\"${TARGET_BASEDIR}\"|" \
    -e "s|^FIREWORKS=.*|FIREWORKS=1|" \
    -e "s|^FIREWORKS_LINES=.*|FIREWORKS_LINES=${FIREWORKS_LINES}|" \
    -e "s|^FIREWORKS_TIMEOUT=.*|FIREWORKS_TIMEOUT=${FIREWORKS_TIMEOUT}|" \
    -e "s|^MULTI_THREADS=.*|MULTI_THREADS=${FIREWORKS_MULTI_THREADS}|" \
    -e "s|^NEW_BUGS_SAVE_DIR=.*|NEW_BUGS_SAVE_DIR=\"${FIREWORKS_NEW_BUGS_DIR}\"|" \
    -e "s|^MODE=.*|MODE=4|" \
    -e "s|^USE_NEW_TEXT_STRING=.*|USE_NEW_TEXT_STRING=1|" \
    -e "s|^USE_PQUERY=.*|USE_PQUERY=1|" \
    -e "s|^SCAN_FOR_NEW_BUGS=.*|SCAN_FOR_NEW_BUGS=1|" \
    "${FW}"
  chmod +x "${FW}"

  local LOG="${WASABI_DIR}/logs/fireworks_$(date +'%F_%H%M%S').log"
  wecho 0 'FW' "Launching (basedir=${TARGET_BASEDIR}, infile=$(basename "${INFILE}"), log=${LOG})"
  screen -dmS fireworks bash -c "${FW} 2>&1 | tee ${LOG}"
  date +'%s' > "${WASABI_DIR}/state/fireworks_started"
  echo "${TARGET_BASEDIR}" > "${WASABI_DIR}/state/fireworks_basedir"
}

# =============== Curation ===============
# watchdog_curate.sh handles cleanup, P1 starts, hung handling, copy-through
# reductions, ~/b reports, MTR generation. Its lock prevents overlap with any
# concurrently-running watchdog.sh that's also calling it.
curate(){
  [ "${CURATE_ENABLED}" -ne 1 ] && { wecho 1 'Curate' 'CURATE_ENABLED=0 — skipping'; return 0; }
  [ ! -x "${CURATE_SCRIPT}" ] && { wecho 1 'Curate' "${CURATE_SCRIPT} missing — skipping"; return 0; }
  "${CURATE_SCRIPT}"
}

# =============== Main loop ===============
main_loop(){
  while true; do
    LAST_ITER_EPOCH=$(date +'%s')
    wecho 0 'Loop' '=== Iteration start ==='

    init_dirs
    check_disk
    resolve_target
    build_cycle
    generate_sql
    discover_fireworks
    curate

    local ELAPSED NB
    ELAPSED=$(( $(date +'%s') - LAST_ITER_EPOCH ))
    NB=$(ls "${FIREWORKS_NEW_BUGS_DIR}"/newbug_*.reducer.sh 2>/dev/null | wc -l)
    wecho 0 'Loop' "=== Iteration end (${ELAPSED}s, target=${TARGET_VERSION:-none}, newbugs=${NB}) ==="

    sleep "${LOOP_SLEEP_SEC}"
  done
}

main(){
  # Single-instance lock.
  mkdir -p "${WASABI_DIR}/state" 2>/dev/null
  exec 8>"${WASABI_DIR}/state/wasabi.lock" 2>/dev/null || true
  if ! flock -n 8 2>/dev/null; then
    echo "wasabi.sh: another instance is already running (lock held)" >&2
    exit 1
  fi
  preflight
  init_dirs
  main_loop
}
main "$@"
