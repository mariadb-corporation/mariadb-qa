#!/bin/bash
MAX_RUNTIME=1200  # In seconds. Default: 1200 (20 minutes). Minimum 180 seconds to avoid conflicts with other timeouts
FILTER='grep|build|fireworks|mtr_to_sql|generator.sh|cc|clang|reducer|screen|bash|pge|pquery-go|pquery-run|timeout|mysql-test-run|xargs|cc|clang|addr2line'
# Loop through all pquery/mariadbd/mysqld/mariadb/mysqld testing processes and terminate if long-running
ps -eo pid,etimes,comm,args | grep --binary-files=text -E 'pquery|mariadb|mysql' | grep --binary-files=text -vEi 'gal' | grep --binary-files=text -vEi "${FILTER}" | while read -r pid etimes comm args; do
  if [ "$etimes" -gt ${MAX_RUNTIME} ]; then
    kill -9 $pid 2>/dev/null
    echo "Process ${pid} (${comm}), running for ${etimes} seconds, terminated" | tee -a /tmp/terminate_long_running.log
  fi
done
