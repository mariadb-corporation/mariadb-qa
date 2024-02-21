#!/bin/bash
# For large-scale newbug verification/reduction runs
THREADS=15

if [ -r ${HOME}/ds ]; then
  if ! grep -q '^FILTER_LARGE_NEWBUG_RUNS=1' ${HOME}/ds; then
    echo "Assert: please set FILTER_LARGE_NEWBUG_RUNS to =1 in ${HOME}/ds"
    exit 1
  fi
else
  echo "Warning: ${HOME}/ds does not exist, you can run ~/mariadb-qa/linkit (on non-production instances) to create it"
fi

if [ ! -d /data/NEWBUGS ]; then
  echo "Assert: /data/NEWBUGS does not exist"
  exit 1
else
  cd /data/NEWBUGS
fi

if [ "${STY}" == "" ]; then
  THIS_SCRIPT="$(readlink -f $0)"  # Resolves symlinks, result is the actual script including directory
  SCREEN_NAME='lnbr'
  echo "Not a screen, restarting myself inside a screen"
  screen -admS "${SCREEN_NAME}" bash -c "${THIS_SCRIPT} ${*}"
  sleep 1
  screen -d -r "${SCREEN_NAME}"
  return 2> /dev/null; exit 0
fi

echo "Commencing ${THREADS} reducer threads..."
echo 'Use this command to stop all newbug reduction activity:'
echo 'ps -ef | grep newbug | grep -vE "grep|large_newbug_run" | awk "{print $2}" | xargs kill -9 2>/dev/null'
./uniq_newbugs | grep -o 'newbug_[0-9]\+\.reducer\.sh' | tr '\n' '\0' | xargs -I{} -0 -P${THREADS} bash -c 'echo Starting {}...; ./{} > ./{}.log 2>&1'
