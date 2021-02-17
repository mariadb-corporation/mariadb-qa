#!/bin/bash
# Created by Roel Van de Paar, Percona LLC

# This script quickly patches a reducer<trialnr>.sh or newbug_...sh script from FORCE_SKIPV set on to off, 
# and sets it to the already reduced _out sql file. This is very handy when the following procedure was used;
# pquery-run.sh > pquery-go-expert.sh > {reducer<trialnr>.sh or pquery-mass-reducer.sh} > testcase reduced 
# but now stuck at stage1 and ~4 lines (multi-threaded) > this script > restart reducer<trialnr>.sh with 
# the said changes done by this script. It will then run through all other stages

if [ "$1" == "" ]; then
  echo "Assert: This script expects one option, namely the trial number for which this script should patch reducer<trialnr>.sh"
  echo "Terminating."
  exit 1
elif [ "$(echo $1 | sed 's|^[0-9]\+||')" != "" ]; then
  R1="$(echo "${1}" | sed 's|^\./||')"
  if [[ "${R1}" == "newbug_"* ]]; then
    if [ -f "./${R1}" -a -r "./${R1}" ]; then
      REDUCER="${R1}"
    else
      echo "Assert: the reducer script passed to this script (${REDUCER}) is not a file readable by this script!" 
      exit 1
    fi
  else
    echo "Assert: option passed is not numeric. If you do not know how to use this script, execute it without options to see more information"
    exit 1
  fi
else
  REDUCER="reducer${1}.sh"
fi

# Patch reducer
sed -i "s|^FORCE_SKIPV=1|FORCE_SKIPV=0|" ${REDUCER}
sed -i "s|^STAGE1_LINES=[0-9]\+|STAGE1_LINES=1000|" ${REDUCER}

# Start reducer
./${REDUCER}
