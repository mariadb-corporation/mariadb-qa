#!/bin/bash
# Source this script from your script and then you can use init_empty_port() to find an empty port. 
# The empty port number will then be stored in the ${NEWPORT} variable for you to use.
init_empty_port(){  # Find an empty port
  # Choose a random port number in 10-13K range (**), with triple check to confirm it is free
  # Note that reducer.sh uses a 13-47K port range, whereas init_empty_port.sh uses 10-13K to further avoid conflicts
  NEWPORT=$[ 10001 + ( ${RANDOM} % 3000 ) ]
  DOUBLE_CHECK=0
  while :; do
    # Check if the port is free in four different ways
    ISPORTFREE1="$(netstat -an | tr '\t' ' ' | grep -E --binary-files=text "[ :]${NEWPORT} " | wc -l)"
    ISPORTFREE2="$(ps -ef | grep --binary-files=text "port=${NEWPORT}" | grep --binary-files=text -v 'grep')"
    ISPORTFREE3="$(grep --binary-files=text -o "port=${NEWPORT}" /test/*/start 2>/dev/null | wc -l)"
    ISPORTFREE4="$(netstat -tuln | grep :${NEWPORT})"
    if [ "${ISPORTFREE1}" -eq 0 -a -z "${ISPORTFREE2}" -a "${ISPORTFREE3}" -eq 0 -a -z "${ISPORTFREE4}" ]; then
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

