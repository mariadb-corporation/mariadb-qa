#!/bin/bash
# Source this script from your script and then you can use init_empty_port() to find an empty port.
# The empty port number will then be stored in the ${NEWPORT} variable for you to use.

# Two parallel pickers can both observe a port as free via netstat/ps/lsof — neither has called bind(2) yet.
# Reservation closes that gap: each picker creates a claim file at /tmp/.mariadb_qa_ports/<port> using O_CREAT|O_EXCL
# semantics (set -o noclobber). The atomic create-or-fail is the synchronization primitive — at most one picker can
# hold a claim for a given port at any moment. No global lock; concurrent pickers that random-hit the same port are
# repelled per-port and immediately retry with another random pick.
_INIT_EMPTY_PORT_CLAIM_DIR=/tmp/.mariadb_qa_ports
_INIT_EMPTY_PORT_CLAIMED=
_INIT_EMPTY_PORT_TRAP_SET=

_init_empty_port_cleanup(){
  local p
  for p in ${_INIT_EMPTY_PORT_CLAIMED}; do
    rm -f "${_INIT_EMPTY_PORT_CLAIM_DIR}/${p}"
  done
}

init_empty_port(){  # Find an empty port
  # Pick a random port in the 10001-13000 range; reducer.sh uses the 13001-47001 range to avoid conflicts.
  mkdir -p "${_INIT_EMPTY_PORT_CLAIM_DIR}" 2>/dev/null
  # Best-effort reap of claims whose owner PID is no longer alive. Scoped to this picker's range to bound cost.
  # Race-tolerant: if a concurrent picker rewrites the file between read and rm, we re-verify ownership before unlinking.
  local _stale _owner _port _verify
  for _stale in "${_INIT_EMPTY_PORT_CLAIM_DIR}"/[0-9]*; do
    [ -f "${_stale}" ] || continue
    _port=${_stale##*/}
    if [ "${_port}" -lt 10001 ] || [ "${_port}" -gt 13000 ]; then continue; fi
    read -r _owner < "${_stale}" 2>/dev/null
    [ -n "${_owner}" ] || continue
    kill -0 "${_owner}" 2>/dev/null && continue
    read -r _verify < "${_stale}" 2>/dev/null
    [ "${_owner}" = "${_verify}" ] && rm -f "${_stale}"
  done

  while :; do
    NEWPORT=$[ 10001 + ( ${RANDOM} % 3000 ) ]
    # Atomic claim attempt. set -o noclobber makes the redirect use O_CREAT|O_EXCL; on collision with another picker
    # holding the same port, the subshell's redirect fails, the subshell exits non-zero, and we retry a fresh random port.
    if ! ( set -o noclobber; echo "$$" > "${_INIT_EMPTY_PORT_CLAIM_DIR}/${NEWPORT}" ) 2>/dev/null; then
      continue
    fi
    # We hold the claim. Verify the port is also free at the OS level (catches unrelated services bound to the port).
    ISPORTFREE1="$(netstat -an | tr '\t' ' ' | grep -E --binary-files=text "[ :]${NEWPORT} " | wc -l)"
    ISPORTFREE2="$(ps -ef | grep --binary-files=text "port=${NEWPORT}" | grep --binary-files=text -v 'grep')"
    ISPORTFREE3="$(grep --binary-files=text -o "port=${NEWPORT}" /test/*/start 2>/dev/null | wc -l)"
    ISPORTFREE4="$(netstat -tuln | grep :${NEWPORT})"
    ISPORTFREE5="$(lsof -i :${NEWPORT})"
    if [ "${ISPORTFREE1}" -eq 0 -a "${ISPORTFREE3}" -eq 0 -a -z "${ISPORTFREE2}${ISPORTFREE4}${ISPORTFREE5}" ]; then
      _INIT_EMPTY_PORT_CLAIMED="${_INIT_EMPTY_PORT_CLAIMED} ${NEWPORT}"
      if [ -z "${_INIT_EMPTY_PORT_TRAP_SET}" ]; then
        trap '_init_empty_port_cleanup' EXIT
        _INIT_EMPTY_PORT_TRAP_SET=1
      fi
      # Auto-release the claim ~600s later. Sized to comfortably exceed the worst-case caller bind window (SAN/UBASAN/MSAN builds use seq 0 480 = 120s ping-wait in start; 600s = 5x safety margin). Cost is bounded: max in-flight claims <= port-range size (3000 entries). Double-fork detaches so long-lived pickers don't accumulate zombies and the reaper survives if the parent exits before the timer fires.
      ( ( sleep 600; rm -f "${_INIT_EMPTY_PORT_CLAIM_DIR}/${NEWPORT}" ) & ) </dev/null >/dev/null 2>&1
      break
    fi
    # Port is in use by an unrelated process; release the claim and retry.
    rm -f "${_INIT_EMPTY_PORT_CLAIM_DIR}/${NEWPORT}"
  done
}
