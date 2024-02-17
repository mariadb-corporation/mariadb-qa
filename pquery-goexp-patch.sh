#!/bin/bash
# Created by Roel Van de Paar, Percona LLC

# This script quickly patches a reducer<trialnr>.sh or newbug_...sh script from FORCE_SKIPV set on to off,
# This is very handy when the following procedure was used; pquery-run.sh > pquery-go-expert.sh >
# {reducer<trialnr>.sh or pquery-mass-reducer.sh} > testcase reduced, but now stuck at stage1 and ~4 lines
# (multi-threaded) > this script > restart reducer<trialnr>.sh with the said changes done by this script.
# It will then run through all other stages

if [ "$1" == "" ]; then
  echo "Assert: This script expects one option, namely the trial number for which this script should patch reducer<trialnr>.sh Note: you can also use, for example, 5-1 for reducer5-1.sh - in the case of reducers for MDG runs."
  echo "Terminating."
  exit 1
else
  R1="$(echo "${1}" | sed 's|^/data/NEWBUGS/||;s|NEWBUGS/||;s|^\.[/]*||')"
  if [ -f "/data/NEWBUGS/newbug_${R1}.reducer.sh" ]; then  # Add ./newbug_ and .reducer.sh if it was not specified
    cd /data/NEWBUGS
    R1="newbug_${R1}.reducer.sh"
    REDUCERLOG="newbug_${R1}.reducer.log"
  fi
  if [ -f "/data/NEWBUGS/newbug_${R1}" ]; then  # Add ./newbug_ if it was not specified
    cd /data/NEWBUGS
    R1="newbug_${R1}"
    REDUCERLOG="$(echo "newbug_${R1}.log" | sed 's|\.sh||')"
  fi
  if [ -f "/data/NEWBUGS/${R1}.reducer.sh" ]; then  # Add .reducer.sh if it was not specified
    cd /data/NEWBUGS
    R1="${R1}.reducer.sh"
    REDUCERLOG="${R1}.reducer.log"
  fi
  if [ -f "/data/NEWBUGS/${R1}" ]; then  # Correct name already
    cd /data/NEWBUGS
    REDUCERLOG="$(echo "newbug_${R1}.log" | sed 's|\.sh||')"
  fi
  R_TMP="$(echo "${R1}" | sed 's|^s||')"
  if [ -f "/data/NEWBUGS/${R_TMP}" ]; then  # Correct name already, except leading 's', remove it
    R1="${R_TMP}"
    cd /data/NEWBUGS
    REDUCERLOG="$(echo "newbug_${R1}.log" | sed 's|\.sh||')"
  fi
  R_TMP=
  if [[ "${R1}" == *"newbug"* ]]; then
    if [ -f "./${R1}" -a -r "./${R1}" ]; then
      REDUCER="${R1}"
      REDUCERLOG="reducer${1}.log"
    else
      echo "Assert: the reducer script passed to this script (${REDUCER}) is not a file readable by this script!"
      exit 1
    fi
  elif [ ! -z "$(echo "${R1}" | sed 's|[0-9]||g')" ]; then
    echo "Assert: option passed is not numeric nor a valid newbug reducer"
    echo "Execute this script without options to see more information"
    exit 1
  else
    if [ -r ./reducer_val${1}.sh ]; then  # Valgrind
      REDUCER="reducer_val${1}.sh"
      REDUCERLOG="reducer_val${1}.log"
    else  # All regular ~/pge calls (generic server, SAN)
      REDUCER="reducer${1}.sh"
      REDUCERLOG="reducer${1}.log"
    fi
  fi
fi

if [ ! -r ${REDUCER} -o ! -f ${REDUCER} ]; then
  echo "Assert: ${REDUCER} does not exist!"
  exit 1
fi

# Patch reducer
if [[ "${0}" == *"depge"* || "${2}" == "depge" ]]; then  # Reverse (de-) pge changes, i.e. ~/depge, and increase threads to reduce more easily
  sed -i "s|^FORCE_SKIPV=0|FORCE_SKIPV=1|" ${REDUCER}
  sed -i "s|^STAGE1_LINES=[0-9]\+|STAGE1_LINES=3|" ${REDUCER}
  sed -i "s|^MULTI_THREADS=[0-9]\+|MULTI_THREADS=3|" ${REDUCER}
else  # Normal, i.e. ~/pge
  sed -i "s|^FORCE_SKIPV=1|FORCE_SKIPV=0|" ${REDUCER}
  sed -i "s|^STAGE1_LINES=[0-9]\+|STAGE1_LINES=1000|" ${REDUCER}
fi

# Start reducer
mkdir -p ./reducer.logs
./${REDUCER} | tee -a ./reducer.logs/${REDUCERLOG}
