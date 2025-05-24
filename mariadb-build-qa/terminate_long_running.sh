#!/bin/bash
# Created by Roel Van de Paar, MariaDB
# Memory watchdog: read script comments for more information

# User variables
MAX_RUNTIME=1200  # In seconds. Default: 1200 (20 minutes). Minimum 180 seconds to avoid conflicts with other timeouts, but such a low setting is not a good idea. Minimum recommended is 900 (15 minutes)
MAX_DEFUNCT=1140  # In seconds. Default: 1140 (19 minutes). Idem.
FILTER='grep|build|fireworks|mtr_to_sql|generator.sh|cc|clang|reducer|screen|bash|pge|pquery-go|pquery-run|timeout|mysql-test-run|xargs|cc|clang|addr2line|pquery-clean-kn|cat|cp|tar|file|screen|ds|new_text_string|tmpfs_clean.sh|rm|fallback_text_s|san_text_string|vi|vim'

# Loop through all pquery/mariadbd/mysqld/mariadb/mysqld testing processes and terminate if long-running
echo "--- Terminating pquery|mariadb|mysql processes which have been live at least ${MAX_RUNTIME} sec"
ps -eo pid,etimes,comm,args --no-headers | grep --binary-files=text -E 'pquery|mariadb|mysql' | grep --binary-files=text -vEi 'gal' | while read -r pid etimes comm args; do
  if [ ! -z "$(echo "${comm}" | grep --binary-files=text -vEi "${FILTER}" | tr -d ' ')" ]; then  # Filter
    if [ "${etimes}" -gt ${MAX_RUNTIME} -a "${etimes}" != "4123168608" ]; then  # 4123168608: TODO: output bug? added filtering ftm to avoid wrong terminations
      for((l=0;l<3;l++)){
        sudo kill -9 ${pid} 2>/dev/null
      }
      echo "Process ${pid} (${comm}), running for ${etimes} seconds, terminated" | tee -a /tmp/terminate_long_running.log
     fi
  fi
done

# Terminate <defunct> (already dead) processes by killing the parent process provided that has been live at least MAX_DEFUNCT seconds
echo "--- Terminating parent PPIDs of <defunct> processes where the process has been live at least ${MAX_DEFUNCT} sec"
COUNT="$(ps -eo pid,ppid,etimes,state --no-headers | awk -v m=${MAX_DEFUNCT} '$4 == "Z" && $3 > m' | wc -l)"
COUNTER=0
ps -eo pid,ppid,etimes,state --no-headers | awk -v m=${MAX_DEFUNCT} '$4 == "Z" && $3 > m' | while read -r pid ppid etimes state; do  # awk: grep on col 4 being Z
  COUNTER=$[ ${COUNTER} + 1 ]
  echo "[${COUNTER}/${COUNT}] Processing <defunct> PID $pid with parent PPID $ppid (Age: $etimes sec)"  # Do not log to disk as these messages may loop many times
  if [ "${etimes}" -gt ${MAX_DEFUNCT} -a "${etimes}" != "4123168608" ]; then  # The first condition is defensive coding/not strictly needed as the awk above already guarantees this (but not the second)
    if kill -0 "$ppid" 2>/dev/null; then
      echo "Terminating parent PPID ${ppid} of <defunct> PID ${pid} (Age: ${etimes} sec)" | tee -a /tmp/terminate_long_running.log
      for((l=0;l<3;l++)){
        sudo kill -9 ${ppid} 2>/dev/null
      }
    else
      echo "<defunct> PID ${pid} (Age: ${etimes} sec) already has dead parent PPID ${ppid}"  # Do not log, idem
    fi
  fi
done
COUNT=
COUNTER=
