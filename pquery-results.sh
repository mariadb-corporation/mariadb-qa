#!/bin/bash
# Created by Roel Van de Paar, Percona LLC

# Usage example"
#  For normal output            : $./pquery-results.sh
#  For Valgrind + normal output : $./pquery-results.sh valgrind

# Setup
set +H  # Disables history substitution and avoids  -bash: !: event not found  like errors

# Internal variables
SCRIPT_PWD="$(readlink -f "${0}" | sed "s|$(basename "${0}")||;s|/\+$||")"
VALGRINDOUTPUT=0

if [ "$1" == "valgrind" ]; then
  VALGRINDOUTPUT=1
fi

if [ "${PWD}" == "/test" -o "${PWD}" == "/data" -o "${PWD}" == "${HOME}" ]; then
  if [ "$(ls pquery*log 2>/dev/null | wc -l)" -eq 0 ]; then
    echo "Assert: you seem to be running this from an incorrect directory ("${PWD}"), we expected pquery*log to exist and be in a WORKDIR, e.g. for example '/data/123456'. Terminating."
    exit 1
  fi
fi

# If there are ongoing pquery runs, do an automated check and report if there were issues with the pr vs ge count
if [ -r "${HOME}/check" -a -x "${HOME}/check" ]; then
  ${HOME}/check 'automation'
fi

# Check if this is a MDG run
if [ "$(grep --binary-files=text 'MDG Mode:' ./pquery-run.log 2>/dev/null | sed 's|^.*MDG Mode[: \t]*||' )" == "TRUE" ]; then
  MDG=1
  ERROR_LOG_LOC="*/node*/node*.err"
else
  MDG=0
  ERROR_LOG_LOC="*/log/*.err"
fi

# Check if this is a group replication run
if [ "$(grep --binary-files=text 'Group Replication Mode:' ./pquery-run.log 2>/dev/null | sed 's|^.*Group Replication Mode[: \t]*||')" == "TRUE" ]; then
  GRP_RPL=1
else
  GRP_RPL=0
fi

# Per-instance temp files. This script runs concurrently in the same workdir: by hand via ~/pr, from /data/results (alias `r`), and twice per loop from the ge<workdir> pquery-go-expert.sh screen. Fixed temp file names in the workdir let one instance truncate or delete another instance's files mid-run, which shows up as awk/grep "No such file or directory" aborts and, worse, silently wrong counts. One dir per instance, removed on exit.
_PQ_TMPDIR="$(mktemp -d)" || { echo "Assert: mktemp -d failed, cannot create a temporary directory"; exit 1; }
trap 'rm -rf "${_PQ_TMPDIR}"' EXIT
TEXTS_CACHE="${_PQ_TMPDIR}/texts_cache"
STRINGS_CACHE="${_PQ_TMPDIR}/strings_cache"
ALLERRLOGS="${_PQ_TMPDIR}/allerrlogs"
ERRORLOGS="${_PQ_TMPDIR}/errorlogs"
ERROR_SIGS="${_PQ_TMPDIR}/error_sigs"
LISTED_UIDS="${_PQ_TMPDIR}/listed_uids"

# The scans below read each error log in full. A log over 10MB is replaced by a copy of its first and last 5MB, as reading a runaway log in full takes minutes. A capped copy sits under CAPPED_LOGS_DIR, keeping the trial directory in its path, so TRIAL_FROM_LOG strips that one prefix wherever a trial number is read from a log path
CAPPED_LOGS_DIR="${_PQ_TMPDIR}/logs"
mkdir -p "${CAPPED_LOGS_DIR}"
CAPPED_LOGS="$("${SCRIPT_PWD}/capped_error_log.sh" "${CAPPED_LOGS_DIR}" ${ERROR_LOG_LOC} 2>/dev/null | tr '\n' ' ')"
[ ! -z "${CAPPED_LOGS}" ] && ERROR_LOG_LOC="${CAPPED_LOGS}"  # Capping that cannot run leaves the logs as they are. Taking its empty output would drop every log, and every scan below would then report nothing at all
CAPPED_LOGS=
TRIAL_FROM_LOG="s|^${CAPPED_LOGS_DIR}/||"

# String (TEXT=string) specific trials (commonly these are MODE=3 trials)
NTS=  # Backwards compatible (and manually modified reducers scanning without using new text string)
if grep -qi --binary-files=text "^USE_NEW_TEXT_STRING=1" reducer*.sh 2>/dev/null; then
  NTS='-Fi' # New text string (i.e. no regex, exact text string) mode
fi
# Terminal width, used to right-position the '(Seen ...)' column of the UniqueID list. Stays 0 when stdout is not a terminal (~/pg redirects to a log), which keeps the fixed-width layout so stored output is unaffected.
# Colours follow the echoit() scale in pquery-run.sh and the dim note in ~/sr: DIM for an error-log entry and for the summary blocks, ORANGE for a framework problem. A crash signature, a sanitizer report and the MODE=4 line all rank the same, and read green once any of their trials has an _out file, so reduction is running or done, red when a trial was started but no _out came of it, and #E59E7A while nothing was started at all. An UNTYPED entry uses #D47147, because it asks for a uid_prefix() rule and is meant to catch the eye. All empty when stdout is not a terminal, so a redirected run stays plain text.
SCREEN_WIDTH=0
C_DIM=$'\e[2m' C_SIG_OR_SAN=$'\e[32m' C_STALLED=$'\e[31m' C_UNREDUCED=$'\e[38;2;229;158;122m' C_UNTYPED=$'\e[38;2;212;113;71m' C_ORANGE=$'\e[33m' C_OFF=$'\e[0m'
if [ -t 1 ]; then
  SCREEN_WIDTH="$(tput cols 2>/dev/null)"
else
  C_DIM= C_SIG_OR_SAN= C_STALLED= C_UNREDUCED= C_UNTYPED= C_ORANGE= C_OFF=
fi
case "${SCREEN_WIDTH}" in (''|*[!0-9]*) SCREEN_WIDTH=0 ;; esac
TRIALS_EXECUTED=$(cat pquery-run.log 2>/dev/null | grep --binary-files=text -o "==.*TRIAL.*==" 2>/dev/null | tail -n1 | sed 's|[^0-9]*||;s|[ \t=]||g')
echo "=== [ cd ${PWD} ] UniqueID's (${TRIALS_EXECUTED} trials done, $(ls reducer*.sh qcreducer*.sh 2>/dev/null | wc -l) remaining reducers) nf: non-filtered bugs ==="

# Hang/timeout signature scan over SHUTDOWN_TIMEOUT_ISSUE-marked trials. Consumed by the TRIALS_MDEV_30418 / MASTER_POS_WAIT / MDEV_22727 / NET_RETRY / MDEV_25611 / MDEV_35064 blocks (all inside the MDG=0 && GRP_RPL=0 main branch), each looking for a different SQL pattern within those trials' default.node.tld_thread-*.sql. One batched grep populates a "<file>:<matched_line>" cache that _pq_trials_with dispatches over.
_HANG_TRIALS=
_PQ_SQL_FIRSTPASS=
if [ "${MDG}" -eq 0 ] && [ "${GRP_RPL}" -eq 0 ]; then
  _HANG_TRIALS="$(ls --color=never [0-9]*/SHUTDOWN_TIMEOUT_ISSUE 2>/dev/null | sed 's|/.*||' | sort -u)"
  if [ -n "${_HANG_TRIALS}" ]; then
    _PQ_SQL_FIRSTPASS="${_PQ_TMPDIR}/hang_sql_firstpass"
    if [ -n "${_PQ_SQL_FIRSTPASS}" ]; then
      _hang_sql=()
      for _t in ${_HANG_TRIALS}; do
        for _f in "${_t}"/default.node.tld_thread-*.sql; do
          [ -e "${_f}" ] && _hang_sql+=("${_f}")
        done
      done
      if [ ${#_hang_sql[@]} -gt 0 ]; then
        grep --binary-files=text -EHi \
          -e 'set.*global.*wsrep_cluster_address' \
          -e 'set.*global.*wsrep_slave_threads' \
          -e 'set.*aria_group_commit_interval' \
          -e 'set.*aria_group_commit.*hard' \
          -e 'innodb_flush_log_at_timeout' \
          -e 'RESET[ \t]*MASTER' \
          -e 'set.*net_retry_count' \
          -e 'start.*slave' \
          -e 'master_pos_wait' \
          "${_hang_sql[@]}" 2>/dev/null > "${_PQ_SQL_FIRSTPASS}"
      fi
      _hang_sql= _t= _f=
    fi
  fi
fi
# Trial numbers whose first-pass-cache line matches the given regex. Cache is restricted to hang trials; no further SHUTDOWN_TIMEOUT_ISSUE filter needed at the call site.
_pq_trials_with() { [ -s "${_PQ_SQL_FIRSTPASS}" ] && grep -Ei "$1" "${_PQ_SQL_FIRSTPASS}" 2>/dev/null | sed 's|/.*||' | sort -u; }
# Current location checks
if [ $(ls ./*/*.sql 2>/dev/null | wc -l) -eq 0 ]; then
  if [ "$(echo ${PWD} | sed 's|.*/||')" != "ERR_REDUCERS" -a $(ls ./*.sql 2>/dev/null | wc -l) -eq 0  ]; then
    echo "Assert: no pquery trials (with logging - i.e. ./*/*.sql) were found in this directory (or they were all cleaned up already) (${PWD})"
    echo "Please make sure to execute this script from within the pquery working directory!"
    exit 1
  fi
elif [ $(ls ./reducer* ./qcreducer* 2>/dev/null | wc -l) -eq 0 ]; then
  echo "Note: no reducer scripts were found in this directory."
  echo "  Did you forget to run ${SCRIPT_PWD}/pquery-prep-red.sh (or better ~/pg)?"
  echo "  Or, if you used ~/gomd to start this run, it is possible that ~/pg has not (loop) processed this directory yet"
  exit 1
fi

# MODE 3 TRIALS
ORIG_IFS=$IFS; IFS=$'\n'  # Use newline seperator instead of space seperator in the for loop
# Single head-scan of all reducer scripts: "<file>:   TEXT='...'" rows (-m1 stops at the first TEXT= line per file, so only file heads are read). All per-STRING matching below, and the footer's already-listed-UID filter, run against this cache instead of re-reading every reducer script for each string.
grep --binary-files=text -H -m1 '^   TEXT=' reducer* 2>/dev/null > "${TEXTS_CACHE}"
CHAR_REGEX='[^0-9]'
if [ "$(echo ${PWD} | sed 's|.*/||')" == "ERR_REDUCERS" ]; then
  CHAR_REGEX='[^_0-9]'
fi
OUT_TRIALS=",$(ls -d [0-9]*/*_out 2>/dev/null | sed 's|/.*||' | sort -u | tr '\n' ',')"  # Every trial which already holds a reduced testcase, comma-wrapped so a lookup of ",<trial>," cannot match part of another trial number. One glob for the whole workdir, so the colouring below costs no extra directory reads
STARTED_TRIALS=",$(ls -d [0-9]*/[1-2][0-9]*_start 2>/dev/null | sed 's|/.*||' | sort -u | tr '\n' ',')"  # Every trial which holds an EPOCH bundle, so a reducer ran on it at some point. Same test start_unreduced uses. A trial in this list but not in OUT_TRIALS was started and gave no testcase
if [[ $MDG -eq 0 && $GRP_RPL -eq 0 ]]; then  # Normal non-Galera, non-GR run
  grep --binary-files=text -vE 'Last.*consecutive queries all failed|Assert: no core file found in.*and fallback_text_string.sh returned an empty output' "${TEXTS_CACHE}" 2>/dev/null | sed "s|.*TEXT=.||;s|['\"][ \t]*$||" | sort -u | awk -v w="${SCREEN_WIDTH}" '
    # Error-log and assert-only entries list first, crash signatures and sanitizer reports after. Inside the leading group the ones that fit the terminal come before the ones that run past it, so the aligned block stays unbroken. Alphabetical within each group. The width test mirrors the display below: a sanitizer entry always renders at 170 columns, any other entry at its own length with the \" escaping reverted.
    { t=$0
      san = (index(t,"=ERROR")==1 || index(t,"ThreadSanitizer:")==1 || index(t,"runtime error:")==1 || index(t,"LeakSanitizer:")==1 || index(t,"MemorySanitizer:")==1)
      if (san) { L=170 } else { gsub(/\\"/,"\"",t); L=length(t) }
      if (san || index($0,"SIG")) sig_or_san[++nss]=$0; else if (w>0 && L<w-43) fit[++nf]=$0; else ovf[++no]=$0 }
    END { for (i=1;i<=nf;i++) print fit[i]; for (i=1;i<=no;i++) print ovf[i]; for (i=1;i<=nss;i++) print sig_or_san[i] }' > "${STRINGS_CACHE}"
  if [ "${NTS}" == "-Fi" ]; then  # New text string (i.e. no regex, exact text string) mode
    # One awk pass over the string list and the TEXT cache replaces a ~10-process pipeline per string. Matching is case-insensitive fixed-substring (as grep -Fi); trial numbers come from the cache filenames (strip at ':', drop CHAR_REGEX chars, drop leading __); trial lists are numeric-unique ascending (as sort -un). The trailing printf '%b' loop reproduces echo -e's backslash handling. The s|\\"|"|g revert of the else-branch: pquery-prep-reducer.sh inserts \ before " for in-reducer TEXT use; it is not part of the official bug uniqueID string, so pquery-results.sh / MYBUG / known_bug_string.sh show " where reducer.sh TEXT holds \" (pquery-clean-known.sh relies on the \" form to find failing reducers).
    awk -v crx="${CHAR_REGEX}" -v w="${SCREEN_WIDTH}" -v dim="${C_DIM}" -v sig_or_sancol="${C_SIG_OR_SAN}" -v stalledcol="${C_STALLED}" -v unredcol="${C_UNREDUCED}" -v outs="${OUT_TRIALS}" -v started="${STARTED_TRIALS}" -v untypedcol="${C_UNTYPED}" -v off="${C_OFF}" '
      FILENAME==ARGV[1] { if ($0!="") s[++ns]=$0; next }  # An empty TEXT extraction stays hidden, as with word-split iteration
      { cl[++nc]=$0; lcl[nc]=tolower($0) }
      END {
        for (k=1; k<=ns; k++) {
          S=s[k]; ls=tolower(S); cnt=0; nt=0; delete tr
          for (i=1; i<=nc; i++) {
            if (index(lcl[i], ls)) {
              cnt++
              f=cl[i]; sub(/:.*/,"",f); gsub(crx,"",f); sub(/^__/,"",f)
              tr[++nt]=f
            }
          }
          if (cnt==0) continue
          for (a=2; a<=nt; a++) { v=tr[a]; b=a-1; while (b>=1 && tr[b]+0 > v+0) { tr[b+1]=tr[b]; b-- } tr[b+1]=v }
          j=""; pv=""
          for (a=1; a<=nt; a++) { if (a>1 && tr[a]+0 == pv+0) continue; j=(j=="")?tr[a]:j","tr[a]; pv=tr[a] }
          # sc: a crash signature and a sanitizer report read green once one of their trials holds an _out file, red when a trial was started and produced none, and in the unreduced colour while nothing was started. c: an UNTYPED entry in the untyped colour, an error-log error or warning dim.
          hasout=0; hasstart=0
          for (a=1; a<=nt; a++) { if (index(outs, "," tr[a] ",")) { hasout=1; break } if (index(started, "," tr[a] ",")) hasstart=1 }
          sc = hasout ? sig_or_sancol : (hasstart ? stalledcol : unredcol)
          c=""
          if      (index(S,"=ERROR")==1)           { o=sprintf("%-164sASAN  ",S); c=sc }
          else if (index(S,"ThreadSanitizer:")==1) { o=sprintf("%-164sTSAN  ",S); c=sc }
          else if (index(S,"runtime error:")==1)   { o=sprintf("%-164sUBSAN ",S); c=sc }
          else if (index(S,"LeakSanitizer:")==1)   { o=sprintf("%-164sASAN ",S);  c=sc }
          else if (index(S,"MemorySanitizer:")==1) { o=sprintf("%-164sMSAN ",S);  c=sc }
          else                                     { o=S; gsub(/\\"/,"\"",o); gsub(/\\`/,"`",o); if (index(S,"SIG")) c=sc; else if (index(S,"UNTYPED")==1) c=untypedcol; else if (index(S,"ERROR") || index(S,"WARNING")) c=dim }
          # A UniqueID that leaves room pushes its "(Seen ...)" to a fixed right-hand column, so the counts line up in one place instead of drifting with the text. A longer one falls back to the fixed layout.
          if (w > 0 && length(o) < w-43) { line=sprintf("%-*s(Seen %3s times: reducers %s)", w-43, o, cnt, j) }
          else                           { line=sprintf("%-170s (Seen %3s times: reducers %s)", o, cnt, j) }
          if (c!="") printf "%s%s%s\n", c, line, off; else print line
        }
      }' "${STRINGS_CACHE}" "${TEXTS_CACHE}" | while IFS= read -r _line; do printf '%b\n' "${_line}"; done
  else  # Backwards compatible (and manually modified reducers scanning without using new text string)
    for STRING in $(cat "${STRINGS_CACHE}"); do
      MATCHING_TRIALS=($(grep --binary-files=text "TEXT=.${STRING}." "${TEXTS_CACHE}" 2>/dev/null | awk '{print $1}' | sort -u | sed "s|:.*||;s|${CHAR_REGEX}||g" | sed 's|^__||' | sort -un))
      COUNT=$(grep --binary-files=text -v 'Last.*consecutive queries all failed' "${TEXTS_CACHE}" 2>/dev/null | sort -u | sed 's|reducer\([0-9]\+\).sh:|reducer\1.sh:  |;s|  TEXT|TEXT|' 2>/dev/null | grep --binary-files=text "${STRING}" 2>/dev/null | wc -l)
      if [ ${COUNT} -gt 0 ]; then
        if [[ "${STRING}" == "=ERROR"* ]]; then  # ASAN bug
          STRING_OUT="$(echo $STRING | awk -F "\n" '{printf "%-164sASAN  ",$1}')"
        elif [[ "${STRING}" == "ThreadSanitizer:"* ]]; then  # TSAN bug
          STRING_OUT="$(echo $STRING | awk -F "\n" '{printf "%-164sTSAN  ",$1}')"
        elif [[ "${STRING}" == "runtime error:"* ]]; then  # UBSAN bug
          STRING_OUT="$(echo $STRING | awk -F "\n" '{printf "%-164sUBSAN ",$1}')"
        elif [[ "${STRING}" == "LeakSanitizer:"* ]]; then  # LSAN bug
          STRING_OUT="$(echo $STRING | awk -F "\n" '{printf "%-164sASAN ",$1}')"  # LSAN shows as ASAN, ref san_text_string.sh
        elif [[ "${STRING}" == "MemorySanitizer:"* ]]; then  # MSAN bugs
          STRING_OUT="$(echo $STRING | awk -F "\n" '{printf "%-164sMSAN ",$1}')"
        else
          STRING_OUT="$(echo $STRING | awk -F "\n" '{printf "%-170s",$1}' | sed 's|\\"|"|g')"  # See the \" revert note above the awk pass
        fi
        COUNT_OUT="$(echo $COUNT | awk '{printf " (Seen %3s times: reducers ",$1}')"
        echo -e "${STRING_OUT}${COUNT_OUT}$(echo ${MATCHING_TRIALS[@]}|sed 's| |,|g'))"
      fi
    done
  fi
else  # Galera or GR run
  for STRING in $(grep --binary-files=text -m1 '^   TEXT=' reducer* 2>/dev/null | grep -v 'Last.*consecutive queries all failed' | sed "s|.*TEXT=.||;s|['\"][ \t]*$||" | sort -u); do
    MATCHING_TRIALS=()
    for TRIAL in $(grep ${NTS} -H --binary-files=text "${STRING}" reducer* 2>/dev/null | awk '{print $1}' | cut -d'-' -f1 | tr -d '[:alpha:]' | sort -un) ; do
      MATCHING_TRIAL=$(grep -H --binary-files=text -m1 '^   TEXT=' reducer${TRIAL}-* 2>/dev/null | grep -v 'Last.*consecutive queries all failed' | sed 's|reducer\([0-9]\).sh:|reducer\1.sh:  |;s|reducer\([0-9][0-9]\).sh:|reducer\1.sh: |;s|  TEXT|TEXT|' | grep ${NTS} --binary-files=text "${STRING}" 2>/dev/null | sed "s|.sh.*||;s|reducer${TRIAL}-||" | tr -d '\n' | xargs -I {} echo "${TRIAL}-{},")
      MATCHING_TRIALS+=("${MATCHING_TRIAL}")
    done
    COUNT=$(grep --binary-files=text -m1 '^   TEXT=' reducer* 2>/dev/null | grep -v 'Last.*consecutive queries all failed' | sort -u | sed 's|reducer\([0-9]\).sh:|reducer\1.sh:  |;s|reducer\([0-9][0-9]\).sh:|reducer\1.sh: |;s|  TEXT|TEXT|' | grep ${NTS} --binary-files=text "${STRING}" 2>/dev/null | wc -l)
    STRING_OUT="$(echo $STRING | awk -F "\n" '{printf "%-55s",$1}')"
    COUNT_OUT="$(echo $COUNT | awk '{printf " (Seen %3s times: reducers ",$1}')"
    echo "$(echo -e "${STRING_OUT}${COUNT_OUT}${MATCHING_TRIALS[@]})" | sed 's|, |,|g;s|,)|)|')"
  done
fi
IFS=$ORIG_IFS

# MODE 4 TRIALS
if [[ $MDG -eq 0 && $GRP_RPL -eq 0 ]]; then
  COUNT=0
  MATCHING_TRIALS=()
  for MATCHING_TRIAL in $(grep -H --binary-files=text -m1 "^MODE=4$" reducer* 2>/dev/null | sort -u | awk '{print $1}' | sed 's|:.*||;s|[^0-9]||g' | sort -un) ; do
    if [ ! -r ${MATCHING_TRIAL}/SHUTDOWN_TIMEOUT_ISSUE ]; then
      MATCHING_TRIALS+=($MATCHING_TRIAL)
      COUNT=$[ COUNT + 1 ]
    fi
  done
  if [ $COUNT -gt 0 ]; then
    STRING_OUT="$(echo "* TRIALS TO CHECK MANUALLY (NO TEXT SET: MODE=4) *" | awk -F "\n" '{printf "%-55s",$1}')"
    COUNT_OUT=$(echo $COUNT | awk '{printf " (Seen %3s times: reducers ",$1}')
    MODE4_COLOR="${C_UNREDUCED}"  # Green once one of these trials holds an _out file, red when one was started and gave none, as with the UniqueID list above
    for MATCHING_TRIAL in ${MATCHING_TRIALS[@]}; do
      case "${OUT_TRIALS}" in *",${MATCHING_TRIAL},"*) MODE4_COLOR="${C_SIG_OR_SAN}"; break ;; esac
      case "${STARTED_TRIALS}" in *",${MATCHING_TRIAL},"*) MODE4_COLOR="${C_STALLED}" ;; esac
    done
    echo -e "${MODE4_COLOR}${STRING_OUT}${COUNT_OUT}$(echo ${MATCHING_TRIALS[@]}|sed 's| |,|g'))${C_OFF}"
  fi
else
  COUNT=0
  MATCHING_TRIALS=()
  for TRIAL in $(grep -H --binary-files=text "^MODE=4$" reducer* 2>/dev/null | sort -u | awk '{print $1}' | cut -d'-' -f1 | tr -d '[:alpha:]' | sort -un); do
    MATCHING_TRIAL=$(grep -H --binary-files=text "^MODE=4$" reducer${TRIAL}-* 2>/dev/null | sort -u | sed "s|.sh.*||;s|reducer${TRIAL}-||" | tr '\n' , | sed 's|,$||' | xargs -I '{}' echo "${TRIAL}-{},")
    if [[ ! -r ${MATCHING_TRIAL}/SHUTDOWN_TIMEOUT_ISSUE ]]; then
      MATCHING_TRIALS+=($MATCHING_TRIAL)
      COUNT=$[ COUNT + 1 ]
    fi
  done
  if [ $COUNT -gt 0 ]; then
    STRING_OUT="$(echo "* TRIALS TO CHECK MANUALLY (NO TEXT SET; MODE=4) *" | awk -F "\n" '{printf "%-55s",$1}')"
    COUNT_OUT=$(echo $COUNT | awk '{printf " (Seen %3s times: reducers ",$1}')
    echo "${C_SIG_OR_SAN}$(echo -e "${STRING_OUT}${COUNT_OUT}${MATCHING_TRIALS[@]})" | sed 's|, |,|g;s|,)|)|')${C_OFF}"
           #echo -e "${STRING_OUT}${COUNT_OUT}${MATCHING_TRIALS[@]})"
  fi
fi

if grep -qi 'RR.*enabled.*:.*YES' pquery-run.log; then
  if [ ! -z "$(ls */AVOID_FORCE_KILL 2>/dev/null)" ]; then  # AVOID_FORCE_KILL is only created (by pquery-prep-red.sh) when pquery-run.sh wrote a ./SHUTDOWN_TIMEOUT_ISSUE flag (and that flag is deleted upon writing AVOID_FORCE_KILL). In that case, we want to check if this was an RR run. If so, remind about SIGABRT as per below
    echo '** RR traced trials which also experienced shutdown timeout issues, and were subsequently sent a SIGABRT to ensure RR trace stability. These likely require in-depth review before logging (Ref MDEV-36228 and MDEV-36231 for more info):'  
    ls */AVOID_FORCE_KILL 2>/dev/null | grep -o '[0-9]\+' | xargs -I{} grep -l 'SIGABRT' {}/MYBUG | grep -o '[0-9]\+' | tr '\n' ' ' | sed 's|[ ]\+$||;s|$|\n|'
  fi
fi

# mysqld shutdown timeout issue trials
# Semi-false positives; (Though the issues below refer to reducer.sh, they apply similarly to the original trials which failed due to the same circumstances)
# * Where a shutdown issue testcase reduces to something like: SET PASSWORD=PASSWORD('somepass'); it is a false positive.
#   > reducer.sh in MODE=0 (which auto sets FORCE_KILL=0) will reduce on this SQL as mysqladmin shutdown will loose user access
# * Where a shutdown issue testcase reduces to something like (with matching mysqld otions):
#   SET GLOBAL rpl_semi_sync_master_timeout=600000;
#   SET GLOBAL rpl_semi_sync_master_enabled=1;
#   GRANT ALL ON *.* TO user3_mysqlx@localhost;
#   > Here a timeout was set (and reached) of 10 minutes which was <=600 seconds configured in reducer.sh
#   > To avoid the more common 600 second (10 minutes) timeouts, reducer was changed to 780 seconds default (=13 minutes)
if [ $(ls */SHUTDOWN_TIMEOUT_ISSUE 2>/dev/null | wc -l) -gt 0 ]; then
  COUNT=$(ls */SHUTDOWN_TIMEOUT_ISSUE 2>/dev/null | wc -l)
  STRING_OUT="$(echo "* SHUTDOWN TIMEOUT >90 SEC ISSUE *" | awk -F "\n" '{printf "%-55s",$1}')"
  COUNT_OUT=$(echo $COUNT | awk '{printf "  (Seen %3s times: reducers ",$1}')
  echo -e "${C_DIM}${STRING_OUT}${COUNT_OUT}$(ls */SHUTDOWN_TIMEOUT_ISSUE 2>/dev/null | sed 's|/.*||' | sort -un | tr '\n' ',' | sed 's|,$||'))${C_OFF}"
  COUNT=
  STRING_OUT=
  COUNT_OUT=
  # Two-stage SQL pattern match: both patterns intersected via comm -12 over the hang-trial first-pass cache (_pq_trials_with).
  TRIALS_MDEV_30418="$(comm -12 <(_pq_trials_with 'set.*global.*wsrep_cluster_address') <(_pq_trials_with 'set.*global.*wsrep_slave_threads') | sort -h | tr '\n' ' ' | sed 's|[ ]\+$||')"
  if [ ! -z "${TRIALS_MDEV_30418}" ]; then
    echo '** Trials with SET GLOBAL of wsrep_cluster_address & wsrep_slave_threads (known hang/timeout issue MDEV-30418):'
    echo "${TRIALS_MDEV_30418}"
  fi
  TRIALS_MDEV_30418=
  TRIALS_MASTER_POS_WAIT="$(comm -12 <(_pq_trials_with 'start.*slave') <(_pq_trials_with 'master_pos_wait') | sort -h | tr '\n' ' ' | sed 's|[ ]\+$||')"
  if [ ! -z "${TRIALS_MASTER_POS_WAIT}" ]; then
    echo '** Trials with START SLAVE & MASTER_POS_WAIT (known hang/timeout issue waiting for an invalid position):'
    echo "${TRIALS_MASTER_POS_WAIT}"
  fi
  TRIALS_MASTER_POS_WAIT=
  TRIALS_MDEV_22727="$(comm -12 <(_pq_trials_with 'set.*aria_group_commit_interval') <(_pq_trials_with 'set.*aria_group_commit.*hard') | sort -h | tr '\n' ' ' | sed 's|[ ]\+$||')"
  if [ ! -z "${TRIALS_MDEV_22727}" ]; then
    echo '** Trials with SET aria_group_commit_interval & SET aria_group_commit=HARD (known hang/timeout issue MDEV-22727):'
    echo "${TRIALS_MDEV_22727}"
  fi
  TRIALS_MDEV_22727=
  TRIALS_NET_RETRY="$(_pq_trials_with 'set.*net_retry_count' | sort -h | tr '\n' ' ' | sed 's|[ ]\+$||')"
  if [ ! -z "${TRIALS_NET_RETRY}" ]; then
    echo '** Trials with SET net_retry_count (known to cause hang/timeout issues):'
    echo "${TRIALS_NET_RETRY}"
  fi
  TRIALS_NET_RETRY=
  TRIALS_MDEV_35064=
  if [ -n "${_HANG_TRIALS}" ]; then
    _out_files=()
    for _t in ${_HANG_TRIALS}; do
      for _f in "${_t}"/default.node.tld_thread-*.sql*out*out*; do
        [ -e "${_f}" ] && _out_files+=("${_f}")
      done
    done
    [ ${#_out_files[@]} -gt 0 ] && TRIALS_MDEV_35064="$(grep --binary-files=text -lim1 "CREATE.*SERVER.*WRAPPER.*HOST[ \t]\+'1');" "${_out_files[@]}" 2>/dev/null | sed 's|/.*||' | sort -u | sort -h | tr '\n' ' ' | sed 's|[ ]\+$||')"
    _out_files= _t= _f=
  fi
  if [ ! -z "${TRIALS_MDEV_35064}" ]; then
    echo '** Trials with "CREATE SERVER.*WRAPPER.*HOST '1');" in reduced traces (known to cause thread-hang issues: ref MDEV-35064):'
    echo "${TRIALS_MDEV_35064}"
  fi
  TRIALS_MDEV_35064=
  TRIALS_MDEV_25611="$(comm -12 <(_pq_trials_with 'innodb_flush_log_at_timeout') <(_pq_trials_with 'RESET[ \t]*MASTER') | sort -h | tr '\n' ' ' | sed 's|[ ]\+$||')"
  if [ ! -z "${TRIALS_MDEV_25611}" ]; then
    echo '** Trials with SET innodb_flush_log_at_timeout and RESET MASTER (known to cause hang/timeout issues, ref MDEV-25611):'
    echo "${TRIALS_MDEV_25611}"
  fi
  TRIALS_MDEV_25611=
  _HANG_TRIALS=
fi

# Trials whose error log ran away in size. pquery-run.sh flags a trial when any of
# its error logs passed 5MB, where a normal one is about 16KB. The trial is worth a
# look on its own, and its log is also slow for every tool that has to read it
if [ $(ls */LARGE_ERROR_LOG_ISSUE 2>/dev/null | wc -l) -gt 0 ]; then
  COUNT=$(ls */LARGE_ERROR_LOG_ISSUE 2>/dev/null | wc -l)
  STRING_OUT="$(echo "* ERROR LOG OVER 5MB *" | awk -F "\n" '{printf "%-55s",$1}')"
  COUNT_OUT=$(echo $COUNT | awk '{printf "  (Seen %3s times: reducers ",$1}')
  echo -e "${C_DIM}${STRING_OUT}${COUNT_OUT}$(ls */LARGE_ERROR_LOG_ISSUE 2>/dev/null | sed 's|/.*||' | sort -un | tr '\n' ',' | sed 's|,$||'))${C_OFF}"
  COUNT=
  STRING_OUT=
  COUNT_OUT=
fi

# Binlog recovery trials (MARIADB_BINLOG_RECOVERY_TESTING=1): replay error in mariadb-binlog | mariadb pipeline
if [ $(ls */BINLOG_RECOVERY_ERROR 2>/dev/null | wc -l) -gt 0 ]; then
  COUNT=$(ls */BINLOG_RECOVERY_ERROR 2>/dev/null | wc -l)
  STRING_OUT="$(echo "* BINLOG RECOVERY: REPLAY ERROR *" | awk -F "\n" '{printf "%-55s",$1}')"
  COUNT_OUT=$(echo $COUNT | awk '{printf "  (Seen %3s times: trials ",$1}')
  echo -e "${STRING_OUT}${COUNT_OUT}$(ls */BINLOG_RECOVERY_ERROR 2>/dev/null | sed 's|/.*||' | sort -un | tr '\n' ',' | sed 's|,$||'))"
  COUNT=
  STRING_OUT=
  COUNT_OUT=
fi

# Binlog recovery trials (MARIADB_BINLOG_RECOVERY_TESTING=1): table checksum diverged after binlog replay
if [ $(ls */BINLOG_CHECKSUM_DIFF 2>/dev/null | wc -l) -gt 0 ]; then
  COUNT=$(ls */BINLOG_CHECKSUM_DIFF 2>/dev/null | wc -l)
  STRING_OUT="$(echo "* BINLOG RECOVERY: CHECKSUM DIVERGENCE *" | awk -F "\n" '{printf "%-55s",$1}')"
  COUNT_OUT=$(echo $COUNT | awk '{printf "  (Seen %3s times: trials ",$1}')
  echo -e "${STRING_OUT}${COUNT_OUT}$(ls */BINLOG_CHECKSUM_DIFF 2>/dev/null | sed 's|/.*||' | sort -un | tr '\n' ',' | sed 's|,$||'))"
  COUNT=
  STRING_OUT=
  COUNT_OUT=
fi

# Timeouts (MODE=0) which are not shutdown issues (i.e. no <trialnr>/SHUTDOWN_TIMEOUT_ISSUE)
MODE0_TRIALS="$(grep --binary-files=text -l -m1 '^MODE=0' reducer[0-9]*.sh 2>/dev/null | grep -o '[0-9]\+' | sort -uh | while read _t; do [ ! -r "${_t}/SHUTDOWN_TIMEOUT_ISSUE" ] && echo "${_t}"; done | tr '\n' ' ')"
if [ ! -z "${MODE0_TRIALS}" ]; then
  echo '** Trials which timed out (MODE=0) which are not shutdown issues (i.e. no <trialnr>/SHUTDOWN_TIMEOUT_ISSUE):'
  echo "${MODE0_TRIALS}"
fi
MODE0_TRIALS=

# Other MDEV related issues worth highlighting, aiding issue management
# MDEV-26492: SET key_cache_segments in SQL plus '[ERROR] Got an error' in the err log. Independent of SHUTDOWN_TIMEOUT_ISSUE; narrowed by scanning the (small) err logs first, then SQL only of trials matching that err-log marker.
TRIALS_MDEV_26492=
_T1="$(grep --binary-files=text -lim1 'ERROR] Got an error' ${ERROR_LOG_LOC} 2>/dev/null | sed "${TRIAL_FROM_LOG}" | sed 's|/.*||' | sort -u)"
if [ -n "${_T1}" ]; then
  _sql_files=()
  for _t in ${_T1}; do
    for _f in "${_t}"/default.node.tld_thread-*.sql; do
      [ -e "${_f}" ] && _sql_files+=("${_f}")
    done
  done
  [ ${#_sql_files[@]} -gt 0 ] && TRIALS_MDEV_26492="$(grep --binary-files=text -lim1 'key_cache_segments' "${_sql_files[@]}" 2>/dev/null | sed 's|/.*||' | sort -u | sort -h | tr '\n' ' ' | sed 's|[ ]\+$||')"
  _sql_files= _t= _f=
fi
_T1=
if [ ! -z "${TRIALS_MDEV_26492}" ]; then
  echo '** Trials with SET key_cache_segments resulting in '[ERROR] Got an error' (from a thread or an unknown thread), a know bug; ref MDEV-26492:'
  echo "${TRIALS_MDEV_26492}"
fi
TRIALS_MDEV_26492=

# 'MySQL server has gone away' seen >= 200 times + timeout was not reached
if [ $(ls */GONEAWAY 2>/dev/null | wc -l) -gt 0 ]; then
  echo "'** MySQL server has gone away' trials found: $(ls */GONEAWAY | sed 's|/.*||' | sort -un | tr '\n' ',' | sed 's|,$||')"
  echo "(> 'MySQL server has gone away' trials which did not hit the pquery timeout (i.e. the trial ended before pquery timeout was reached, hence something must have gone wrong) are not handled correctly yet by pquery-prep-red.sh (feel free to expand it), and cannot be filtered easily (idem). Frequency unknown. pquery-run.sh has only recently (26-08-2016) been expanded to not delete these. As they did not hit the pquery timeout, something must have gone wrong (in mysqld or in the pquery framework). Please check for existence of a core file (unlikely) and check the mysqld error log, the pquery logs and the SQL log, especially the last query before 'MySQL server has gone away' started happening. If it is a SELECT query on P_S, it's likely http://bugs.mysql.com/bug.php?id=82663 - a mysqld hang)"
fi

# 'SIGKILL myself' trials
if [ $(grep --binary-files=text -l "SIGKILL myself" ${ERROR_LOG_LOC} 2>/dev/null | wc -l) -gt 0 ]; then
  echo "'** SIGKILL myself' trials found: $(grep --binary-files=text -l "SIGKILL myself" ${ERROR_LOG_LOC} 2>/dev/null | sed "${TRIAL_FROM_LOG}" | sed 's|/.*||' | sort -un | tr '\n' ',' | sed 's|,$||')"
  echo "(> 'SIGKILL myself' trials are of interest, but are not handled correctly yet by pquery-prep-red.sh (feel free to expand it), and cannot be filtered easily (idem). Frequency unknown. Easiest way to handle these ftm is to set them to MODE=3, USE_NEW_TEXT_STRING=0, and TEXT='SIGKILL myself' in their reducer<trialnr>.sh files (in the 'Machine configurable variables section'!). Then, simply reduce as normal.)"
fi

# MODE 2 TRIALS (Query correctness trials)
COUNT=$(grep --binary-files=text -l "^MODE=2$" qcreducer* 2>/dev/null | wc -l)
if [ $COUNT -gt 0 ]; then
  for STRING in $(grep --binary-files=text -m1 '^   TEXT=' qcreducer* 2>/dev/null | grep -v 'Last.*consecutive queries all failed' | sed 's|.*TEXT="||;s|"$||' | sort -u); do
    MATCHING_TRIALS=()
    for TRIAL in $(grep ${NTS} -H --binary-files=text "${STRING}" qcreducer* 2>/dev/null | awk '{ print $1}' | cut -d'-' -f1 | sed 's/[^0-9]//g' | sort -un) ; do
      MATCHING_TRIAL=$(grep -H --binary-files=text -m1 '^   TEXT=' qcreducer${TRIAL}* 2>/dev/null | grep -v 'Last.*consecutive queries all failed' | sed 's!qcreducer\([0-9]\).sh:!qcreducer\1.sh:  !;s!qcreducer\([0-9][0-9]\).sh:!qcreducer\1.sh: !;s!  TEXT!TEXT!' | grep ${NTS} --binary-files=text "${STRING}" 2>/dev/null | sed "s!.sh.*!!;s!reducer${TRIAL}!!" | tr '\n' ',' | sed 's!,$!!' | xargs -I {} echo "${TRIAL}{}," 2>/dev/null | sed 's!qc!!' )
      MATCHING_TRIALS+=("$MATCHING_TRIAL")
    done
    COUNT=$(grep --binary-files=text -m1 '^   TEXT=' qcreducer* 2>/dev/null | grep -v 'Last.*consecutive queries all failed' | sort -u | sed 's|qcreducer\([0-9]\).sh:|qcreducer\1.sh:  |;s|qcreducer\([0-9][0-9]\).sh:|qcreducer\1.sh: |;s|  TEXT|TEXT|' | grep "${STRING}" 2>/dev/null | wc -l)
    STRING_OUT="$(echo $STRING | awk -F "\n" '{printf "%-55s",$1}')"
    COUNT_OUT="$(echo $COUNT | awk '{printf " (Seen %3s times: reducers ",$1}')"
    echo -e "${STRING_OUT}${COUNT_OUT}${MATCHING_TRIALS[@]})"
  done
fi

# Likely out of disk space trials
OOS1="$(egrep --binary-files=text -i "device full error|no space left on device|errno[:]* enospc|can't write.*bytes|errno[:]* 28|disk full|waiting for someone to free some space|out of disk space|InnoDB: preallocating.*bytes for file.*failed with error 28|innodb: error while writing|bytes should have been written|error number[:]* 28|error[:]* 28|Disk is full writing|Errcode: 28|No space left on device|Waiting for someone to free space|up to 60 secs delay for server to continue after freeing disk space" ${ERROR_LOG_LOC} 2>/dev/null | sed "${TRIAL_FROM_LOG}" | sed 's|/.*||' | tr '\n' ' ')"
OOS2="$(ls -s */data/*core* 2>/dev/null | grep --binary-files=text -o "^ *0 [^/]\+" 2>/dev/null | awk '{print $2}' | tr '\n' ' ')"  # Cores with a file size of 0: good indication of OOS
OOS3="$(ls --color=never -l */pquery.log 2>/dev/null | grep --binary-files=text '   0' | grep -o '[0-9]\+/pquery.log' | grep -o '[0-9]\+' | tr '\n' ' ')"  # pquery.log has a file size of 0: good indication of OOS
OOS4="$(grep 'Assert: /tmp does not have enough free space' */MYBUG 2>/dev/null | sed 's|/.*||' | tr '\n' ' ')"

OOS="$(echo "${OOS1} ${OOS2} ${OOS3} ${OOS4}" | sed 's|  | |g;s| $||g')"
if [ "$(echo "${OOS}" | sed "s| ||g")" != "" ]; then
  echo "** Likely out of disk space trials:"
  echo "$(echo "${OOS}" | tr ' ' '\n' | sort -nu |  tr '\n' ' ' | sed 's|$|\n|;s|^ \+||')"
fi

# Likely disk I/O issues trials
DI1=$(grep --binary-files=text "bytes should have been read. Only" ${ERROR_LOG_LOC} 2>/dev/null | sed "${TRIAL_FROM_LOG}" | sed 's|/.*||' | tr '\n' ' ')
DI="$(echo "${DI1}" | sed "s|  | |g")"
if [ "$(echo "${DI}" | sed "s| ||g")" != "" ]; then
  echo "** Likely disk I/O issues trials (unable to read from disk etc.):"
  echo "$(echo "${DI}" | tr ' ' '\n' | sort -nu |  tr '\n' ' ' | sed 's|$|\n|;s|^ \+||')"
fi

# Likely result of 'RELEASE' command (client connection lost resulting in pquery seeing >=250 x 'MySQL server has gone away'
# For the moment, these can simply be deleted. In time, pquery itself (and reducer in CLI mode) should handle this better by reconnecting to mysqld. However, in such case reducer replay needs to be checked as well; does it continue replaying the SQL via a live client connection when RELEASE was seen? Likely not for mysql cli mode, but for pquery (which is then updated to do so) it would be fine, and many testcases would not end up with an eventual RELEASE so they would replay at the mysql cli just fine, or otherwise the pquery replay method can be used in the replay only works via pquery (as usual).
REL1=$(grep --binary-files=text -l 'Last [0-9]\+ consecutive queries all failed' [0-9]*/pquery.log 2>/dev/null | sed 's|/.*||' | xargs -I{} grep --binary-files=text -m1 -B2 -H 'MySQL server has gone away' {}/default.node.tld_thread-0.sql 2>/dev/null | grep 'RELEASE' | sed 's|/.*||' | tr '\n' ',' | sed -E 's|,|, |g;s|^|Trials: |;s|, $||')
if [ ! -z "$REL1" ]; then
  echo "** Trials with 'Server has gone away' 250x, likely due to 'RELEASE' being used in the input SQL:"
  echo "${REL1}"
fi

# Coredumps overview (for comparison). One tree walk, consumed twice (the display filter additionally drops vault paths)
CORE_PATHS="$(find . | grep --binary-files=text 'core' 2>/dev/null)"
COREDUMPS="$(echo "${CORE_PATHS}" | grep --binary-files=text -vE 'parse|pquery' 2>/dev/null | cut -d '/' -f2 | sort -un | tr '\n' ' ' | sed 's|$|\n|')"
if [ "$(echo "${COREDUMPS}" | sed 's| \+||g')" != "" ]; then
  echo "${C_DIM}** Coredumps found in trials: $(echo "${CORE_PATHS}" | grep --binary-files=text -vE 'parse|pquery|vault' 2>/dev/null | cut -d '/' -f2 | sort -un | tr '\n' ' ' | sed 's|[ ]*$||')${C_OFF}"
fi

if [ $(ls -l reducer* qcreducer* 2>/dev/null | awk '{print $5"|"$9}' | grep --binary-files=text "^0|" 2>/dev/null | sed 's/^0|//' | wc -l) -gt 0 ]; then
  echo "${C_ORANGE}Detected one or more empty (0 byte) reducer script(s): $(ls -l reducer* qcreducer* 2>/dev/null | awk '{print $5"|"$9}' | grep --binary-files=text "^0|" 2>/dev/null | sed 's/^0|//' | tr '\n' ' ')- you may want to check what's causing this (possibly a bug in pquery-prep-red.sh, or did you simply run out of space while running pquery-prep-red.sh?) and do the analysis for these trial numbers manually, or free some space, delete the reducer*.sh scripts and re-run pquery-prep-red.sh${C_OFF}"
fi

# Stack smashing overview
if [ ! -z "$(grep --binary-files=text 'smashing' ${ERROR_LOG_LOC} 2>/dev/null)" ]; then
  echo "** Stack smashing detected:"
  grep --binary-files=text 'smashing' ${ERROR_LOG_LOC} 2>/dev/null | sed "${TRIAL_FROM_LOG}"
fi

# Significant/major error scanning. The REGEX_ERRORS_* application is centralised in error_log_scan.sh (shared with pquery-run.sh / pquery-prep-red.sh / pquery-del-trial.sh). This script applies its own additional ERROR_MSG_FILTER on top of the helper's output (see ERROR_MSG_FILTER below).
ERRORS=
ERROR_LOG=
if [ ! -z "$(grep -io 'Basedir.*' pquery-run.log | grep -o '10\.[2-5]\.')" ]; then
  if grep -qm1 'innodb.checksum.algorithm' [0-9]*/default.node.tld_thread-0.sql 2>/dev/null; then
    echo '** Trials which modify innodb_checksum_algorithm (likely cause of corruption on versions <10.6, ref MDEV-23667)'
    grep -lm1 'innodb_checksum_algorithm' [0-9]*/default.node.tld_thread-0.sql 2>/dev/null | sed 's|/.*||' | sort -n | tr '\n' ' ' | sed 's| $||;s|$|\n|'
  fi
fi
#if grep -qm1 'WITHOUT VALIDATION' [0-9]*/default.node.tld_thread-0.sql 2>/dev/null; then
#  echo '** WITHOUT VALIDATION trials: if this clause remains post-reduction, ref server-testing @ 19-12-23 & MDEV-22164'
#  grep -lm1 'WITHOUT VALIDATION' [0-9]*/default.node.tld_thread-0.sql 2>/dev/null | sed 's|/.*||' | sort -n | tr '\n' ' ' | sed 's| $||;s|$|\n|'
#fi
if grep -qm1 'slave SQL thread aborted' [0-9]*/log/slave.err 2>/dev/null; then
  echo '** Trials where the slave SQL thread aborted: manual reducer setup verification may be required'
  grep -lm1 'slave SQL thread aborted' [0-9]*/log/slave.err 2>/dev/null | sed 's|/.*||' | sort -n | tr '\n' ' ' | sed 's| $||;s|$|\n|'
fi
# Galera per-node error logs: ./<trial>/node<N>/node<N>.err. error_log_scan.sh
# aggregate-mode extracts the trial id from the leading ./<digits>/ path component,
# so these slot into the same aggregate output as master.err / slave.err. Added
# so /data/results (alias `r`) can drop its own inline scan that previously
# covered Galera node logs. One tree walk for all three log names.
find . -type f \( -name "master.err" -o -name "slave.err" -o -name "node*.err" \) 2>/dev/null > "${ALLERRLOGS}"
grep '\./[0-9]\+/log/master.err' "${ALLERRLOGS}" > "${ERRORLOGS}"
grep '\./[0-9]\+/log/slave.err' "${ALLERRLOGS}" >> "${ERRORLOGS}"
grep -E '\./[0-9]+/node[0-9]+/node[0-9]+\.err' "${ALLERRLOGS}" >> "${ERRORLOGS}"
if [ -s "${ERRORLOGS}" ]; then
  # Single error_log_scan.sh aggregate call over all error logs; emits "<UID>\t<trial>" rows. ERROR_MSG_FILTER (pquery-results.sh-local, on top of REGEX_ERRORS_FILTER) drops items already shown as new_text_string.sh UniqueIDs and 'slave SQL thread aborted' (own section above), keeping the 'Significant/Major errors' section concise.
  # Signatures already listed in the sorted-UniqueID section on top (the reducer TEXT= strings, with the \" escaping reverted to match error_log_scan.sh output) are dropped too: this section surfaces errors not yet captured by any reducer, so that none are lost.
  ERROR_MSG_FILTER='Warning: Memory not freed|mysqld: Got error|is marked as crashed|MariaDB error code|slave SQL thread aborted'
  grep --binary-files=text -vE 'Last.*consecutive queries all failed|Assert: no core file found in.*and fallback_text_string.sh returned an empty output' "${TEXTS_CACHE}" 2>/dev/null | sed "s|.*TEXT=.||;s|['\"][ \t]*$||" | sed 's|\\"|"|g' | sort -u > "${LISTED_UIDS}"
  xargs -a "${ERRORLOGS}" "${SCRIPT_PWD}/error_log_scan.sh" aggregate 2>/dev/null \
    | grep --binary-files=text -vE "${ERROR_MSG_FILTER}" \
    | awk -F'\t' 'FILENAME==ARGV[1]{listed[$0];next} !($1 in listed)' "${LISTED_UIDS}" - > "${ERROR_SIGS}"
fi
if [ -s "${ERROR_SIGS}" ]; then
  # Cross-trial aggregation: group by signature, list trials per signature in numeric order. Sort by signature (alphabetical) then trial (numeric) so the awk pass only has to detect signature boundaries. The per-(sig,trial) dedup in the awk catches trials whose master.err and slave.err both contain the same signature. Signature and trials share one line, separated by two spaces: a colon would read as part of the UniqueID.
  ERROR_SIGS_OUT="$(sort -t$'\t' -k1,1 -k2,2n "${ERROR_SIGS}" | awk -F'\t' '
    seen[$1, $2]++ { next }
    $1 != prev_sig {
      if (prev_sig != "") print prev_sig "  " trials
      trials = $2
      prev_sig = $1
      next
    }
    { trials = trials " " $2 }
    END { if (prev_sig != "") print prev_sig "  " trials }')"
  if [ ! -z "${ERROR_SIGS_OUT}" ]; then  # Header only when the aggregation actually produced rows
    echo "${C_DIM}** Significant/Major errors${C_OFF}"
    echo "${ERROR_SIGS_OUT}" | sed "s|^|${C_DIM}|;s|\$|${C_OFF}|"  # Per line, so a grep of the output keeps its own colouring intact
  fi
  ERROR_SIGS_OUT=
fi

extract_valgrind_error(){
  for i in $( ls  ${ERROR_LOG_LOC} 2>/dev/null); do
    TRIAL=$(echo $i | sed "${TRIAL_FROM_LOG}" | cut -d'/' -f1)
    echo "** Trial $TRIAL"
    grep --binary-files=text -E --no-group-separator  -A4 "Thread[ \t][0-9]+:" $i 2>/dev/null | cut -d' ' -f2- |  sed 's/0x.*:[ \t]\+//' |  sed 's/(.*)//' | rev | cut -d '(' -f2- | sed 's/^[ \t]\+//' | rev  | sed 's/^[ \t]\+//'  |  tr '\n' '|' |xargs |  sed 's/Thread[ \t][0-9]\+:/\nIssue #/ig'
  done
}

if [ ${VALGRINDOUTPUT} -eq 1 ]; then
  extract_valgrind_error
fi
