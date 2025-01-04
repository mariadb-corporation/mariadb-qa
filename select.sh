#!/bin/bash
if [ "${STY}" == "" ]; then
  THIS_SCRIPT="$(readlink -f $0)"  # Resolves symlinks, result is the actual script including directory
  SCREEN_NAME='loopselect'
  echo "Not a screen, restarting myself inside a screen"
  screen -admS "${SCREEN_NAME}" bash -c "${THIS_SCRIPT} ${*}"
  sleep 1
  screen -d -r "${SCREEN_NAME}"
  return 2> /dev/null; exit 0
fi

mkdir -p ./select
echo "grep 'ALREADY KNOWN BUG' tt_*log | wc -l ; ls tt_*log | wc -l" > select/count
chmod +x select/count
NR="$(ls tt_*.log 2>/dev/null | grep -o '[0-9]\+' | sort -n | tail -n1)"
if [ -z "${NR}" ]; then NR=0; fi
while true; do
  NR=$[ ${NR} + 1 ]
  ./anc
  python3 ./select.py
  sync
  cat executed_queries.log failed_queries.log > select/tc_${NR}.sql
  cp failed_queries.log select/fail_${NR}.log
  rm -f executed_queries.log failed_queries.log
  ${HOME}/mariadb-qa/homedir_scripts/tt > select/tt_${NR}.log
  cp log/master.err select/err_${NR}.log
  ./stack > select/stack_${NR}.log
done
