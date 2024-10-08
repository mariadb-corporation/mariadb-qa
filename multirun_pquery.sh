#!/bin/bash
# Created by Roel Van de Paar, Percona LLC
# Updated by Roel Van de Paar, MariaDB

RND_DELAY_FUNCTION=0     # If set to 1, insert random delays after starting a new repetition in a thread. This may help to decrease locking issues.
RND_REPLAY_ORDER=0       # If set to 1, the tool will shuffle the input SQL in various ways
REPORT_END_THREAD=0      # If set to 1, report the outcome of ended threads (slows things down considerably)
REPORT_THREADS=0         # If set to 1, report the outcome of ongoing threads (slows things down considerably)

if [ "" == "$7" ]; then
  echo "This script expects exactly 7 options. Execute as follows:"
  echo "$ multirun_pquery.sh threads repetitions input.sql pquery_binary socket basedir pquery_threads"
  echo "Where:"
  echo "  threads: is the number of simultaneously started pquery client threads"
  echo "  repetitions: the number of repetitions *per* individual thread"
  echo "  input.sql: is the input SQL file executed by the clients"
  echo "  pquery_binary: is the location of the pquery binary"
  echo "  socket: is the location of the socket file for connection to mysqld"
  echo "  basedir: the base directory of the MD/MS/PS build being used"
  echo "  pquery_threads: how many client threads pquery should instantiate (per pquery client)"
  echo "Example:"
  echo "$ multirun_pquery.sh 1 5 bug.sql ${HOME}/mariadb-qa/pquery/pquery2-md /test/MD201120-mariadb-10.6.0-linux-x86_64-opt/socket.sock /test/MD201120-mariadb-10.6.0-linux-x86_64-opt/ 10"
  echo "Cautionary Notes:"
  echo "  - Script does not check *yet* if options passed are all valid/present, make sure you get it right"
  echo "  - If root user uses a password, a script hack is suggested *ftm*"
  echo "  - This script may cause very significant server load if used with many threads"
  echo "  - This script expects write permissions in the current directory ($PWD)"
  echo "  - Output files for each thread are written as: multirun.<thread number>.<repetition number> (e.g. multirun.1.1 etc.)"
  exit 1
fi

if [ ! -d $6/lib ]; then echo "Assert: $6/lib does not exist?"; exit 1; fi

RANDOM=$(date +%s%N | cut -b10-19 | sed 's|^[0]\+||')
EXE_TODO=$[$1 * $7 * $2]
EXE_DONE=0
echo "===== Total planned executions:"
echo "$1 pquery Thread(s) * $7 Threads per pquery * $2 Repetitions = $EXE_TODO Executions"

echo -e "\n===== Reseting all threads statuses"
for (( thread=1; thread<=$1; thread++ )); do
  PID[$thread]=0
  RPT_LEFT[$thread]=$2
done
echo "Done!"

TEMPSQLFILE="$(mktemp | tr -d '\n')"

echo -e "\n===== Verifying server is up & running"
rm -f ${TEMPSQLFILE}
echo 'SELECT 1;' > ${TEMPSQLFILE}
CHK_CMD="$4 --database=test --infile=${TEMPSQLFILE} --threads=1 --no-shuffle --user=root --socket=$5"
CHK_OUT="$(eval ${CHK_CMD} 2>&1 | grep 'Exit status' | tail -n1)"
ERR_CODE="$(echo "${CHK_OUT}" | sed 's|.*:[ \t]*||')"
rm -f ${TEMPSQLFILE}
if [ "${ERR_CODE}" != "0" ]; then
  echo "Server not reachable! Check settings. Error: ${CHK_OUT}"
  echo "Terminating!"
  exit 1
else
  echo "Done!"
fi

echo -e "\n===== Starting pquery process(es)"
if [ ${REPORT_THREADS} -eq 0 ]; then
  echo 'Running...'
fi
for (( ; ; )); do
  if [ ! -r ${TEMPSQLFILE} ]; then echo 'SELECT 1;' > ${TEMPSQLFILE}; fi
  # Loop through threads
  for (( thread=1; thread<=$1; thread++ )); do
    # Check if thread is busy
    if [ ${PID[$thread]} -eq 0 ]; then
      # Check if repeats are exhaused
      if [ ${RPT_LEFT[$thread]} -ne 0 ]; then
        REPETITION=$[ $2 - ${RPT_LEFT[$thread]} + 1 ]
        if [ ${REPORT_THREADS} -eq 1 ]; then
          echo -n "Thread: $thread | Repetition: ${REPETITION}/$2 | "
        fi
        export LD_LIBRARY_PATH=$6/lib
        # Note that there are two levels of threading: the number of pquery clients started (as set by $1), and the number of pquery threads initiated/used by each of those pquery clients (as set by $7).
        if [ $RND_REPLAY_ORDER -eq 1 ]; then
          CLI_CMD="$4 --database=test --infile=$3 --threads=$7 --user=root --socket=$5 >/dev/null 2>&1"
        else
          CLI_CMD="$4 --database=test --infile=$3 --threads=$7 --no-shuffle --user=root --socket=$5 >/dev/null 2>&1"
        fi
        # In background; a must to ensure threads run concurrently
        # For testing: CLI_CMD="sleep $[ $RANDOM % 10 ]"
        eval "${CLI_CMD} &"  # With thanks, https://stackoverflow.com/questions/4339756/
        PID[$thread]=$!
        if [ ${REPORT_THREADS} -eq 1 ]; then
          echo "Started! [PID: ${PID[$thread]}]"
        fi
        RPT_LEFT[$thread]=$[ ${RPT_LEFT[$thread]} - 1 ]
        # Check to see if server is still alive - provided mysqladmin can be found in same location as mysql binary
        CHK_CMD="$4 --database=test --infile=${TEMPSQLFILE} --threads=1 --no-shuffle --user=root --socket=$5"
        CHK_OUT="eval ${CHK_CMD} 2>&1 | grep 'Exit status' | tail -n1 | sed 's|.*:[ \t]*||"
        if [ "${CHK_OUT}" == "256" ]; then
          echo "Server no longer reachable! Check for crash etc. (Tip: run: ~/tt and/or check ./log/master.err)"
          echo "Execution rounds done (gives an indication as to level of reproducibility): $[ ${EXE_DONE} + 1]"
          echo "Terminating!"
          exit 1
        fi
        # Introduce random delay if set to do so
        if [ $RND_DELAY_FUNCTION -eq 1 -a $thread -ne $1 ]; then
          RND_DELAY=$[ $RANDOM % 10 ]
          echo -n "   Random delay: $RND_DELAY seconds | "
          eval "sleep $RND_DELAY"
          echo "Done!"
        fi
      fi
    else
      if [ -z "`ps -p ${PID[$thread]} | awk '{print $1}' | grep -v 'PID'`" ]; then
        if [ ${REPORT_END_THREAD} -eq 1 ]; then
          echo -e "\t\t\t\t\t\t   Thread: $thread | Repetition: $[ $2 - ${RPT_LEFT[$thread]} ]/$2 | [PID: ${PID[$thread]}] Ended!"
        fi
        EXE_DONE=$[ $EXE_DONE + 1 ]
        PID[$thread]=0
      fi
    fi
  done
  if [ $EXE_DONE -ge $EXE_TODO ]; then break; fi
done
