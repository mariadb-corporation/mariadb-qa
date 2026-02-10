#!/bin/bash
# Created by Roel Van de Paar, Percona LLC
# Expanded by Roel Van de Paar, MariaDB

# This script starts x (first option) new reducers based on the pquery-results.sh output (one reducer per issue seen - using the first failing trail for that issue), skipping the first n reducers (second option)

# Internal variables
SCRIPT_PWD=$(dirname $(readlink -f "${0}"))

if [ "$1" == "" ]; then
  echo "Assert: This script expects one option: how many reducers to start on pquery-results.sh output."
  echo "Note that you can set this to a high number to ensure all issues in the current dir are reduced."
  echo "Additionally one can pass a second option to 'skip' a number of results."
  echo "For example, ./pquery-mass-reduce.sh 10 5 will start to reduce items 6-16 of the pquery-results.sh output."
  echo "Note that it is likely not wise to start more then 15-20 orso reducers, unless you are using a high-end server."
  echo "On a machine with 32 cores and 128GB RAM however, you can likely 50-75 reducers, or more."
  echo "Those last notes apply when pquery-go-expert.sh was used. If it was not used, then likely much less (e.g. 2-5) reducers should be started (on a higher end server), or they need to be monitored more closely. For the reason why, please see the extensive help text near the top of the pquery-go-expert.sh script"
  echo "Terminating."
  exit 1
elif [ "$(echo $1 | sed 's|^[0-9]\+||')" != "" ]; then
  echo "Assert: option passed is not numeric. If you do not know how to use this script, execute it without options to see more information"
  exit 1
fi

if [ "$2" == "" ]; then
  SKIP=0
elif [ "$(echo $2 | sed 's|^[0-9]\+||')" != "" ]; then
  echo "Assert: an option passed is not numeric. Execute this script without options to see more information"
  exit 1
else
  SKIP=$2
fi
TOTAL=$[ $1 + $SKIP ]

RND=${RANDOM}
# For each issue, take the first trial number and sent it to a file
${SCRIPT_PWD}/pquery-results.sh | grep '(Seen ' | grep -v 'reducers)$' | grep -o "reducers.*" | sed 's|reducers ||;s|[,)]\+.*||' > /tmp/${RND}.txt
# Now put the issues into an issue array
mapfile -t issues < /tmp/${RND}.txt; rm -f /tmp/${RND}.txt 2>/dev/null
# Now loop though the issues. When the counter reaches the amount passed to this scirpt, the loop will terminate
COUNTER=1
for TRIAL in "${issues[@]}"; do
  RES=0
  if [ $COUNTER -gt $SKIP ]; then
    if [ -x "${HOME}/sr" ]; then  # sr has prevention against starting multiple reducers for the same issue etc. so use it if available
      ${HOME}/sr ${TRIAL}
      RES=$?
    elif [ -x "${SCRIPT_PWD}/homedir_scripts/sr" ]; then  # sr direct link; idem
      ${SCRIPT_PWD}/homedir_scripts/sr ${TRIAL}
      RES=$?
    else
      screen -admS s${TRIAL} bash -c "./reducer${TRIAL}.sh;bash"  # Start reducer, and when done provide a usable Bash prompt
      RES=$?
    fi
    if [ ${RES} -ne 1 ]; then
      echo "* Started screen with name 's${TRIAL}' and started ./reducer${TRIAL}.sh within it for issue: $(grep --binary-files=text -m1 "   TEXT=" reducer${TRIAL}.sh | sed 's|   TEXT="||;s|"$||')"
    fi
    sleep 1  # Avoid a /dev/shm/<epoch> directory conflict (yes, it happened) (yes, it happened again at 0.3 sec delay)
  fi
  COUNTER=$[ $COUNTER + 1 ]
  if [ $COUNTER -gt $TOTAL ]; then break; fi
done
echo "Done! started $[ $COUNTER - $SKIP - 1 ] screen sessions."
echo "To reconnect to any of them, use:  $ screen -d -r s<nr>  where <nr> matches the number listed in the output above!"
