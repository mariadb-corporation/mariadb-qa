#!/bin/bash
# Created by Roel Van de Paar, MariaDB
#
# watchdog_curate.sh — single mechanical curation pass over active reducers
# Invoked by watchdog.sh each main-loop iteration; exits when done.
# Acts on UniqueIDs (not trials), tracking per-BUG_UID attempt state in
# /data/watchdog/attempts.log, and queues AI-judgment cases into
# /data/watchdog/ai_queue/.
#
# Two data sources:
#   /data/NEWBUGS/newbug_<EPOCH>.{reducer.sh,string,sql,varmod}  (FireWorks)
#   /data/<wd>/<trial>/ + /data/<wd>/reducer<trial>.sh           (pquery-run)

set +H   # disable history substitution (avoids '!' in TEXT/regex causing 'event not found')

# ============================ Config ============================
MAX_MEMORY_IN_USE=${MAX_MEMORY_IN_USE:-110}      # GB. P1 stops launching when free -g 'used' hits this.
INTER_START_SLEEP=${INTER_START_SLEEP:-10}       # Seconds between successive sr launches in P1.

P2_CAP=${P2_CAP:-2}               # Depges per pass (switch-to-sibling-trial is uncapped).
P3_CAP=${P3_CAP:-4}               # Copy-through reductions per pass.
P4_CAP=${P4_CAP:-2}               # ~/b invocations per pass (each can take 10-30 min).
P5_CAP=${P5_CAP:-2}               # MTR generations per pass.

HANG_MIN=${HANG_MIN:-90}                         # Reducer.log mtime older than this in minutes → HUNG (P2).
SMALL_OUT_LINES=${SMALL_OUT_LINES:-10}           # _out at or below this many lines = good enough; no depge/switch.
STUCK_NO_REPRO_HOURS=${STUCK_NO_REPRO_HOURS:-4}  # Running this long with no '[*]' marker → kill (P0B).
DATA_HARD_CAP=${DATA_HARD_CAP:-99}               # df /data pct at or above this → skip P3/P4/P5 (sed -i would fail silently).

ATTEMPTS_LOG=${ATTEMPTS_LOG:-/data/watchdog/attempts.log}
DEPGED_LOG=${DEPGED_LOG:-/data/watchdog/depged_trials.log}
LOOP_LOG=${LOOP_LOG:-/data/watchdog/curate.log}
AI_QUEUE=${AI_QUEUE:-/data/watchdog/ai_queue}
MTR_TEMPLATES=${MTR_TEMPLATES:-${HOME}/mariadb-qa/claude_mtr_templates}
NEWBUGS_DIR=${NEWBUGS_DIR:-/data/NEWBUGS}
RESULTS_LIST=${RESULTS_LIST:-/data/results.list}

# ============================ State ============================
# Counters populated by phase functions
P0A_KILLED=0; P0B_KILLED=0
P1_STARTED=0; P1_DEDUP=0; P1_NOSCRIPT=0; P1_MEM_STOP=0
P2_SWITCHED=0; P2_DEPGED=0; P2_READY_P3=0
P3_COPIED=0; P3_QUEUED_AI=0
P4_GENERATED=0; P4_PARTIAL=0; P4_FAILED=0
P5_GENERATED=0; P5_BUG_REPRO=0; P5_QUEUED_AI=0
P6_REGEN=0; P6_FAILED=0

# Trial keys processed this pass (for P5 to prefer same-pass trials)
THIS_PASS_P3_TRIALS=()
THIS_PASS_P4_TRIALS=()

# ============================ Helpers ============================
ts(){ date -Iseconds; }

log_loop(){ echo "$(ts) $*" >> "$LOOP_LOG" 2>/dev/null || true; }
log_action(){ echo "$(ts) $*" >> "$ATTEMPTS_LOG" 2>/dev/null || true; }
log_depged(){ echo "$(ts) $*" >> "$DEPGED_LOG" 2>/dev/null || true; }

# get_uid <path>
#   <path> can be a trial dir (reads MYBUG; falls back to ~/t inside it)
#   or a newbug_<EPOCH>.reducer.sh path (reads the sibling .string)
get_uid(){
  local ARG="$1"
  local BUG_UID=""
  if [ -d "$ARG" ]; then
    BUG_UID="$(cat "$ARG/MYBUG" 2>/dev/null)"
    if [ -z "$BUG_UID" ] && [ -r "$ARG/log/master.err" ]; then
      BUG_UID="$(cd "$ARG" && "${HOME}/t" 2>/dev/null | head -1)"
    fi
  else
    # Reducer script path: strip .reducer.sh, look for .string sibling
    local BASE="${ARG%.reducer.sh}"
    [ -r "${BASE}.string" ] && BUG_UID="$(cat "${BASE}.string")"
    # Last resort — pull TEXT= from the reducer itself
    if [ -z "$BUG_UID" ] && [ -r "$ARG" ]; then
      BUG_UID="$(awk -F= '/^[[:space:]]*TEXT=/{gsub(/^"|"$/, "", $2); print $2; exit}' "$ARG")"
    fi
  fi
  echo "$BUG_UID"
}

# screen_for_trial <trial_or_key>   →  <pid>.s<arg> if found, else empty
screen_for_trial(){
  local T="$1"
  screen -ls 2>/dev/null | awk -v t="s${T}" '{for(i=1;i<=NF;i++) if($i ~ "[.]"t"$") print $i}' | head -1
}

# is_depged <trial>  →  0 if in depged log, 1 otherwise
is_depged(){
  local T="$1"
  [ ! -r "$DEPGED_LOG" ] && return 1
  awk -v t="$T" '$0 ~ ("trial=" t "$") || $0 ~ ("trial=" t "[[:space:]]") {f=1} END{exit !f}' "$DEPGED_LOG"
}

# attempts_for_uid <uid>  →  space-separated list of "wd/trial" pairs already attempted
attempts_for_uid(){
  local BUG_UID="$1"
  [ ! -r "$ATTEMPTS_LOG" ] && { echo ""; return; }
  awk -v u="$BUG_UID" '
    index($0, "uid=\"" u "\"") && /action=(started|switched|depged)/ {
      # Extract wd= and trial= values
      wd=""; tr="";
      for(i=1;i<=NF;i++){
        if($i ~ /^wd=/){ sub(/^wd=/, "", $i); wd=$i }
        if($i ~ /^trial=/){ sub(/^trial=/, "", $i); tr=$i }
      }
      if(wd && tr) print wd "/" tr
    }' "$ATTEMPTS_LOG" | sort -u | tr '\n' ' '
}

# last_status_for_uid <uid>  →  last action= value for this uid, or empty
last_status_for_uid(){
  local BUG_UID="$1"
  [ ! -r "$ATTEMPTS_LOG" ] && return
  awk -v u="$BUG_UID" 'index($0, "uid=\"" u "\"") {last=$0} END{print last}' "$ATTEMPTS_LOG" | \
    awk '{for(i=1;i<=NF;i++) if($i ~ /^action=/){ sub(/^action=/, "", $i); print $i; exit}}'
}

# mem_used_g  →  current "used" GB from `free -g`
mem_used_g(){ free -g | awk '/^Mem:/ {print $3; exit}'; }

# newest_out <trial_dir>  →  path to newest *_out* (non-_claude_reduced), or empty
newest_out(){
  local TDIR="$1"
  ls -t "$TDIR"/*_out* 2>/dev/null | awk '!/_claude_reduced$/' | head -1
}

# basedir_from_reducer <path-to-reducer.sh>  →  BASEDIR= value (no quotes), or empty
basedir_from_reducer(){
  awk -F= '/^BASEDIR=/{gsub(/"/,"",$2); print $2; exit}' "$1" 2>/dev/null
}

# mt_layout <basedir>  →  echoes "mariadb-test" or "mysql-test" or empty
mt_layout(){
  local BD="$1"
  if [ -d "$BD/mariadb-test/main" ]; then echo "mariadb-test"
  elif [ -d "$BD/mysql-test/t" ]; then echo "mysql-test"
  fi
}

# enqueue_ai <key> <reason> [info-kv-pairs...]
# Creates /data/watchdog/ai_queue/<key>/info.txt with guidance for manual AI processing.
enqueue_ai(){
  local KEY="$1"; shift
  local REASON="$1"; shift
  local DIR="$AI_QUEUE/$KEY"
  mkdir -p "$DIR" 2>/dev/null || return 1
  {
    echo "queued: $(ts)"
    echo "reason: $REASON"
    echo "key: $KEY"
    for KV in "$@"; do echo "$KV"; done
  } > "$DIR/info.txt"
  log_loop "[AI_QUEUE] enqueued key=$KEY reason=$REASON"
}

# ============================ Phase 0: gates ============================
phase0_gates(){
  USED_G=$(mem_used_g)
  DATA_PCT=$(df /data --output=pcent 2>/dev/null | tail -1 | tr -dc 0-9)
  [ -z "$DATA_PCT" ] && DATA_PCT=0

  if [ "$DATA_PCT" -ge "$DATA_HARD_CAP" ]; then
    P345_OK=0
    log_loop "[curate][ALERT] /data at ${DATA_PCT}% — P3/P4/P5 will skip writes"
  else
    P345_OK=1
  fi
  log_loop "[curate] start USED=${USED_G}G/cap=${MAX_MEMORY_IN_USE}G DATA=${DATA_PCT}% p345_ok=$P345_OK"
}

# ============================ Phase 0A: cleanup finished screens ============================
# `sr` leaves an idle bash trailing inside the screen after reducer + PGE
# iterations complete. Quit any 's<key>' screen whose reducer is no longer
# running. Uncapped.
cleanup_finished_screens(){
  local FULL T killed=0
  while IFS= read -r FULL; do
    [ -z "$FULL" ] && continue
    # Extract the trial key (everything after '.s' in the screen name)
    T=$(echo "$FULL" | sed 's|^[0-9]*\.s||')
    [ -z "$T" ] && continue
    # If a reducer process for this trial is alive, leave the screen alone.
    if pgrep -af "/reducer${T}\.sh\b" >/dev/null 2>&1; then continue; fi
    if pgrep -af "/newbug_${T}\.reducer\.sh\b" >/dev/null 2>&1; then continue; fi
    if [[ "$T" == newbug_* ]] && pgrep -af "/${T}\.reducer\.sh\b" >/dev/null 2>&1; then continue; fi
    # No reducer process. Screen is idle bash. Quit it.
    screen -S "$FULL" -X quit 2>/dev/null
    log_loop "[P0A] killed-finished screen=$FULL trial=$T"
    killed=$((killed+1))
  done < <(screen -ls 2>/dev/null | awk '$1 ~ /\.s[a-zA-Z0-9_]+$/ {print $1}')
  P0A_KILLED=$killed
  log_loop "[P0A] killed=$P0A_KILLED"
}

# ============================ Phase 0B: cleanup stuck-no-repro reducers ============================
# Kill reducers running > STUCK_NO_REPRO_HOURS without an ATLEASTONCE marker
# ('[*]') anywhere in recent log tail — they never reproduced and aren't going
# to. Distinct from P2's hung-but-reproduced flow (switch/depge). Uncapped.
cleanup_stuck_no_repro(){
  local LOG RPATH T WD AGE_MIN FULL killed=0
  local STUCK_MIN=$((STUCK_NO_REPRO_HOURS * 60))
  while IFS= read -r LOG; do
    [ ! -f "$LOG" ] && continue
    local LMTIME
    LMTIME=$(stat -c %Y "$LOG" 2>/dev/null)
    [ -z "$LMTIME" ] && continue
    AGE_MIN=$(( ( $(date +%s) - LMTIME ) / 60 ))
    [ "$AGE_MIN" -lt "$STUCK_MIN" ] && continue
    # Did the reducer ever reproduce? Look for ATLEASTONCE marker '[*]' in tail.
    if tail -100 "$LOG" 2>/dev/null | command grep -aq '\[\*\]'; then
      continue   # has reproduced — Phase 2 territory
    fi
    # Map log → trial
    RPATH=$(awk 'match($0, /\/data\/[0-9]+\/reducer[0-9]+\.sh/){print substr($0, RSTART, RLENGTH); exit}' "$LOG")
    if [ -z "$RPATH" ]; then
      RPATH=$(awk 'match($0, /\/data\/NEWBUGS\/newbug_[0-9]+\.reducer\.sh/){print substr($0, RSTART, RLENGTH); exit}' "$LOG")
    fi
    [ -z "$RPATH" ] && continue
    if echo "$RPATH" | command grep -aq '/NEWBUGS/'; then
      T=$(echo "$RPATH" | sed -n 's|.*newbug_\([0-9]\+\)\.reducer\.sh|newbug_\1|p')
      WD=NEWBUGS
    else
      T=$(echo "$RPATH" | awk -F'reducer|[.]sh' '{print $(NF-1)}')
      WD=$(echo "$RPATH" | awk -F/ '{print $3}')
    fi
    FULL=$(screen_for_trial "$T")
    [ -n "$FULL" ] && screen -S "$FULL" -X quit 2>/dev/null
    pkill -TERM -f "$RPATH" 2>/dev/null
    log_loop "[P0B] killed-stuck-no-repro wd=$WD trial=$T age=${AGE_MIN}m screen=$FULL"
    killed=$((killed+1))
  done < <(command grep -la "Reducer PID" /dev/shm/*/reducer.log 2>/dev/null)
  P0B_KILLED=$killed
  log_loop "[P0B] killed=$P0B_KILLED"
}

# ============================ Phase 1: start reducers (memory-bounded) ============================
# Iterate two sources in natural order, calling ~/sr for each new candidate:
#   (a) /data/NEWBUGS/newbug_<EPOCH>.reducer.sh  — newest first (ls -t)
#   (b) /data/<wd>/<trial>/                       — ~/pr's order, in workdirs
#                                                   listed above 'return 0' in
#                                                   /data/results.list
# Skip a BUG_UID if its last attempts-log status is ready_p3 or depged. Stop the
# whole phase as soon as `free -g`'s 'used' column hits MAX_MEMORY_IN_USE; sleep
# INTER_START_SLEEP between starts so memory has time to settle.
phase1_start_reducers(){
  # _try_start cwd sr-arg source-tag wd-label key uid
  #   0=started   (counter bumped, sleep INTER_START_SLEEP)
  #   1=dedup     (sr saw same BUG_UID already running elsewhere)
  #   2=error     (sr exited non-zero for other reasons)
  #   3=mem-stop  (cap reached; outer loop should break)
  _try_start(){
    local CWD="$1" SRARG="$2" SOURCE="$3" WD="$4" KEY="$5" BUG_UID="$6"
    local U
    U=$(mem_used_g)
    if [ "$U" -ge "$MAX_MEMORY_IN_USE" ]; then
      log_loop "[P1] memory cap reached (${U}G >= ${MAX_MEMORY_IN_USE}G) — stopping starts"
      P1_MEM_STOP=1
      return 3
    fi
    cd "$CWD" || return 2
    local OUT RC
    OUT="$("${HOME}/sr" "$SRARG" 2>&1)"; RC=$?
    if echo "$OUT" | awk '/is already running/{f=1} END{exit !f}'; then
      log_loop "[P1] DEDUP src=$SOURCE wd=$WD key=$KEY uid=\"$BUG_UID\""
      P1_DEDUP=$((P1_DEDUP+1))
      return 1
    fi
    if [ $RC -ne 0 ]; then
      log_loop "[P1] ERROR src=$SOURCE wd=$WD key=$KEY rc=$RC"
      return 2
    fi
    log_action "action=started wd=$WD trial=$KEY attempt=1 uid=\"$BUG_UID\" source=$SOURCE"
    log_loop "[P1] STARTED src=$SOURCE wd=$WD key=$KEY uid=\"$BUG_UID\" used=${U}G"
    P1_STARTED=$((P1_STARTED+1))
    sleep "$INTER_START_SLEEP"
    return 0
  }

  # ---- Source A: NEWBUGS (newest first) ----
  # ~/sr refuses to run from /data/NEWBUGS (its cwd guard requires
  # /data/<6-digits>) so we spawn the reducer screen directly here. The
  # newbug_*.reducer.sh files are self-contained — running them produces the
  # same per-trial screen + reducer.log under /dev/shm that ~/sr would.
  if [ -d "$NEWBUGS_DIR" ]; then
    local NB EPOCH KEY BUG_UID LAST U SCRN
    while IFS= read -r NB; do
      [ "${P1_MEM_STOP:-0}" -eq 1 ] && break
      [ ! -s "$NB" ] && continue
      EPOCH="$(basename "$NB" .reducer.sh | sed 's/^newbug_//')"
      KEY="newbug_${EPOCH}"
      [ -n "$(screen_for_trial "$KEY")" ] && continue
      BUG_UID="$(get_uid "$NB")"
      [ -z "$BUG_UID" ] && { log_loop "[P1][nb] no-uid newbug=$EPOCH"; continue; }
      LAST="$(last_status_for_uid "$BUG_UID")"
      case "$LAST" in ready_p3|depged) continue ;; esac
      U=$(mem_used_g)
      if [ "$U" -ge "$MAX_MEMORY_IN_USE" ]; then
        log_loop "[P1] memory cap reached (${U}G >= ${MAX_MEMORY_IN_USE}G) — stopping starts"
        P1_MEM_STOP=1
        break
      fi
      mkdir -p "${NEWBUGS_DIR}/reducer.logs" 2>/dev/null
      SCRN="s${KEY}"
      screen -dmS "${SCRN}" bash -c \
        "cd '${NEWBUGS_DIR}' && './${KEY}.reducer.sh' 2>&1 | tee -a '${NEWBUGS_DIR}/reducer.logs/${KEY}.reducer.log'; bash"
      log_action "action=started wd=NEWBUGS trial=${EPOCH} attempt=1 uid=\"${BUG_UID}\" source=fireworks"
      log_loop "[P1] STARTED src=fireworks wd=NEWBUGS key=${KEY} uid=\"${BUG_UID}\" used=${U}G"
      P1_STARTED=$((P1_STARTED+1))
      sleep "$INTER_START_SLEEP"
    done < <(ls -t "$NEWBUGS_DIR"/newbug_*.reducer.sh 2>/dev/null)
  fi

  # ---- Source B: active workdirs in /data/results.list (pr's natural order) ----
  if [ -r "$RESULTS_LIST" ] && [ "${P1_MEM_STOP:-0}" -ne 1 ]; then
    local ACTIVE_WDS WD TRIAL TDIR BUG_UID LAST
    ACTIVE_WDS=$(awk '/^return 0/{exit} /^MON\[/{sub(/^MON\[[0-9]+\]=/, ""); print $1}' "$RESULTS_LIST")
    for WD in $ACTIVE_WDS; do
      [ "${P1_MEM_STOP:-0}" -eq 1 ] && break
      [ ! -d "/data/$WD" ] && continue
      while IFS= read -r TRIAL; do
        [ "${P1_MEM_STOP:-0}" -eq 1 ] && break
        [ -z "$TRIAL" ] && continue
        TDIR="/data/$WD/$TRIAL"
        [ ! -d "$TDIR" ] && continue
        [ ! -f "/data/$WD/reducer${TRIAL}.sh" ] && { P1_NOSCRIPT=$((P1_NOSCRIPT+1)); continue; }
        [ -n "$(screen_for_trial "$TRIAL")" ] && continue
        is_depged "$TRIAL" && continue
        BUG_UID="$(get_uid "$TDIR")"
        [ -z "$BUG_UID" ] && { log_loop "[P1] no-uid wd=$WD trial=$TRIAL"; continue; }
        LAST="$(last_status_for_uid "$BUG_UID")"
        case "$LAST" in ready_p3|depged) continue ;; esac
        _try_start "/data/$WD" "$TRIAL" "pqueryrun" "$WD" "$TRIAL" "$BUG_UID"
        [ $? -eq 3 ] && break
      done < <(cd "/data/$WD" && "${HOME}/pr" 2>/dev/null | sed -n 's/.*reducers \([0-9]\+\).*/\1/p')
    done
  fi

  log_loop "[P1] started=$P1_STARTED dedup=$P1_DEDUP no_script=$P1_NOSCRIPT mem_stop=$P1_MEM_STOP"
}

# ============================ Phase 2: hung handling (switch → depge) ============================
phase2_handle_hung(){
  local USED_NOW
  USED_NOW=$(mem_used_g)
  if [ "$USED_NOW" -ge "$MAX_MEMORY_IN_USE" ]; then
    log_loop "[P2] skipped — memory ${USED_NOW}G >= ${MAX_MEMORY_IN_USE}G"
    return
  fi

  local depged_count=0
  local LOG RPATH T WD BUG_UID

  # Enumerate running reducers with old log mtime
  while IFS= read -r LOG; do
    [ $depged_count -ge "$P2_CAP" ] && { log_loop "[P2] depge cap ($P2_CAP) reached"; break; }
    # Re-check memory mid-loop — switches/depges allocate, may push us over.
    USED_NOW=$(mem_used_g)
    if [ "$USED_NOW" -ge "$MAX_MEMORY_IN_USE" ]; then
      log_loop "[P2] memory cap reached mid-loop (${USED_NOW}G >= ${MAX_MEMORY_IN_USE}G) — stopping"
      break
    fi
    local AGE_MIN LMTIME
    LMTIME=$(stat -c %Y "$LOG" 2>/dev/null)
    [ -z "$LMTIME" ] && continue
    AGE_MIN=$(( ( $(date +%s) - LMTIME ) / 60 ))
    [ "$AGE_MIN" -le "$HANG_MIN" ] && continue
    RPATH=$(awk 'match($0, /\/data\/[0-9]+\/reducer[0-9]+\.sh/){print substr($0, RSTART, RLENGTH); exit}' "$LOG")
    if [ -z "$RPATH" ]; then
      # Also handle newbug_*.reducer.sh paths
      RPATH=$(awk 'match($0, /\/data\/NEWBUGS\/newbug_[0-9]+\.reducer\.sh/){print substr($0, RSTART, RLENGTH); exit}' "$LOG")
    fi
    [ -z "$RPATH" ] && continue

    # Parse out wd/trial (or NEWBUGS/epoch)
    local TDIR="" KEY=""
    if echo "$RPATH" | command grep -aq '/NEWBUGS/'; then
      local EPOCH
      EPOCH=$(echo "$RPATH" | sed -n 's|.*newbug_\([0-9]\+\)\.reducer\.sh|\1|p')
      WD=NEWBUGS; T="$EPOCH"; KEY="newbug_${EPOCH}"
      TDIR=""  # no trial dir for NEWBUGS
    else
      T=$(echo "$RPATH" | awk -F'reducer|[.]sh' '{print $(NF-1)}')
      WD=$(echo "$RPATH" | awk -F/ '{print $3}')
      KEY="$T"
      TDIR="/data/$WD/$T"
    fi
    local FULL_SCREEN
    FULL_SCREEN=$(screen_for_trial "$KEY")

    # Good-enough exemption: if newest _out is already short, the reducer is
    # likely just looping toward 3 lines from 5 — leave it alone, mark for P3.
    if [ -n "$TDIR" ] && [ -d "$TDIR" ]; then
      local LOUT LINES
      LOUT=$(newest_out "$TDIR")
      if [ -n "$LOUT" ]; then
        LINES=$(wc -l < "$LOUT" 2>/dev/null)
        if [ -n "$LINES" ] && [ "$LINES" -le "$SMALL_OUT_LINES" ]; then
          BUG_UID="$(get_uid "$TDIR")"
          log_action "action=ready_p3 wd=$WD trial=$T uid=\"$BUG_UID\" _out_lines=$LINES"
          log_loop "[P2] READY_P3 wd=$WD trial=$T lines=$LINES (hung age=${AGE_MIN}m but good enough)"
          P2_READY_P3=$((P2_READY_P3+1))
          continue
        fi
      fi
    fi

    # Get BUG_UID — from MYBUG (trial dir) or .string (NEWBUGS)
    if [ -n "$TDIR" ]; then
      BUG_UID="$(get_uid "$TDIR")"
    else
      BUG_UID="$(get_uid "$RPATH")"
    fi
    if [ -z "$BUG_UID" ]; then
      log_loop "[P2] no-uid wd=$WD trial=$T"
      continue
    fi

    # Decision: SWITCH or DEPGE?
    local FB_OUT UNTRIED ATTEMPTED
    FB_OUT="$(cd /data && ./find_uniqueids_or_errorlog "$BUG_UID" 2>/dev/null | \
      awk -F: '{print $1}' | awk -F/ '{if (NF>=2) print $1"/"$2}' | sort -u)"
    ATTEMPTED="$(attempts_for_uid "$BUG_UID")"
    UNTRIED=""
    local CAND
    for CAND in $FB_OUT; do
      if ! echo " $ATTEMPTED " | command grep -aqF " $CAND "; then
        # Verify the candidate is usable
        local CWD CT
        CWD=$(echo "$CAND" | awk -F/ '{print $1}')
        CT=$(echo "$CAND" | awk -F/ '{print $2}')
        [ -f "/data/$CWD/reducer${CT}.sh" ] || continue
        [ -n "$(screen_for_trial "$CT")" ] && continue
        UNTRIED="$CAND"
        break
      fi
    done

    if [ -n "$UNTRIED" ]; then
      # SWITCH
      local NEW_WD NEW_T
      NEW_WD=$(echo "$UNTRIED" | awk -F/ '{print $1}')
      NEW_T=$(echo "$UNTRIED" | awk -F/ '{print $2}')
      # Kill current
      if [ -n "$FULL_SCREEN" ]; then
        screen -S "$FULL_SCREEN" -X quit 2>/dev/null
      fi
      pkill -TERM -f "/data/$WD/reducer${T}.sh" 2>/dev/null
      sleep 2
      # Start new
      cd "/data/$NEW_WD" || continue
      local OUT RC
      OUT="$("${HOME}/sr" "$NEW_T" 2>&1)"; RC=$?
      local PRIOR_COUNT
      PRIOR_COUNT=$(echo "$ATTEMPTED" | tr ' ' '\n' | command grep -ac .)
      local NEW_ATTEMPT=$((PRIOR_COUNT+1))
      if [ $RC -eq 0 ] && ! echo "$OUT" | awk '/is already running/{f=1} END{exit !f}'; then
        log_action "action=switched wd=$NEW_WD trial=$NEW_T attempt=$NEW_ATTEMPT uid=\"$BUG_UID\" from=$WD/$T"
        log_loop "[P2] SWITCHED wd=$WD/$T → $NEW_WD/$NEW_T attempt=$NEW_ATTEMPT uid=\"$BUG_UID\""
        P2_SWITCHED=$((P2_SWITCHED+1))
      elif echo "$OUT" | awk '/is already running/{f=1} END{exit !f}'; then
        # sr saw the same BUG_UID running elsewhere — sibling already covered.
        log_loop "[P2] switch DEDUP $WD/$T → $NEW_WD/$NEW_T (sr: already running)"
      else
        log_loop "[P2] switch FAILED $WD/$T → $NEW_WD/$NEW_T rc=$RC"
      fi
    else
      # All candidates exhausted → DEPGE the current hung trial
      if [ -z "$FULL_SCREEN" ]; then
        log_loop "[P2] cannot depge wd=$WD trial=$T — no live screen"
        continue
      fi
      log_loop "[P2] DEPGING wd=$WD trial=$T age=${AGE_MIN}m (fb-list exhausted)"
      if apply_depge_direct "$T" "$FULL_SCREEN" "$LOG" "$WD" "$BUG_UID"; then
        log_action "action=depged wd=$WD trial=$T uid=\"$BUG_UID\""
        log_depged "wd=$WD trial=$T"
        P2_DEPGED=$((P2_DEPGED+1))
        depged_count=$((depged_count+1))
      fi
    fi
  done < <(command grep -la "Reducer PID" /dev/shm/*/reducer.log 2>/dev/null)

  log_loop "[P2] switched=$P2_SWITCHED depged=$P2_DEPGED ready_p3=$P2_READY_P3"
}

# apply_depge_direct <trial> <screen> <log> <wd> <uid>
# Patches the reducer in place (FORCE_SKIPV=1, STAGE1_LINES=3, MULTI_THREADS=7)
# after killing the old reducer + screen, then restarts via sr. Returns 0 on
# verified success, 1 on any failure (with reason logged).
#
# We patch directly rather than stuffing '~/depge' into the live screen because
# `sed -i` silently fails when /data has no room for its temp+rename; we gate
# on disk% first and verify mtime + each value after.
apply_depge_direct(){
  local T="$1" FULL="$2" LOG="$3" WD="$4"
  local REDUCER="/data/$WD/reducer${T}.sh"

  if [ ! -w "$REDUCER" ]; then
    log_loop "[P2] depge FAIL reason=not-writable path=$REDUCER"
    return 1
  fi

  # sed -i writes a temp next to the target then renames. With /data near full
  # the rename can fail and sed exits 0 leaving the original untouched.
  local DATA_PCT
  DATA_PCT=$(df /data --output=pcent 2>/dev/null | tail -1 | tr -dc 0-9)
  if [ -n "$DATA_PCT" ] && [ "$DATA_PCT" -ge "$DATA_HARD_CAP" ]; then
    log_loop "[P2] depge FAIL reason=disk-gate /data=${DATA_PCT}% >= ${DATA_HARD_CAP}%"
    return 1
  fi

  # Kill the old reducer + its screen first — sr's UniqueID dedup would
  # otherwise refuse to relaunch (same BUG_UID already "running").
  [ -n "$FULL" ] && screen -S "$FULL" -X quit 2>/dev/null
  pkill -TERM -f "/data/$WD/reducer${T}.sh" 2>/dev/null
  # Reap any '~/depge <T>' processes still parked on this workdir.
  local PID
  for PID in $(pgrep -f "depge ${T}\b" 2>/dev/null); do
    [ "$(readlink "/proc/${PID}/cwd" 2>/dev/null)" = "/data/$WD" ] || continue
    log_loop "[P2] reaping stale depge pid=$PID wd=$WD trial=$T"
    kill -TERM "$PID" 2>/dev/null
  done
  sleep 3

  # Snapshot pre-state — verify after sed that values changed AND mtime moved.
  local PRE_MTIME PRE_MT PRE_SL PRE_FSK
  PRE_MTIME=$(stat -c %Y "$REDUCER" 2>/dev/null)
  PRE_MT=$(awk -F= '/^MULTI_THREADS=/{print $2+0; exit}' "$REDUCER")
  PRE_SL=$(awk -F= '/^STAGE1_LINES=/{print $2+0; exit}' "$REDUCER")
  PRE_FSK=$(awk -F= '/^FORCE_SKIPV=/{print $2+0; exit}' "$REDUCER")

  # All three patches in one sed call (single temp + single rename).
  if ! sed -i \
    -e 's|^FORCE_SKIPV=0|FORCE_SKIPV=1|' \
    -e 's|^STAGE1_LINES=[0-9]\+|STAGE1_LINES=3|' \
    -e 's|^MULTI_THREADS=[0-9]\+|MULTI_THREADS=7|' \
    "$REDUCER" 2>/dev/null; then
    log_loop "[P2] depge FAIL reason=sed-error path=$REDUCER"
    return 1
  fi

  local POST_MTIME POST_MT POST_SL POST_FSK
  POST_MTIME=$(stat -c %Y "$REDUCER" 2>/dev/null)
  POST_MT=$(awk -F= '/^MULTI_THREADS=/{print $2+0; exit}' "$REDUCER")
  POST_SL=$(awk -F= '/^STAGE1_LINES=/{print $2+0; exit}' "$REDUCER")
  POST_FSK=$(awk -F= '/^FORCE_SKIPV=/{print $2+0; exit}' "$REDUCER")

  if [ "$POST_MTIME" = "$PRE_MTIME" ]; then
    log_loop "[P2] depge FAIL reason=mtime-unchanged (sed -i did not commit; likely silent disk-full)"
    return 1
  fi
  if [ "$POST_MT" != "7" ] || [ "$POST_SL" != "3" ] || [ "$POST_FSK" != "1" ]; then
    log_loop "[P2] depge FAIL reason=values-not-applied pre={MT=$PRE_MT SL=$PRE_SL FSK=$PRE_FSK} post={MT=$POST_MT SL=$POST_SL FSK=$POST_FSK}"
    return 1
  fi

  # Restart via sr — fresh screen + reducer.log under a new /dev/shm/<epoch>.
  ( cd "/data/$WD" && "${HOME}/sr" "$T" ) >/dev/null 2>&1
  local SR_RC=$?
  if [ $SR_RC -ne 0 ]; then
    # Patch is applied; next pass's P1 will see no live screen and launch it.
    log_loop "[P2] depge WARN reason=sr-restart-failed rc=$SR_RC (next pass picks it up)"
    return 0
  fi
  log_loop "[P2] depge OK wd=$WD trial=$T post={MT=7 SL=3 FSK=1}"
  return 0
}

# ============================ Phase 3: copy-through / queue ============================
# For each trial that has a non-empty _out, no _claude_reduced yet, no live
# reducer, no depge mark, no REPLICATION_ACTIVE, and a still-extant basedir:
#   _out <= SMALL_OUT_LINES  → cp verbatim to <basename>_claude_reduced
#   _out >  SMALL_OUT_LINES  → enqueue to /data/watchdog/ai_queue/ (real
#                              SQL simplification needs human/AI judgment).
phase3_reduce(){
  [ "$P345_OK" -ne 1 ] && { log_loop "[P3] skipped (disk gate)"; return; }

  local copied=0
  # Scan all /data/NNNNNN workdirs (historical + active).
  # Historical _out files accumulate across days; P3 not limited to active workdirs.
  local WD_PATH WD
  for WD_PATH in /data/[0-9]*/; do
    [ $copied -ge "$P3_CAP" ] && break
    WD=$(basename "$WD_PATH")
    local TRIALDIR TRIAL
    for TRIALDIR in "${WD_PATH}"[0-9]*/; do
      [ $copied -ge "$P3_CAP" ] && break
      [ ! -d "$TRIALDIR" ] && continue
      [ -f "${TRIALDIR}REPLICATION_ACTIVE" ] && continue
      TRIAL=$(basename "$TRIALDIR")
      pgrep -af "/data/${WD}/reducer${TRIAL}.sh" >/dev/null 2>&1 && continue
      is_depged "$TRIAL" && continue
      local LOUT
      LOUT=$(newest_out "$TRIALDIR")
      [ -z "$LOUT" ] && continue
      local BASENAME="${LOUT##*/}"; BASENAME="${BASENAME%%_out*}"
      local DEST="${TRIALDIR}${BASENAME}_claude_reduced"
      [ -f "$DEST" ] && continue
      local LINES
      LINES=$(wc -l < "$LOUT" 2>/dev/null)
      [ -z "$LINES" ] || [ "$LINES" -le 0 ] && continue

      # Verify basedir still exists
      local BD
      BD=$(basedir_from_reducer "/data/${WD}/reducer${TRIAL}.sh")
      if [ -z "$BD" ] || [ ! -d "$BD" ]; then
        log_loop "[P3] skip basedir-missing wd=$WD trial=$TRIAL basedir=$BD"
        continue
      fi

      if [ "$LINES" -le "$SMALL_OUT_LINES" ]; then
        # Copy-through
        if cp "$LOUT" "$DEST" 2>/dev/null; then
          # Verify the copy succeeded (disk-full safety)
          if [ ! -s "$DEST" ]; then
            rm -f "$DEST"
            log_loop "[P3] COPY_FAIL wd=$WD trial=$TRIAL lines=$LINES reason=0byte-after-cp"
            continue
          fi
          log_loop "[P3] COPIED wd=$WD trial=$TRIAL lines=$LINES reason=already-minimal"
          P3_COPIED=$((P3_COPIED+1))
          copied=$((copied+1))
          THIS_PASS_P3_TRIALS+=("$WD/$TRIAL")
        else
          log_loop "[P3] COPY_FAIL wd=$WD trial=$TRIAL lines=$LINES"
        fi
      else
        # Too long → AI queue
        local KEY="p3_${WD}_${TRIAL}"
        local BUG_UID
        BUG_UID="$(get_uid "$TRIALDIR")"
        enqueue_ai "$KEY" "p3-reduction-needed" \
          "wd=$WD" "trial=$TRIAL" "phase=3" "lines=$LINES" \
          "out_path=$LOUT" "basedir=$BD" "uid=$BUG_UID"
        P3_QUEUED_AI=$((P3_QUEUED_AI+1))
      fi
    done
  done

  log_loop "[P3] copied=$P3_COPIED queued_ai=$P3_QUEUED_AI"
}

# ============================ Phase 4: bug report (~/b) ============================
# For each trial with _claude_reduced and no claude_report.txt yet (skipping
# replication and depged trials): cp the SQL to <BASEDIR>/in.sql, cd into the
# basedir, run ~/b (variant SAN/MSAN derived from basedir name), capture
# stdout+stderr to claude_report.txt. ~/b takes 10-30 min — cap is 2 per pass.
phase4_report(){
  [ "$P345_OK" -ne 1 ] && { log_loop "[P4] skipped (disk gate)"; return; }

  local done_count=0
  local WD_PATH WD TRIAL TRIALDIR

  # Prefer trials touched this pass (THIS_PASS_P3_TRIALS)
  local candidates=() SEEN=""
  local t
  for t in "${THIS_PASS_P3_TRIALS[@]}"; do
    candidates+=("$t"); SEEN="$SEEN $t"
  done
  for WD_PATH in /data/[0-9]*/; do
    WD=$(basename "$WD_PATH")
    for TRIALDIR in "${WD_PATH}"[0-9]*/; do
      [ ! -d "$TRIALDIR" ] && continue
      TRIAL=$(basename "$TRIALDIR")
      local pair="$WD/$TRIAL"
      echo " $SEEN " | command grep -aqF " $pair " && continue
      candidates+=("$pair")
    done
  done

  local PAIR
  for PAIR in "${candidates[@]}"; do
    [ $done_count -ge "$P4_CAP" ] && break
    WD=$(echo "$PAIR" | awk -F/ '{print $1}')
    TRIAL=$(echo "$PAIR" | awk -F/ '{print $2}')
    TRIALDIR="/data/$WD/$TRIAL"
    [ ! -d "$TRIALDIR" ] && continue
    [ -f "${TRIALDIR}/REPLICATION_ACTIVE" ] && continue  # repl skips P4
    is_depged "$TRIAL" && continue
    # Need _claude_reduced present, no claude_report.txt
    local REDUCED
    REDUCED=$(ls "$TRIALDIR"/*_claude_reduced 2>/dev/null | head -1)
    [ -z "$REDUCED" ] || [ ! -s "$REDUCED" ] && continue
    [ -s "$TRIALDIR/claude_report.txt" ] && continue
    # Need basedir
    local BD
    BD=$(basedir_from_reducer "/data/${WD}/reducer${TRIAL}.sh")
    [ -z "$BD" ] || [ ! -d "$BD" ] && continue
    # Variant
    local VARIANT=""
    case "$BD" in
      *UBASAN*) VARIANT="SAN" ;;
      *MSAN*)   VARIANT="MSAN" ;;
    esac
    # Run
    log_loop "[P4] start wd=$WD trial=$TRIAL variant=${VARIANT:-default} basedir=$BD"
    cp "$REDUCED" "$BD/in.sql" 2>/dev/null || { log_loop "[P4] cp-failed wd=$WD trial=$TRIAL"; continue; }
    ( cd "$BD" && "${HOME}/b" $VARIANT ) > "$TRIALDIR/claude_report.txt" 2>&1
    local RC=$?
    local BYTES LAST
    BYTES=$(stat -c %s "$TRIALDIR/claude_report.txt" 2>/dev/null)
    BYTES=${BYTES:-0}
    LAST=$(tail -1 "$TRIALDIR/claude_report.txt" 2>/dev/null | cut -c1-160)
    local TOKEN
    if [ "$RC" -eq 0 ] && [ "$BYTES" -gt 0 ] && \
       command grep -qaE "/BUG REPORT|Bug String|Starting bug report" "$TRIALDIR/claude_report.txt"; then
      TOKEN=REPORT_GENERATED
      P4_GENERATED=$((P4_GENERATED+1))
    elif [ "$RC" -eq 0 ]; then
      TOKEN=REPORT_PARTIAL
      P4_PARTIAL=$((P4_PARTIAL+1))
    else
      TOKEN=REPORT_FAIL
      P4_FAILED=$((P4_FAILED+1))
    fi
    log_loop "[P4] $TOKEN wd=$WD trial=$TRIAL variant=${VARIANT:-default} rc=$RC report_bytes=$BYTES last=\"$LAST\""
    THIS_PASS_P4_TRIALS+=("$WD/$TRIAL")
    done_count=$((done_count+1))
  done

  log_loop "[P4] generated=$P4_GENERATED partial=$P4_PARTIAL failed=$P4_FAILED"
}

# ============================ Phase 5: MTR generation ============================
# Convert reduced SQL into a runnable mtr testcase, install into the basedir's
# test tree, run ./mtra --record. Iteration order: trials touched in this pass
# first, then any other eligible trial.
#   REPLICATION_ACTIVE  → use a repl_*.template (XA/gtid → repl_stmt;
#                         gtid_strict → repl_mixed_parallel; else repl_row);
#                         source SQL = newest _out (no _claude_reduced needed)
#   Spider engine       → enqueue AI (template choice non-trivial)
#   Otherwise (vanilla) → emit with --source include/have_innodb.inc + add
#                         ENGINE=InnoDB to bare CREATE TABLEs
phase5_mtr(){
  [ "$P345_OK" -ne 1 ] && { log_loop "[P5] skipped (disk gate)"; return; }

  local done_count=0
  local PAIR WD TRIAL TRIALDIR

  # Priority list: this pass's P3 + P4 trials, then scan for others
  local candidates=() SEEN=""
  for PAIR in "${THIS_PASS_P4_TRIALS[@]}" "${THIS_PASS_P3_TRIALS[@]}"; do
    echo " $SEEN " | command grep -aqF " $PAIR " && continue
    candidates+=("$PAIR"); SEEN="$SEEN $PAIR"
  done
  local WD_PATH
  for WD_PATH in /data/[0-9]*/; do
    WD=$(basename "$WD_PATH")
    for TRIALDIR in "${WD_PATH}"[0-9]*/; do
      [ ! -d "$TRIALDIR" ] && continue
      TRIAL=$(basename "$TRIALDIR")
      local pair="$WD/$TRIAL"
      echo " $SEEN " | command grep -aqF " $pair " && continue
      candidates+=("$pair"); SEEN="$SEEN $pair"
    done
  done

  for PAIR in "${candidates[@]}"; do
    [ $done_count -ge "$P5_CAP" ] && break
    WD=$(echo "$PAIR" | awk -F/ '{print $1}')
    TRIAL=$(echo "$PAIR" | awk -F/ '{print $2}')
    TRIALDIR="/data/$WD/$TRIAL"
    [ ! -d "$TRIALDIR" ] && continue

    # Skip if _claude_mtr already produced
    [ -n "$(ls "$TRIALDIR"/*_claude_mtr 2>/dev/null | head -1)" ] && continue

    local IS_REPL=0
    [ -f "${TRIALDIR}/REPLICATION_ACTIVE" ] && IS_REPL=1

    # Choose source SQL
    local SOURCE_SQL=""
    if [ $IS_REPL -eq 1 ]; then
      # Replication shortcut — use newest _out directly (no _claude_reduced required)
      SOURCE_SQL=$(newest_out "$TRIALDIR")
    else
      # Non-repl — need _claude_reduced
      SOURCE_SQL=$(ls "$TRIALDIR"/*_claude_reduced 2>/dev/null | head -1)
    fi
    [ -z "$SOURCE_SQL" ] || [ ! -s "$SOURCE_SQL" ] && continue

    # Basedir
    local BD
    BD=$(basedir_from_reducer "/data/${WD}/reducer${TRIAL}.sh")
    if [ -z "$BD" ] || [ ! -d "$BD" ]; then
      log_loop "[P5] skip basedir-missing wd=$WD trial=$TRIAL basedir=$BD"
      continue
    fi

    # Detect test-tree layout
    local MT TEST_DIR TEST_T TEST_R
    MT=$(mt_layout "$BD")
    if [ -z "$MT" ]; then
      log_loop "[P5] skip no-test-tree wd=$WD trial=$TRIAL basedir=$BD"
      continue
    fi
    if [ "$MT" = "mariadb-test" ]; then
      TEST_DIR="$BD/mariadb-test/main"
      TEST_T="$TEST_DIR"; TEST_R="$TEST_DIR"
    else
      TEST_T="$BD/mysql-test/t"; TEST_R="$BD/mysql-test/r"
    fi

    # Detect complexity — if so, queue for AI rather than attempt mechanical
    local TEMPLATE=""
    if [ $IS_REPL -eq 1 ]; then
      # Pick replication template
      if command grep -qaiE 'xa [se][at][a-z]*|gtid_domain_id|slave_parallel_mode.*aggressive' "$SOURCE_SQL"; then
        TEMPLATE="$MTR_TEMPLATES/repl_stmt.template.test"
      elif command grep -qaiE 'gtid_strict_mode' "$SOURCE_SQL"; then
        TEMPLATE="$MTR_TEMPLATES/repl_mixed_parallel.template.test"
      else
        TEMPLATE="$MTR_TEMPLATES/repl_row.template.test"
      fi
    elif command grep -qaiE 'engine[[:space:]]*=[[:space:]]*spider|ha_spider' "$SOURCE_SQL"; then
      # Spider — enqueue AI (template choice ambiguous: single vs master-slave vs partition)
      local BUG_UID; BUG_UID="$(get_uid "$TRIALDIR")"
      enqueue_ai "p5_${WD}_${TRIAL}" "p5-spider-template-selection" \
        "wd=$WD" "trial=$TRIAL" "phase=5" "source_sql=$SOURCE_SQL" \
        "basedir=$BD" "uid=$BUG_UID" "templates_dir=$MTR_TEMPLATES"
      P5_QUEUED_AI=$((P5_QUEUED_AI+1))
      continue
    fi

    # Generate MTR
    local BASENAME="${SOURCE_SQL##*/}"
    BASENAME="${BASENAME%_claude_reduced}"; BASENAME="${BASENAME%%_out*}"
    local MTR_FILE="$TRIALDIR/${BASENAME}_claude_mtr"

    if [ -n "$TEMPLATE" ] && [ -r "$TEMPLATE" ]; then
      # Template-based (replication): splice SQL into the <<< marker
      awk -v sql_file="$SOURCE_SQL" '
        /# <<< reduced SQL goes here/ {
          while ((getline line < sql_file) > 0) print line
          close(sql_file)
          next
        }
        { print }
      ' "$TEMPLATE" > "$MTR_FILE"
    else
      # Vanilla non-repl: prepend includes + ENGINE=InnoDB fixup. The fixup is
      # line-local (only patches CREATE TABLE statements that fit on one line);
      # multi-line CREATEs reach the basedir as-is — review the _claude_mtr
      # by hand if the bug needs explicit InnoDB.
      {
        echo "--source include/have_innodb.inc"
        echo ""
        awk '{
          if ($0 ~ /CREATE[[:space:]]+TABLE/ && $0 !~ /ENGINE=/) {
            sub(/;[[:space:]]*$/, " ENGINE=InnoDB;", $0)
          }
          print
        }' "$SOURCE_SQL"
      } > "$MTR_FILE"
    fi

    if [ ! -s "$MTR_FILE" ]; then
      log_loop "[P5] write-fail wd=$WD trial=$TRIAL"
      rm -f "$MTR_FILE"
      continue
    fi

    # Validate with ./mtra --record (capture stdout+stderr to parse for outcome)
    local TEST_NAME="claude_${TRIAL}"
    cp "$MTR_FILE" "${TEST_T}/${TEST_NAME}.test" 2>/dev/null
    touch "${TEST_R}/${TEST_NAME}.result" 2>/dev/null
    local MTRA_OUT MTRA_RC=0
    MTRA_OUT=$( ( cd "$BD/$MT" && timeout 180 ./mtra --record "$TEST_NAME" 2>&1 ) ) || MTRA_RC=$?

    # Outcome detection:
    #   BUG_REPRODUCED  — mtra recorded a failure (bug-producing testcase, expected for crash repros)
    #   PASS            — mtra ran cleanly (test didn't reproduce the bug; may need review)
    #   VALIDATION_ERROR — mtra itself errored (timeout, missing tree, etc.)
    local OUTCOME
    if [ "$MTRA_RC" -ne 0 ] && ! echo "$MTRA_OUT" | command grep -qaE 'Failing test|Failed [0-9]'; then
      OUTCOME=VALIDATION_ERROR
    elif echo "$MTRA_OUT" | command grep -qaE 'Failing test\(s\):|Failed [0-9]+/[0-9]+ tests'; then
      OUTCOME=BUG_REPRODUCED
      P5_BUG_REPRO=$((P5_BUG_REPRO+1))
    else
      OUTCOME=PASS
    fi
    P5_GENERATED=$((P5_GENERATED+1))
    log_loop "[P5] MTR_GENERATED wd=$WD trial=$TRIAL template=$(basename "${TEMPLATE:-vanilla}") mt=$MT outcome=$OUTCOME mtra_rc=$MTRA_RC"

    # Cleanup basedir test file (permanent copy stays in trial dir)
    rm -f "${TEST_T}/${TEST_NAME}.test" "${TEST_R}/${TEST_NAME}.result"

    done_count=$((done_count+1))
  done

  log_loop "[P5] generated=$P5_GENERATED queued_ai=$P5_QUEUED_AI"
}

# ============================ Phase 6: 0-line _out repair ============================
# Reducer occasionally produces a 0-byte _out (disk-space hiccup mid-write).
# Such a trial looks "done" to P3 but isn't reducible. Wipe its 17*.sql +
# *_out* + reducer<N>.sh and run `~/pg ONCEONLY` in the workdir to regenerate.
# Uncapped.
phase6_repair_zero_outs(){
  [ "$P345_OK" -ne 1 ] && { log_loop "[P6] skipped (disk gate)"; return; }

  local WD_PATH WD TRIALDIR TRIAL
  for WD_PATH in /data/[0-9]*/; do
    WD=$(basename "$WD_PATH")
    for TRIALDIR in "${WD_PATH}"[0-9]*/; do
      [ ! -d "$TRIALDIR" ] && continue
      TRIAL=$(basename "$TRIALDIR")
      # Skip if reducer is live for this trial
      pgrep -af "/data/${WD}/reducer${TRIAL}.sh\b" >/dev/null 2>&1 && continue
      # Find newest _out (any flavour) in trial dir
      local OUT
      OUT=$(ls -t "$TRIALDIR"*_out* 2>/dev/null | head -1)
      [ -z "$OUT" ] && continue
      # Only act when it's 0 bytes
      [ -s "$OUT" ] && continue
      [ ! -f "/data/$WD/reducer${TRIAL}.sh" ] && continue
      log_loop "[P6] regen wd=$WD trial=$TRIAL reason=zero-line-out path=$OUT"
      # Targeted chain (not '*_out*') so we never remove a sibling that just
      # happens to contain '_out' as a substring.
      rm -f "${TRIALDIR}"17*.sql 2>/dev/null
      find "${TRIALDIR%/}" -maxdepth 1 -type f \
        \( -name '*_out' -o -name '*_out_out' -o -name '*_out_out_out' \
           -o -name '*_out_out_out_out' \) -delete 2>/dev/null
      rm -f "/data/$WD/reducer${TRIAL}.sh" 2>/dev/null
      ( cd "/data/$WD" && "${HOME}/pg" ONCEONLY ) >/dev/null 2>&1
      if [ -f "/data/$WD/reducer${TRIAL}.sh" ]; then
        log_loop "[P6] regen-ok wd=$WD trial=$TRIAL"
        P6_REGEN=$((P6_REGEN+1))
      else
        log_loop "[P6] regen-fail wd=$WD trial=$TRIAL (~/pg didn't recreate reducer${TRIAL}.sh)"
        P6_FAILED=$((P6_FAILED+1))
      fi
    done
  done
  log_loop "[P6] regen=$P6_REGEN failed=$P6_FAILED"
}

# ============================ Main ============================
main(){
  # Guard against running in parallel with itself
  local LOCKFILE=/data/watchdog/state/watchdog_curate.lock
  mkdir -p "$(dirname "$LOCKFILE")" 2>/dev/null
  exec 9>"$LOCKFILE" 2>/dev/null || true
  if ! flock -n 9 2>/dev/null; then
    log_loop "[curate] lock held — another instance running, exiting"
    exit 0
  fi

  # Ensure log files exist
  touch "$ATTEMPTS_LOG" "$DEPGED_LOG" "$LOOP_LOG" 2>/dev/null || true
  mkdir -p "$AI_QUEUE" 2>/dev/null

  local START
  START=$(date +%s)

  phase0_gates
  cleanup_finished_screens     # P0A — kill idle bash screens (frees memory before P1)
  cleanup_stuck_no_repro       # P0B — kill reducers stuck without reproducing
  phase1_start_reducers
  phase2_handle_hung
  phase3_reduce
  phase4_report
  phase5_mtr
  phase6_repair_zero_outs

  local ELAPSED
  ELAPSED=$(( $(date +%s) - START ))

  local SUMMARY
  SUMMARY="[curate] end elapsed=${ELAPSED}s"
  SUMMARY="$SUMMARY p0a_killed=$P0A_KILLED"
  SUMMARY="$SUMMARY p0b_killed=$P0B_KILLED"
  SUMMARY="$SUMMARY p1=$P1_STARTED/dedup=$P1_DEDUP/mem_stop=$P1_MEM_STOP"
  SUMMARY="$SUMMARY p2=switched=$P2_SWITCHED/depged=$P2_DEPGED/ready_p3=$P2_READY_P3"
  SUMMARY="$SUMMARY p3=$P3_COPIED/queued=$P3_QUEUED_AI"
  SUMMARY="$SUMMARY p4=gen=$P4_GENERATED/partial=$P4_PARTIAL/fail=$P4_FAILED"
  SUMMARY="$SUMMARY p5=gen=$P5_GENERATED/bug_repro=$P5_BUG_REPRO/queued=$P5_QUEUED_AI"
  SUMMARY="$SUMMARY p6=regen=$P6_REGEN/failed=$P6_FAILED"
  log_loop "$SUMMARY"
  echo "$SUMMARY"
}

main "$@"
