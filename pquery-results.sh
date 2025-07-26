#!/bin/bash
# Created by Roel Van de Paar, Percona LLC

# Usage example"
#  For normal output            : $./pquery-results.sh
#  For Valgrind + normal output : $./pquery-results.sh valgrind
#  For known bugs scanning      : $./pquery-results.sh scan

# Setup
set +H  # Disables history substitution and avoids  -bash: !: event not found  like errors

# Internal variables
SCRIPT_PWD="$(readlink -f "${0}" | sed "s|$(basename "${0}")||;s|/\+$||")"
VALGRINDOUTPUT=0
SCANBUGS=0
if [ "$1" == "valgrind" ]; then
  VALGRINDOUTPUT=1
fi
if [ "$1" == "scan" ]; then
  SCANBUGS=1
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

# String (TEXT=string) specific trials (commonly these are MODE=3 trials)
NTS=  # Backwards compatible (and manually modified reducers scanning without using new text string)
if grep -qi --binary-files=text "^USE_NEW_TEXT_STRING=1" reducer*.sh 2>/dev/null; then
  NTS='-Fi' # New text string (i.e. no regex, exact text string) mode
fi
TRIALS_EXECUTED=$(cat pquery-run.log 2>/dev/null | grep --binary-files=text -o "==.*TRIAL.*==" 2>/dev/null | tail -n1 | sed 's|[^0-9]*||;s|[ \t=]||g')
echo "========== [ cd ${PWD} ] Sorted UniqueID's (${TRIALS_EXECUTED} trials done, $(ls reducer*.sh qcreducer*.sh 2>/dev/null | wc -l) remaining reducers) =========="
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
if [[ $MDG -eq 0 && $GRP_RPL -eq 0 ]]; then  # Normal non-Galera, non-GR run
  for STRING in $(grep --binary-files=text -m1 '^   TEXT=' reducer* 2>/dev/null | grep --binary-files=text -vE 'Last.*consecutive queries all failed|Assert: no core file found in.*and fallback_text_string.sh returned an empty output' 2>/dev/null | sed "s|.*TEXT=.||;s|['\"][ \t]*$||" | sort -u); do
    MATCHING_TRIALS=()
    if grep --binary-files=text -qi "^USE_NEW_TEXT_STRING=1" reducer*.sh 2>/dev/null; then  # New text string (i.e. no regex) mode
      CHAR_REGEX='[^0-9]'
      if [ "$(echo ${PWD} | sed 's|.*/||')" == "ERR_REDUCERS" ]; then
        CHAR_REGEX='[^_0-9]'
      fi
      for MATCHING_TRIAL in $(grep -FiH --binary-files=text "${STRING}" reducer* 2>/dev/null | awk '{print $1}' | sort -u | sed "s|:.*||;s|${CHAR_REGEX}||g" | sed 's|^__||' | sort -un) ; do
        MATCHING_TRIAL=$(echo ${MATCHING_TRIAL} | sed 's|.*TEXT=.||;s|\.[ \t]*$||')
        MATCHING_TRIALS+=($MATCHING_TRIAL)
      done
      COUNT=$(grep -Fi -m1 --binary-files=text "${STRING}" reducer* 2>/dev/null | wc -l)
    else  # Backwards compatible (and manually modified reducers scanning without using new text string)
      CHAR_REGEX='[^0-9]'
      if [ "$(echo ${PWD} | sed 's|.*/||')" == "ERR_REDUCERS" ]; then
        CHAR_REGEX='[^_0-9]'
      fi
      for MATCHING_TRIAL in $(grep -H --binary-files=text "TEXT=.${STRING}." reducer* 2>/dev/null | awk '{print $1}' | sort -u | sed "s|:.*||;s|${CHAR_REGEX}||g" | sed 's|^__||' | sort -un) ; do
        MATCHING_TRIAL=$(echo ${MATCHING_TRIAL} | sed 's|.*TEXT=.||;s|\.[ \t]*$||')
        MATCHING_TRIALS+=($MATCHING_TRIAL)
      done
      COUNT=$(grep --binary-files=text -m1 '^   TEXT=' reducer* 2>/dev/null | grep -v 'Last.*consecutive queries all failed' | sort -u | sed 's|reducer\([0-9]\+\).sh:|reducer\1.sh:  |;s|  TEXT|TEXT|' | grep --binary-files=text "${STRING}" 2>/dev/null | wc -l)
    fi
    SAN=0
    if [ ${COUNT} -gt 0 ]; then
      if [[ "${STRING}" == "=ERROR"* ]]; then  # ASAN bug
        STRING_OUT="$(echo $STRING | awk -F "\n" '{printf "%-164sASAN  ",$1}')"
        SAN=1
      elif [[ "${STRING}" == "ThreadSanitizer:"* ]]; then  # TSAN bug
        STRING_OUT="$(echo $STRING | awk -F "\n" '{printf "%-164sTSAN  ",$1}')"
        SAN=1
      elif [[ "${STRING}" == "runtime error:"* ]]; then  # UBSAN bug
        STRING_OUT="$(echo $STRING | awk -F "\n" '{printf "%-164sUBSAN ",$1}')"
        SAN=1
      elif [[ "${STRING}" == "LeakSanitizer:"* ]]; then  # LSAN bug
        STRING_OUT="$(echo $STRING | awk -F "\n" '{printf "%-164sASAN ",$1}')"  # LSAN shows as ASAN, ref san_text_string.sh
        SAN=1
      elif [[ "${STRING}" == "MemorySanitizer:"* ]]; then  # MSAN bugs
        STRING_OUT="$(echo $STRING | awk -F "\n" '{printf "%-164sMSAN ",$1}')"
        SAN=1
      else
        STRING_OUT="$(echo $STRING | awk -F "\n" '{printf "%-170s",$1}' | sed 's|\\"|"|g')"  # The s|\\"|"|g sed reverts the insertion of \ before " (i.e. \") as done by pquery-prep-reducer.sh and as used by reducer. It is not helpful here, and it is not part of the offial bug uniqueID string. Thus, pquery-results.sh and in-reducer TEXT slightly differ: " (pquery-results.sh, MYBUG, known_bug_string.sh) vs \" (reducer.sh, and as set by pquery-prep-reducer.sh, and pquery-clean-known.sh also uses this to be able to find failing reducers)
      fi
      COUNT_OUT="$(echo $COUNT | awk '{printf " (Seen %3s times: reducers ",$1}')"
      echo -e "${STRING_OUT}${COUNT_OUT}$(echo ${MATCHING_TRIALS[@]}|sed 's| |,|g'))"
    fi
    if [ ${SCANBUGS} -eq 1 ]; then
      # Look for exact match (except for allowing both .c and .cc to be used)
      #OLD SCANSTRING="$(echo "${STRING}" | sed 's|\.c[c]*|.c[c]*|')"
      SCANSTRING="$(echo "${STRING}")"
      KB="${SCRIPT_PWD}/known_bugs.strings"
      if [ "${SAN}" -eq 1 ]; then
        KB="${SCRIPT_PWD}/known_bugs.strings.SAN"
      fi
      SCANOUTPUT="$(grep ${NTS} --binary-files=text "${SCANSTRING}" ${KB} 2>/dev/null | sed 's|[ \t]\+| |g;s/^/  | /')"
      if [ "$(echo "${SCANOUTPUT}" | sed 's|[ \t]\+||g')" != "" ]; then  # TODO: this does not work yet with new text string, as the strings are specific uniqueid's/bugs rather than for example the second/third frame only etc. It may help to just use 2nd/3rd frame alone. Add regex here if this functionality is going to be used more (it isn't atm and the new uniqueID's and the new dup bug search function of ~/tt have made this mostly redudant).
        # Note you cannot just echo ${SCANOUTPUT} here without processing; it does not contain newlines. If multiple matches are found, it will condense them into one line
        grep ${NTS} --binary-files=text "${SCANSTRING}" ${KB} 2>/dev/null | sed 's|[ \t]\+| |g;s/^/  | /'
      else  # Also may provide backwards (old text string) compatibility
        # Look for a more generic string. Allow things like "line 1000" to match for "line 2100" (first digit match + neighbour numbers)
        SCANSTRING=$(echo "${STRING}" | sed 's|\.c[c]*|.c[c]*|;s|\( line [0-9]\)[0-9]\+|\1|')
        SCANSTRINGLASTNR=$(echo "${SCANSTRING}" | sed 's|.*\(.\)$|\1|' | sed 's|[^0-9]||')
        if [ "${SCANSTRINGLASTNR}" == "" -o "${SCANSTRINGLASTNR}" == "0" ]; then  # The last character was not a digit, or a 0
          grep ${NTS} --binary-files=text "${SCANSTRING}" ${KB} 2>/dev/null | sed 's|[ \t]\+| |g;s/^/  | /' | sort -u
        else
          # Scan all nearest neighbours
          SCANSTRING=$(echo "${SCANSTRING}" | sed 's|.$||')  # Remove last character (the number)
          # Scan with the original string number
          grep ${NTS} --binary-files=text "${SCANSTRING}${SCANSTRINGLASTNR}" ${KB} 2>/dev/null | sed 's|[ \t]\+| |g;s/^/  | /' | sort -u
          # Scan with the original string number -1 (0 is not fine; already handled above)
          SCANSTRINGLASTNR=$[ ${SCANSTRINGLASTNR} - 1 ]
          grep ${NTS} --binary-files=text "${SCANSTRING}${SCANSTRINGLASTNR}" ${KB} 2>/dev/null | sed 's|[ \t]\+| |g;s/^/  | /' | sort -u
          # Scan with the original string number +1 (9 is fine; this becomes 10 and that would be the next upper neighbour)
          SCANSTRINGLASTNR=$[ ${SCANSTRINGLASTNR} + 2 ]
          grep ${NTS} --binary-files=text "${SCANSTRING}${SCANSTRINGLASTNR}" ${KB} 2>/dev/null | sed 's|[ \t]\+| |g;s/^/  | /' | sort -u
        fi
      fi
    fi
  done
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
    if [ ${SCANBUGS} -eq 1 ]; then
      # Look for exact match (except for allowing both .c and .cc to be used)
      SCANSTRING="$(echo "${STRING}" | sed 's|\.c[c]*|.c[c]*|')"
      SCANOUTPUT="$(grep ${NTS} --binary-files=text "${SCANSTRING}" ${SCRIPT_PWD}/known_bugs.strings 2>/dev/null | sed 's|[ \t]\+| |g;s/^/  | /')"
      if [ "$(echo --binary-files=text "${SCANOUTPUT}" | sed 's|[ \t]\+||g')" != "" ]; then
        # Note you cannot just echo ${SCANOUTPUT} here without processing; it does not contain newlines. If multiple matches are found, it will condense them into one line
        grep ${NTS} --binary-files=text "${SCANSTRING}" ${SCRIPT_PWD}/known_bugs.strings 2>/dev/null | sed 's|[ \t]\+| |g;s/^/  | /'
      else
        # Look for a more generic string. Allow things like "line 1000" to match for "line 2100" (first digit match + neighbour numbers)
        SCANSTRING=$(echo "${STRING}" | sed 's|\.c[c]*|.c[c]*|;s|\( line [0-9]\)[0-9]\+|\1|')
        SCANSTRINGLASTNR=$(echo "${SCANSTRING}" | sed 's|.*\(.\)$|\1|' | sed 's|[^0-9]||')
        if [ "${SCANSTRINGLASTNR}" == "" -o "${SCANSTRINGLASTNR}" == "0" ]; then  # The last character was not a digit, or a 0
          grep ${NTS} --binary-files=text "${SCANSTRING}" ${SCRIPT_PWD}/known_bugs.strings 2>/dev/null | sed 's|[ \t]\+| |g;s/^/  | /' | sort -u
        else
          # Scan all nearest neighbours
          SCANSTRING=$(echo "${SCANSTRING}" | sed 's|.$||')  # Remove last character (the number)
          # Scan with the original string number
          grep ${NTS} --binary-files=text "${SCANSTRING}${SCANSTRINGLASTNR}" ${SCRIPT_PWD}/known_bugs.strings 2>/dev/null | sed 's|[ \t]\+| |g;s/^/  | /' | sort -u
          # Scan with the original string number -1 (0 is not fine; already handled above)
          SCANSTRINGLASTNR=$[ ${SCANSTRINGLASTNR} - 1 ]
          grep ${NTS} --binary-files=text "${SCANSTRING}${SCANSTRINGLASTNR}" ${SCRIPT_PWD}/known_bugs.strings 2>/dev/null | sed 's|[ \t]\+| |g;s/^/  | /' | sort -u
          # Scan with the original string number +1 (9 is fine; this becomes 10 and that would be the next upper neighbour)
          SCANSTRINGLASTNR=$[ ${SCANSTRINGLASTNR} + 2 ]
          grep ${NTS} --binary-files=text "${SCANSTRING}${SCANSTRINGLASTNR}" ${SCRIPT_PWD}/known_bugs.strings 2>/dev/null | sed 's|[ \t]\+| |g;s/^/  | /' | sort -u
        fi
      fi
    fi
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
    echo -e "${STRING_OUT}${COUNT_OUT}$(echo ${MATCHING_TRIALS[@]}|sed 's| |,|g'))"
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
    echo "$(echo -e "${STRING_OUT}${COUNT_OUT}${MATCHING_TRIALS[@]})" | sed 's|, |,|g;s|,)|)|')"
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
  echo -e "${STRING_OUT}${COUNT_OUT}$(ls */SHUTDOWN_TIMEOUT_ISSUE 2>/dev/null | sed 's|/.*||' | sort -un | tr '\n' ',' | sed 's|,$||'))"
  COUNT=
  STRING_OUT=
  COUNT_OUT=
  TRIALS_MDEV_30418="$(grep --binary-files=text -il 'set.*global.*wsrep_cluster_address' [0-9]*/default.node.tld_thread-*.sql 2>/dev/null | sed 's|/.*||' | sort -u | xargs -I{} echo "grep --binary-files=text -il 'set.*global.*wsrep_slave_threads' {}/default.node.tld_thread-*.sql 2>/dev/null" | tr '\n' '\0' | xargs -0 -I{} bash -c "{}" | sed 's|/.*||' | sort -u | grep -E "$(ls --color=never [0-9]*/SHUTDOWN_TIMEOUT_ISSUE 2>/dev/null | sed 's|/.*||' | tr '\n' '|' | sed 's/[|]\+$//')" | sort -h | tr '\n' ' ' | sed 's|[ ]\+$||')"
  if [ ! -z "${TRIALS_MDEV_30418}" ]; then
    echo '** Trials with SET GLOBAL of wsrep_cluster_address & wsrep_slave_threads (known hang/timeout issue MDEV-30418):'
    echo "${TRIALS_MDEV_30418}"
  fi
  TRIALS_MDEV_30418=
  TRIALS_MASTER_POS_WAIT="$(grep --binary-files=text -il 'start.*slave' [0-9]*/default.node.tld_thread-*.sql 2>/dev/null | sed 's|/.*||' | sort -u | xargs -I{} echo "grep --binary-files=text -il 'master_pos_wait' {}/default.node.tld_thread-*.sql 2>/dev/null" | tr '\n' '\0' | xargs -0 -I{} bash -c "{}" | sed 's|/.*||' | sort -u | grep -E "$(ls --color=never [0-9]*/SHUTDOWN_TIMEOUT_ISSUE 2>/dev/null | sed 's|/.*||' | tr '\n' '|' | sed 's/[|]\+$//')" | sort -h | tr '\n' ' ' | sed 's|[ ]\+$||')"
  if [ ! -z "${TRIALS_MASTER_POS_WAIT}" ]; then
    echo '** Trials with START SLAVE & MASTER_POS_WAIT (known hang/timeout issue waiting for an invalid position):'
    echo "${TRIALS_MASTER_POS_WAIT}"
  fi
  TRIALS_MASTER_POS_WAIT=
  TRIALS_MDEV_22727="$(grep --binary-files=text -il 'set.*aria_group_commit_interval' [0-9]*/default.node.tld_thread-*.sql 2>/dev/null | sed 's|/.*||' | sort -u | xargs -I{} echo "grep --binary-files=text -il 'set.*aria_group_commit.*hard' {}/default.node.tld_thread-*.sql 2>/dev/null" | tr '\n' '\0' | xargs -0 -I{} bash -c "{}" | sed 's|/.*||' | sort -u | grep -E "$(ls --color=never [0-9]*/SHUTDOWN_TIMEOUT_ISSUE 2>/dev/null | sed 's|/.*||' | tr '\n' '|' | sed 's/[|]\+$//')" | sort -h | tr '\n' ' ' | sed 's|[ ]\+$||')"
  if [ ! -z "${TRIALS_MDEV_22727}" ]; then
    echo '** Trials with SET aria_group_commit_interval & SET aria_group_commit=HARD (known hang/timeout issue MDEV-22727):'
    echo "${TRIALS_MDEV_22727}"
  fi
  TRIALS_MDEV_22727=
  TRIALS_NET_RETRY="$(grep --binary-files=text -il 'set.*net_retry_count' [0-9]*/default.node.tld_thread-*.sql 2>/dev/null | sed 's|/.*||' | sort -u | grep -E "$(ls --color=never [0-9]*/SHUTDOWN_TIMEOUT_ISSUE 2>/dev/null | sed 's|/.*||' | tr '\n' '|' | sed 's/[|]\+$//')" | sort -h | tr '\n' ' ' | sed 's|[ ]\+$||')"
  if [ ! -z "${TRIALS_NET_RETRY}" ]; then
    echo '** Trials with SET net_retry_count (known to cause hang/timeout issues):'
    echo "${TRIALS_NET_RETRY}"
  fi
  TRIALS_NET_RETRY=
  TRIALS_MDEV_35064="$(grep --binary-files=text -il "CREATE.*SERVER.*WRAPPER.*HOST[ \t]\+'1');" [0-9]*/default.node.tld_thread-*.sql*out*out* 2>/dev/null | sed 's|/.*||' | sort -u | grep -E "$(ls --color=never [0-9]*/SHUTDOWN_TIMEOUT_ISSUE 2>/dev/null | sed 's|/.*||' | tr '\n' '|' | sed 's/[|]\+$//')" | sort -h | tr '\n' ' ' | sed 's|[ ]\+$||')"
  if [ ! -z "${TRIALS_MDEV_35064}" ]; then
    echo '** Trials with "CREATE SERVER.*WRAPPER.*HOST '1');" in reduced traces (known to cause thread-hang issues: ref MDEV-35064):'
    echo "${TRIALS_MDEV_35064}"
  fi
  TRIALS_MDEV_35064=
  TRIALS_MDEV_25611="$(grep --binary-files=text -il 'innodb_flush_log_at_timeout' [0-9]*/default.node.tld_thread-*.sql 2>/dev/null | sed 's|/.*||' | sort -u | xargs -I{} echo "grep --binary-files=text -il 'RESET[ \t]*MASTER' {}/default.node.tld_thread-*.sql 2>/dev/null" | tr '\n' '\0' | xargs -0 -I{} bash -c "{}" | sed 's|/.*||' | sort -u | grep -E "$(ls --color=never [0-9]*/SHUTDOWN_TIMEOUT_ISSUE 2>/dev/null | sed 's|/.*||' | tr '\n' '|' | sed 's/[|]\+$//')" | sort -h | tr '\n' ' ' | sed 's|[ ]\+$||')"
  if [ ! -z "${TRIALS_MDEV_25611}" ]; then
    echo '** Trials with SET innodb_flush_log_at_timeout and RESET MASTER (known to cause hang/timeout issues, ref MDEV-25611):'
    echo "${TRIALS_MDEV_25611}"
  fi
  TRIALS_MDEV_25611=
fi

# Other MDEV related issues worth highlighting, aiding issue management
TRIALS_MDEV_26492="$(grep --binary-files=text -il 'key_cache_segments' [0-9]*/default.node.tld_thread-*.sql 2>/dev/null | sed 's|/.*||' | sort -u | xargs -I{} echo "grep --binary-files=text -il 'ERROR] Got an error' {}/log/*.err 2>/dev/null" | tr '\n' '\0' | xargs -0 -I{} bash -c "{}" | sed 's|/.*||' | sort -u | sort -h | tr '\n' ' ' | sed 's|[ ]\+$||')"
if [ ! -z "${TRIALS_MDEV_26492}" ]; then
  echo '** Trials with SET key_cache_segments resulting in '[ERROR] Got an error' (from a thread or an unknown thread), a know bug; ref MDEV-26492'
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
  echo "'** SIGKILL myself' trials found: $(grep --binary-files=text -l "SIGKILL myself" ${ERROR_LOG_LOC} 2>/dev/null | sed 's|/.*||' | sort -un | tr '\n' ',' | sed 's|,$||')"
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
OOS1="$(egrep --binary-files=text -i "device full error|no space left on device|errno[:]* enospc|can't write.*bytes|errno[:]* 28|disk full|waiting for someone to free some space|out of disk space|InnoDB: preallocating.*bytes for file.*failed with error 28|innodb: error while writing|bytes should have been written|error number[:]* 28|error[:]* 28|Disk is full writing|Errcode: 28|No space left on device|Waiting for someone to free space|up to 60 secs delay for server to continue after freeing disk space" ${ERROR_LOG_LOC} 2>/dev/null | sed 's|/.*||' | tr '\n' ' ')"
OOS2="$(ls -s */data/*core* 2>/dev/null | grep --binary-files=text -o "^ *0 [^/]\+" 2>/dev/null | awk '{print $2}' | tr '\n' ' ')"  # Cores with a file size of 0: good indication of OOS
OOS3="$(ls --color=never -l */pquery.log 2>/dev/null | grep --binary-files=text '   0' | grep -o '[0-9]\+/pquery.log' | grep -o '[0-9]\+' | tr '\n' ' ')"  # pquery.log has a file size of 0: good indication of OOS
OOS4="$(grep 'Assert: /tmp does not have enough free space' */MYBUG 2>/dev/null | sed 's|/.*||' | tr '\n' ' ')"

OOS="$(echo "${OOS1} ${OOS2} ${OOS3} ${OOS4}" | sed 's|  | |g;s| $||g')"
if [ "$(echo "${OOS}" | sed "s| ||g")" != "" ]; then
  echo "** Likely out of disk space trials:"
  echo "$(echo "${OOS}" | tr ' ' '\n' | sort -nu |  tr '\n' ' ' | sed 's|$|\n|;s|^ \+||')"
fi

# Likely disk I/O issues trials
DI1=$(grep --binary-files=text "bytes should have been read. Only" ${ERROR_LOG_LOC} 2>/dev/null | sed 's|/.*||' | tr '\n' ' ')
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

# Coredumps overview (for comparison)
COREDUMPS="$(find . | grep --binary-files=text 'core' 2>/dev/null | grep --binary-files=text -vE 'parse|pquery' 2>/dev/null | cut -d '/' -f2 | sort -un | tr '\n' ' ' | sed 's|$|\n|')"
if [ "$(echo "${COREDUMPS}" | sed 's| \+||g')" != "" ]; then
  echo "** Coredumps found in trials:"
  find . | grep --binary-files=text  'core' 2>/dev/null | grep --binary-files=text -vE 'parse|pquery|vault' 2>/dev/null | cut -d '/' -f2 | sort -un | tr '\n' ' ' | sed 's|$|\n|'
fi

if [ $(ls -l reducer* qcreducer* 2>/dev/null | awk '{print $5"|"$9}' | grep --binary-files=text "^0|" 2>/dev/null | sed 's/^0|//' | wc -l) -gt 0 ]; then
  echo "Detected one or more empty (0 byte) reducer script(s): $(ls -l reducer* qcreducer* 2>/dev/null | awk '{print $5"|"$9}' | grep --binary-files=text "^0|" 2>/dev/null | sed 's/^0|//' | tr '\n' ' ')- you may want to check what's causing this (possibly a bug in pquery-prep-red.sh, or did you simply run out of space while running pquery-prep-red.sh?) and do the analysis for these trial numbers manually, or free some space, delete the reducer*.sh scripts and re-run pquery-prep-red.sh"
fi

# Stack smashing overview
if [ ! -z "$(grep --binary-files=text 'smashing' ${ERROR_LOG_LOC} 2>/dev/null)" ]; then
  echo "** Stack smashing detected:"
  grep --binary-files=text 'smashing' ${ERROR_LOG_LOC} 2>/dev/null
fi

# Significant/major error scanning. This code is partially duplicated in pquery-run.sh as well as in pquery-del-trial.sh. Update all three when making changes. TODO: integrate this code into a new script to de-duplicate the code
ERRORS=
ERROR_LOG=
ERRORS_LAST_LINE=
REGEX_ERRORS_SCAN=
REGEX_ERRORS_LASTLINE=
REGEX_ERRORS_FILTER="NOFILTERDUMMY"  # Leave NOFILTERDUMMY to avoid filtering everything. It will be replaced later if a REGEX_ERRORS_FILTER file is present in mariadb-qa (and by default there is)
if [ -r ${SCRIPT_PWD}/REGEX_ERRORS_SCAN ]; then
  REGEX_ERRORS_SCAN="$(cat ${SCRIPT_PWD}/REGEX_ERRORS_SCAN 2>/dev/null | tr -d '\n')"
  if [ -z "${REGEX_ERRORS_SCAN}" ]; then
    echo '** Significant/Major errors (if any)'
    echo "Error: ${REGEX_ERRORS_SCAN} is empty?"
    exit 1
  fi
else
  echo '** Significant/Major errors (if any)'
  echo "Error: ${REGEX_ERRORS_SCAN} could not be read by this script"
  exit 1
fi
if [ -r ${SCRIPT_PWD}/REGEX_ERRORS_LASTLINE ]; then
  REGEX_ERRORS_LASTLINE="$(cat ${SCRIPT_PWD}/REGEX_ERRORS_LASTLINE 2>/dev/null | tr -d '\n')"
  if [ -z "${REGEX_ERRORS_LASTLINE}" ]; then
    echo '** Significant/Major errors (if any)'
    echo "Error: ${REGEX_ERRORS_LASTLINE} is empty?"
    exit 1
  fi
else
  echo '** Significant/Major errors (if any)'
  echo "Error: ${REGEX_ERRORS_LASTLINE} could not be read by this script"
  exit 1
fi
if [ -r ${SCRIPT_PWD}/REGEX_ERRORS_FILTER ]; then
  REGEX_ERRORS_FILTER="$(cat ${SCRIPT_PWD}/REGEX_ERRORS_FILTER 2>/dev/null | tr -d '\n')"
fi
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
rm -f ./errorlogs.tmp
find . -type f -name "master.err" | grep '\./[0-9]\+/log/master.err' > ./errorlogs.tmp
find . -type f -name "slave.err" | grep '\./[0-9]\+/log/slave.err' >> ./errorlogs.tmp
if [ -r ./errorlogs.tmp ]; then
  FIST_OCCURRENCE=0
  while read ERROR_LOG; do
    if [ -r ${ERROR_LOG} ]; then
      # Note that the next line does not use -Eio but -Ei. The 'o' should not be used here as that will cause the filter to fail where the search string (REGEX_ERRORS_SCAN) contains for example 'corruption' and the filter looks for 'the required persistent statistics storage is not present or is corrupted'
      # Filtering 'MariaDB error code' is a bit wide, but the pquery-results output is simply too large without including this
      ERROR_MSG_FILTER='Warning: Memory not freed|mysqld: Got error|is marked as crashed|MariaDB error code|slave SQL thread aborted' # 'Warning: Memory not freed' etc. are now handled by new_text_string.sh and will show up in the UniqueID list already, not much point including them here again (except here it shows for example the actual memory lost in bytes size, but it also really clogs the output/screen)  # 'slave SQL thread aborted' is now handled by it's own '** Trials where the slave SQL thread aborted' section, which provides much cleaner and shorter overall pr output
      ERRORS="$(grep --binary-files=text -Ei "${REGEX_ERRORS_SCAN}" ${ERROR_LOG} 2>/dev/null | sort -u 2>/dev/null | grep --binary-files=text -vE "${REGEX_ERRORS_FILTER}" | grep --binary-files=text -vE "${ERROR_MSG_FILTER}" | grep -vE "^[ \t]*$")"
      ERRORS_LAST_LINE="$(tail -n1 ${ERROR_LOG} 2>/dev/null | grep --no-group-separator --binary-files=text -B1 -E "${REGEX_ERRORS_LASTLINE}" | grep -vE "${REGEX_ERRORS_FILTER}" | grep -vE "${ERROR_MSG_FILTER}" | grep -vE "^[ \t]*$")"
      if [ ! -z "${ERRORS}" -o ! -z "${ERRORS_LAST_LINE}" ]; then
        if [ "${FIST_OCCURRENCE}" != "1" ]; then
          echo "** Significant/Major errors (if any)"
          FIST_OCCURRENCE=1
        fi
        echo "${ERROR_LOG}: $(DOUBLE=0; echo "$(if [ ! -z "${ERRORS}" ]; then echo -n "${ERRORS}"; DOUBLE=1; fi; if [ ! -z "${ERRORS_LAST_LINE}" ]; then if [ "${DOUBLE}" -eq 1 ]; then echo ", ${ERRORS_LAST_LINE}"; else echo ", ${ERRORS_LAST_LINE}"; fi; else echo ''; fi;)" | sed 's|^[ ]+||;s|[ ]\+$||')" | sed 's|:[ ,]\+mariadbd: /test.*_dbg/|: |;s|: Assertion |Assertion |'
      fi
    fi
  done < ./errorlogs.tmp
fi
rm -f ./errorlogs.tmp

extract_valgrind_error(){
  for i in $( ls  ${ERROR_LOG_LOC} 2>/dev/null); do
    TRIAL=$(echo $i | cut -d'/' -f1)
    echo "** Trial $TRIAL"
    grep --binary-files=text -E --no-group-separator  -A4 "Thread[ \t][0-9]+:" $i 2>/dev/null | cut -d' ' -f2- |  sed 's/0x.*:[ \t]\+//' |  sed 's/(.*)//' | rev | cut -d '(' -f2- | sed 's/^[ \t]\+//' | rev  | sed 's/^[ \t]\+//'  |  tr '\n' '|' |xargs |  sed 's/Thread[ \t][0-9]\+:/\nIssue #/ig'
  done
}

if [ ${VALGRINDOUTPUT} -eq 1 ]; then
  extract_valgrind_error
fi
