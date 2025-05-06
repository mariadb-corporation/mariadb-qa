#!/bin/bash
# Created by Ramesh Sivaraman, Percona LLC
# Updated by Roel Van de Paar, Percona LLC
# Updated by Roel Van de Paar, MariaDB
set +H

# Start this script from within the base directory which contains ./bin/mysqld[-debug]

# User configurable variables
WORKDIR="/dev/shm"                     ## Working directory ("/dev/shm" preferred)
SQLFILE="./in.sql"                     ## SQL Input file
MYEXTRA="${*}"                         ## Accept mysqld options from the command line
#SERVER_THREADS=(2 10 25 50 75 100 200 250)  ## Number of server threads (x mysqld's). This is a sequence: (10 20) means: first 10, then 20 server if no crash was observed
SERVER_THREADS=(30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 3 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30)  ## Number of server threads (x mysqld's). This is a sequence: (10 20) means: first 10, then 20 server if no crash was observed
#CLIENT_THREADS=200                    ## Number of client threads (y threads) which will execute the SQLFILE input file against each mysqld
CLIENT_THREADS=1                       ## Number of client threads (y threads) which will execute the SQLFILE input file against each mysqld
#AFTER_SHUTDOWN_DELAY=35               ## Wait this many seconds for mysqld to shutdown properly. If it does not shutdown within the allotted time, an error shows
AFTER_SHUTDOWN_DELAY=3
IGNORE_SHUTDOWN_WIHOUT_CRASH=1         ## When the testcase contains SHUTDOWN, setting this option to 1 prevents any shutdowns without crash from being considered as an event to halt script execution. i.e. a crash is required, not just a shutdown for the script to stop/finish
TEXT=""                                ## Search for a specific string on crash/shutdown. Do NOT use unique bug ID's here (not implemented yet), only a TEXT to look for in the error log (for example, a single mangled frame or a partial error message)

# Scripted variables
if [ "${1}" == "TEXT" ]; then
  if [ ! -z "${2}" ]; then
    TEXT="${2}"
    echo "Looking for TEXT '${TEXT}' in the error log, and ignoring all events (shutdows, other crashes, etc.) UNTIL this TEXT string is found"
    if [ ! -z "${3}" ]; then
      MYEXTRA="$(echo "${*}" | sed "s|^[ ]*TEXT[ ]*||;s|^[ ]*${TEXT}[ ]*||")"
    else
      MYEXTRA=""
    fi
  else
    echo "Assert: if first variable is passed as TEXT (as done), second variable should be the text to look for, and the third variable and subsequent MYEXTRA options, if any. The second variable was empty in this case."
    exit 1
  fi
fi
echo "Using MYEXTRA options: ${MYEXTRA}"

# Internal variables
MYUSER=$(whoami)
MYPORT=$[20000 + $RANDOM % 9999 + 1]
DATADIR=`date +'%s'`

# Reference functions
echoit(){ echo "[$(date +'%T')] $1"; }
echoito(){ echo -ne "[$(date +'%T')] $1\r"; }  # Used for on-screen updating of text

if [ ! -r ${SQL_FILE} ]; then
  echoit "Assert: this script tried to read ${SQL_FILE} (as specified in the  \"User configurable variables\" at the top of/inside the script), but it could not."
  echoit "Please check if the file exists, if this script can read it, etc."
  exit 1
fi

if [ ! -d ${WORKDIR} ]; then
  echoit "Assert: {$WORKDIR} (as specified in the  \"User configurable variables\" at the top of/inside the script) does not exist!"
  exit 1
else  # Workdir setup
  WORKDIR="${WORKDIR}/$DATADIR"
  mkdir -p ${WORKDIR}
  if [ ! -d ${WORKDIR} ]; then
    echoit "Assert: we tried to create ${WORKDIR}, but it does not exist after the creation attempt! Has this script write privileges there?"
    exit 1
  fi
fi

if [ -r ${PWD}/bin/mysqld ]; then
  BIN=${PWD}/bin/mysqld
else
  # Check if this is a debug build by checking if debug string is present in dirname
  if [[ ${PWD} = *debug* ]]; then
    if [ -r ${PWD}/bin/mysqld-debug ]; then
      BIN=${PWD}/bin/mysqld-debug
    else
      echoit "Assert: there is no (script readable) mysqld binary at ${PWD}/bin/mysqld[-debug] ?"
      exit 1
    fi
  else
    echoit "Assert: there is no (script readable) mysqld binary at ${PWD}/bin/mysqld ?"
    exit 1
  fi
fi

echoit "Script work directory : ${WORKDIR}"
# Get version specific options
if [ ! -r ./BUILD_CMD_CMAKE ]; then
  echo "./BUILD_CMD_CMAKE not found! Are you usre you are in a BASEDIR directory?"
  echo "If you're sure (and for example ./bin/mysqld exists), then do this:"
  echo "touch ./BUILD_CMD_CMAKE   # And restart the script"
  exit 1
else
  BASEDIR="${PWD}"
fi
BIN=
if [ -r ${PWD}/bin/mysqld-debug ]; then BIN="${PWD}/bin/mysqld-debug"; fi  # Needs to come first so it's overwritten in next line if both exist
if [ -r ${PWD}/bin/mysqld ]; then BIN="${PWD}/bin/mysqld"; fi
if [ "${BIN}" == "" ]; then echo "Assert: no mysqld or mysqld-debug binary was found!"; fi
MID=
if [ -r ${BASEDIR}/scripts/mariadb-install-db ]; then MID="${BASEDIR}/scripts/mariadb-install-db"; fi
if [ -r ${BASEDIR}/scripts/mysql_install_db ]; then MID="${BASEDIR}/scripts/mysql_install_db"; fi
if [ -r ${BASEDIR}/bin/mysql_install_db ]; then MID="${BASEDIR}/bin/mysql_install_db"; fi
START_OPT="--core-file"           # Compatible with 5.6,5.7,8.0
INIT_OPT="--no-defaults --initialize-insecure ${MYINIT}"  # Compatible with     5.7,8.0 (mysqld init)
INIT_TOOL="${BIN}"                # Compatible with     5.7,8.0 (mysqld init), changed to MID later if version <=5.6
VERSION_INFO=$(${BIN} --version | grep -E --binary-files=text -oe '[589]\.[0-9]' | head -n1)
VERSION_INFO_2=$(${BIN} --version | grep --binary-files=text -i 'MariaDB' | grep -oe '1[0-5]\.[0-9][0-9]*' | head -n1)
if [[ "${VERSION_INFO_2}" =~ ^10.[1-3]$ ]]; then
  VERSION_INFO="5.1"
  INIT_TOOL="${PWD}/scripts/mysql_install_db"
  INIT_OPT="--no-defaults --force"
  START_OPT="--core"
elif [[ "${VERSION_INFO_2}" =~ ^1[0-5].[0-9][0-9]* ]]; then
  VERSION_INFO="5.6"
  INIT_TOOL="${BASEDIR}/scripts/mariadb-install-db"
  INIT_OPT="--no-defaults --force --auth-root-authentication-method=normal ${MYINIT}"
  START_OPT="--core-file --core"
elif [ "${VERSION_INFO}" == "5.1" -o "${VERSION_INFO}" == "5.5" -o "${VERSION_INFO}" == "5.6" ]; then
  if [ "${MID}" == "" ]; then
    echo "Assert: Version was detected as ${VERSION_INFO}, yet ./scripts/mysql_install_db nor ./bin/mysql_install_db is present!"
    exit 1
  fi
  INIT_TOOL="${MID}"
  INIT_OPT="--no-defaults --force ${MYINIT}"
  START_OPT="--core"
elif [ "${VERSION_INFO}" != "5.7" -a "${VERSION_INFO}" != "8.0" ]; then
  echo "WARNING: mysqld (${BIN}) version detection failed. This is likely caused by using this script with a non-supported distribution or version of mysqld. Please expand this script to handle (which shoud be easy to do). Even so, the scipt will now try and continue as-is, but this may fail."
fi

checkstatus(){
  CONTINUE=0
  if [ "${IGNORE_SHUTDOWN_WIHOUT_CRASH}" -eq 1 ]; then
    echoit "[!] Server shutdown found, however as IGNORE_SHUTDOWN_WIHOUT_CRASH=1 the script will continue..."
    CONTINUE=1
  else
    if [ ! -z "${TEXT}" ]; then
      if grep -qi "${TEXT}" ${WORKDIR}/${j}_error.log.out; then
        echoit "[!] Server crash/shutdown found with correct TEXT ("${TEXT}") in the error log at ${WORKDIR}/${j}_error.log.out. Leaving state as-is and terminating. Consider using mariadb-qa/kill_all_procs.sh to cleanup after your research is done."
        exit 1
      else
        echoit "[!] Server crash/shutdown found, however not with the correct TEXT ("${TEXT}") in the error log. Continuing..."
        CONTINUE=1
      fi
    else
      echoit "[!] Server crash/shutdown found: Check ${WORKDIR}/${j}_error.log.out for more info. Leaving state as-is and terminating. Consider using mariadb-qa/kill_all_procs.sh to cleanup after your research is done."
      ps -ef | grep -v grep | grep "$(echo "${WORKDIR}" | sed 's|/dev/shm/||')" | awk '{print $2}' | xargs -I{} kill -9 {}
      exit 1
    fi
  fi
}

CONTINUE=0
# Run SQL file from reducer<trial>.sh
for i in ${SERVER_THREADS[@]};do
  # Start multiple mysqld service
  SERVER_COUNT=0
  MYSQLD=()
  for j in `seq 1 ${i}`;do
    SERVER_COUNT=$[ ${SERVER_COUNT} + 1 ];
    echoito "Starting mysqld #${SERVER_COUNT}..."
    MYPORT=$[ ${MYPORT} + 1 ]
    mkdir ${WORKDIR}/${j} 2>/dev/null
    $INIT_TOOL --no-defaults ${INIT_OPT} --basedir=${PWD} --datadir=${WORKDIR}/${j} ${MYEXTRA} > ${WORKDIR}/${j}_mysql_install_db.out 2>&1
    CMD="bash -c \"set -o pipefail; ${BIN} ${MYEXTRA} ${START_OPT} --basedir=${PWD} --datadir=${WORKDIR}/${j} --port=${MYPORT} --pid-file=${WORKDIR}/${j}_pid.pid --log-error=${WORKDIR}/${j}_error.log.out --socket=${WORKDIR}/${j}_socket.sock --user=${MYUSER}\""
    eval $CMD > ${WORKDIR}/${j}_mysqld.out 2>&1 &
    PIDV="$!"
    MYSQLD+=(${PIDV})
    echoit "Started mysqld #${SERVER_COUNT}/${i} with PID ${MYSQLD[j-1]}"
  done
  for j in `seq 1 ${i}`;do
    x=0
    ${PWD}/bin/mysqladmin -uroot -S${WORKDIR}/${j}_socket.sock ping > /dev/null 2>&1
    CHECK=$?
    while [[ $CHECK != 0 ]]; do
      ${PWD}/bin/mysqladmin -uroot -S${WORKDIR}/${j}_socket.sock ping > /dev/null 2>&1
      CHECK=$?
      sleep 1
      if [ $x == 40 ];then
        echoit "[ERROR] Server not started: Check ${WORKDIR}/${j}_mysql_install_db.out, ${WORKDIR}/${j}_error.log.out and ${WORKDIR}/${j}_mysqld.out for more info"
        ps -ef | grep -v grep | grep "$(echo "${WORKDIR}" | sed 's|/dev/shm/||')" | awk '{print $2}' | xargs -I{} kill -9 {}
        exit 1;
      fi
      x=$[ $x+1 ]
    done
  done
  # Start multiple mysql clients to test the SQL
  MYSQLC=()
  for j in `seq 1 ${i}`;do
    echoit "Starting ${CLIENT_THREADS} client threads against mysqld #${j}..."
    ## The following line is for pquery testing (and remark entire for_do_done loop)
    #$(cd `dirname $0` && pwd)/pquery/pquery --infile=${TRIAL}.out_out --database=test --threads=${CLIENT_THREADS} --user=root --socket=${WORKDIR}/${j}_socket.sock > ${WORKDIR}/${j}_pquery.out 2>&1 &
    for (( thread=1; thread<=${CLIENT_THREADS}; thread++ )); do
      ${PWD}/bin/mysql -uroot --socket=${WORKDIR}/${j}_socket.sock -f < ${SQLFILE} > ${WORKDIR}/${j}_client-$thread.out 2>&1 &
      PID="$!"
      MYSQLC+=($PID)
    done
    # Check if mysqld process crashed immediately
    CONTINUE=0
    if ! ${PWD}/bin/mysqladmin -uroot -S${WORKDIR}/${j}_socket.sock ping > /dev/null 2>&1; then
      checkstatus
      if [ "${CONTINUE}" == "1" ]; then continue; fi
    fi
  done
  sleep 1  # Avoids last client not having started yet
  # Check if mysql client finished
  for k in "${MYSQLC[@]}"; do
    while [[ ( -d /proc/$k ) && ( -z "$(grep zombie /proc/$k/status 2>/dev/null)" ) ]]; do  # Without the 2>/dev/null it sometimes produced 'grep: /proc/595146/status: No such file or directory'
      # Check mysqld processes are still alive while waiting for client processes to finish
      for j in `seq 1 ${i}`;do
        if ! ${PWD}/bin/mysqladmin -uroot -S${WORKDIR}/${j}_socket.sock ping > /dev/null 2>&1; then
          checkstatus
          if [ "${CONTINUE}" == "1" ]; then continue; fi
        fi
      done
    done
  done
  # Check mysqld processes are still alive after client processes are done
  for j in `seq 1 ${i}`;do
    if ! ${PWD}/bin/mysqladmin -uroot -S${WORKDIR}/${j}_socket.sock ping > /dev/null 2>&1; then
      checkstatus
      if [ "${CONTINUE}" == "1" ]; then continue; fi
    fi
  done
  # Shutdown mysqld processes
  for j in `seq 1 ${i}`;do
    echoit "Shutting down mysqld #${j}..."
    timeout --signal=9 ${AFTER_SHUTDOWN_DELAY}s ${PWD}/bin/mysqladmin -uroot -S${WORKDIR}/${j}_socket.sock shutdown >/dev/null 2>&1
    if [ $? -eq 137 ]; then  # Timeout was activated after ${AFTER_SHUTDOWN_DELAY} seconds, highly likely indicating a hang
      echoit "[!] Potential server hang found: mysqld #${j} (${WORKDIR}) has not shutdown in ${AFTER_SHUTDOWN_DELAY} seconds. Check gdb --pid=${MYSQLD[j-1]}. Leaving state as-is and terminating. Consider using mariadb-qa/kill_all_procs.sh to cleanup after your research is done."
      exit 1
    fi
  done
  # Mandarory pause to allow core file write
  sleep 3
  sync
  # Check for shutdown issues
  echoit "Checking outcomes..."
  for j in `seq 1 ${i}`;do
    # Check for shutdown failure (mysqld still responding to mysqladmin pings)
    PING=
    timeout --signal=9 10s ${PWD}/bin/mysqladmin -uroot -S${WORKDIR}/${j}_socket.sock ping > /dev/null 2>&1
${PWD}/bin/mysqladmin -uroot -S${WORKDIR}/${j}_socket.sock ping 2>/dev/null 1>&2
    PING=$?
    if [ $PING -eq 137 ]; then
      echoit "[!] Potential server hang found: a mysqladmin ping to mysqld #${j} (${WORKDIR}) did not complete in 10 sconds. Check gdb --pid=${MYSQLD[j-1]} for more info. Leaving state as-is and terminating. Consider using mariadb-qa/kill_all_procs.sh to cleanup after your research is done."
      exit 1
    elif [ $PING -eq 0 ]; then
      echoit "[!] Server hang found: mysqld #${j} (${WORKDIR}) has not shutdown in 60 seconds and is still responding to mysqladmin ping. Check gdb --pid=${MYSQLD[j-1]} for more info. Leaving state as-is and terminating. Consider using mariadb-qa/kill_all_procs.sh to cleanup after your research is done."
      exit 1
    elif [ $PING -ne 1 ]; then  # PING -eq 1 is what we are looking for, i.e. server no longer reachable. Then check for core dumps below.
      echoit "[!] Unknown issue detected: a mysqladmin ping to mysqld #${j} (${WORKDIR}) returned exit status $PING, which is unkwnon to this script. Please research this code $PING and the current status of mysqld with gdb --pid=${MYSQLD[j-1]} for more info, then please update this script so it can handle this state. Leaving state as-is and terminating. Consider using mariadb-qa/kill_all_procs.sh to cleanup after your research is done."
      exit 1
    fi
    # Check for core dump
    if [ $(ls ${WORKDIR}/${j}/*core* 2>/dev/null | grep -vi "no such file or directory" | wc -l) -gt 0 ]; then
      echoit "[!] Server crash found: mysqld #${j} has generated a core dump. Check ${WORKDIR}/${j}_error.log.out and $(ls -l ${WORKDIR}/${j}/*core* | tr '\n' ' ') for more info. Leaving state as-is and terminating. Consider using mariadb-qa/kill_all_procs.sh to cleanup after your research is done."
      exit 1
    fi
  done
  kill -9 `printf '%s ' "${MYSQLD[@]}"` 2>/dev/null  # For safety, though processes should be gone. Redirected stderr to /dev/null as otherwise 'multirun_mysqld.sh: line ___: kill: (_____) - No such process' errors would show.
  # Roundup by reporting that nothing was found for this run. (If something was found, the script would have instead terminated already, ref exit 1 above after/if 'Check for core dump' was found, and this messsage would thus never show.)
  #if [ ${SERVER_THREADS[@]:(-1)} -ne ${i} ] ; then
    if [ ! -z "${TEXT}" ]; then
      echoit "Did not find the correct (TEXT based) server crash with ${i} mysqld processes. Restarting specific TEXT crash testing with next set of mysqld processes."
    else
      echoit "Did not find server crash with ${i} mysqld processes. Restarting crash testing with next set of mysqld processes."
    fi
    rm -Rf ${WORKDIR}/*
    ps -ef | grep -v grep | grep "$(echo "${WORKDIR}" | sed 's|/dev/shm/||')" | awk '{print $2}' | xargs -I{} kill -9 {}
  #fi
done
echoit "Complete, no issues found."
