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

./corlogic                    \
  TRIALS=0                    \
  QUERIES_PER_TRIAL=500       \
  BASEDIRS="                  \
    /test/MS211024-mysql-9.1.0-linux-x86_64-opt,      \
    /test/MD180826-mariadb-13.1.0-linux-x86_64-opt,   \
  "
