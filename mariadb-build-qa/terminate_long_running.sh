#!/bin/bash
CURRENT_TIME=$(date +%s)
MAX_RUNTIME=900  # seconds
# Loop through all pquery/mariadbd/mysqld/mariadb/mysqld testing processes and terminate if long-running
ps -eo pid,etimes,comm,args | grep --binary-files=text -E 'pquery|mariadb|mysql' | grep --binary-files=text -vEi 'gal' | grep --binary-files=text -vEi 'build|fireworks|mtr_to_sql|generator.sh|cc|clang|reducer' | while read -r pid etimes comm args; do
  if [ "$etimes" -gt ${MAX_RUNTIME} ]; then
    kill -9 $pid 2>/dev/null
    echo "Process ${pid} (${comm}), running for ${etimes} seconds, terminated"
  fi
done
