#!/bin/bash
# Find empty port
# (**) IMPORTANT WARNING! The init_empty_port scan in startup.sh uses a different range than the matching function in
# pquery-run.sh, reducer.sh and reducer-STABLE.sh. These scripts use 13-65K whereas here we use 10-13K to avoid
# conflicts between the initially-random, but hard coded (whenever ~/start is run) port allocations in the basedir
# scripts which use port numbers, like ./start. The script further checks that a given random port is not already
# in use in the startup script of other basedirs. These two methods should avoid as good as all possible port conflicts.
# Originally all scripts used 10-65K but it was relatively easy to get a port conflict as non-started basedir servers
# may have had their ports allocated by for example a reducer, and then cause a conflict when started. The result of the
# port alloc range difference is that this function here (in startup.sh) cannot be copied verbatim to other scripts.
init_empty_port(){
  # Choose a random port number in 10-13K range (**), with triple check to confirm it is free
  NEWPORT=$[ 10001 + ( ${RANDOM} % 3000 ) ]
  DOUBLE_CHECK=0
  while :; do
    # Check if the port is free in three different ways
    ISPORTFREE1="$(netstat -an | tr '\t' ' ' | grep -E --binary-files=text "[ :]${NEWPORT} " | wc -l)"
    ISPORTFREE2="$(ps -ef | grep --binary-files=text "port=${NEWPORT}" | grep --binary-files=text -v 'grep')"
    ISPORTFREE3="$(grep --binary-files=text -o "port=${NEWPORT}" /test/*/start 2>/dev/null | wc -l)"
    if [ "${ISPORTFREE1}" -eq 0 -a -z "${ISPORTFREE2}" -a "${ISPORTFREE3}" -eq 0 ]; then
      if [ "${DOUBLE_CHECK}" -eq 2 ]; then  # If true, then the port was triple checked (to avoid races) to be free
        break  # Suitable port number found
      else
        DOUBLE_CHECK=$[ ${DOUBLE_CHECK} + 1 ]
        sleep 0.0${RANDOM}  # Random Microsleep to further avoid races
        continue  # Loop the check
      fi
    else
      NEWPORT=$[ 10001 + ( ${RANDOM} % 3000 ) ]  # Try a new port
      DOUBLE_CHECK=0  # Reset the double check
      continue  # Recheck the new port
    fi
  done
}

