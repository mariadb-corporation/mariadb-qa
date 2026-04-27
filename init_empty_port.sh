#!/bin/bash
# Source this script from your script and then you can use init_empty_port() to find an empty port.
# The empty port number will then be stored in the ${NEWPORT} variable for you to use.

# Two parallel pickers can both observe a port as free via netstat/ps/lsof — neither has called bind(2) yet.
# Reservation closes that gap: each picker writes its PID into a claim file under flock, so other in-flight
# pickers see the claim and skip the port until the owner has bound or exited.
_INIT_EMPTY_PORT_CLAIM_DIR=/tmp/.mariadb_qa_ports
_INIT_EMPTY_PORT_LOCK_FILE=/tmp/.mariadb_qa_port_lock
_INIT_EMPTY_PORT_CLAIMED=
_INIT_EMPTY_PORT_TRAP_SET=

_init_empty_port_cleanup(){
  local p
  for p in ${_INIT_EMPTY_PORT_CLAIMED}; do
    rm -f "${_INIT_EMPTY_PORT_CLAIM_DIR}/${p}"
  done
}

init_empty_port(){  # Find an empty port
  # Choose a random port number in 10-13K range. The port must be observed free across 3 consecutive iterations (DOUBLE_CHECK reaches 2) before being claimed under the lock.
  # Note that reducer.sh uses a 13-47K port range, whereas init_empty_port.sh uses 10-13K to further avoid conflicts
  mkdir -p "${_INIT_EMPTY_PORT_CLAIM_DIR}" 2>/dev/null
  # fd 9 is local to this function; the lock releases when fd 9 is closed below.
  exec 9>"${_INIT_EMPTY_PORT_LOCK_FILE}"
  flock -x 9
  # Reap claims whose owner PID is no longer alive (covers SIGKILL'd or crashed owners).
  local _stale _owner
  for _stale in "${_INIT_EMPTY_PORT_CLAIM_DIR}"/[0-9]*; do
    [ -f "${_stale}" ] || continue
    _owner=$(cat "${_stale}" 2>/dev/null)
    if [ -n "${_owner}" ] && ! kill -0 "${_owner}" 2>/dev/null; then rm -f "${_stale}"; fi
  done

  NEWPORT=$[ 10001 + ( ${RANDOM} % 3000 ) ]
  DOUBLE_CHECK=0
  while :; do
    # Skip ports already promised to another in-flight picker.
    if [ -e "${_INIT_EMPTY_PORT_CLAIM_DIR}/${NEWPORT}" ]; then
      NEWPORT=$[ 10001 + ( ${RANDOM} % 3000 ) ]
      DOUBLE_CHECK=0
      continue
    fi
    # Check if the port is free in four different ways
    ISPORTFREE1="$(netstat -an | tr '\t' ' ' | grep -E --binary-files=text "[ :]${NEWPORT} " | wc -l)"
    ISPORTFREE2="$(ps -ef | grep --binary-files=text "port=${NEWPORT}" | grep --binary-files=text -v 'grep')"
    ISPORTFREE3="$(grep --binary-files=text -o "port=${NEWPORT}" /test/*/start 2>/dev/null | wc -l)"
    ISPORTFREE4="$(netstat -tuln | grep :${NEWPORT})"
    ISPORTFREE5="$(lsof -i :${NEWPORT})"
    if [ "${ISPORTFREE1}" -eq 0 -a "${ISPORTFREE3}" -eq 0 -a -z "${ISPORTFREE2}${ISPORTFREE4}${ISPORTFREE5}" ]; then
      if [ "${DOUBLE_CHECK}" -eq 2 ]; then  # 3 successive free observations seen
        # Claim must be written while still holding the lock so concurrent pickers cannot select the same port.
        echo "$$" > "${_INIT_EMPTY_PORT_CLAIM_DIR}/${NEWPORT}"
        _INIT_EMPTY_PORT_CLAIMED="${_INIT_EMPTY_PORT_CLAIMED} ${NEWPORT}"
        if [ -z "${_INIT_EMPTY_PORT_TRAP_SET}" ]; then
          trap '_init_empty_port_cleanup' EXIT
          _INIT_EMPTY_PORT_TRAP_SET=1
        fi
        # Brief settle pause keeps the lock held while the caller starts bind(); subsequent pickers see the claim with high reliability.
        sleep 0.2
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
  exec 9>&-
}
