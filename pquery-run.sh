#!/bin/bash
# Created by Roel Van de Paar, Percona LLC
# Updated by Ramesh Sivaraman, Percona LLC
# Updated by Mohit Joshi, Percona LLC
# Updated by Roel Van de Paar, MariaDB

# ========================================= User configurable variables
# Note: if an option is passed to this script, it will use that option as the configuration file instead, for example ./pquery-run.sh pquery-run-MD105.conf
CONFIGURATION_FILE=pquery-run.conf # Do not use any path specifiers, the .conf file should be in the same path as pquery-run.sh

# ========================================= Improvement ideas
# * SAVE_TRIALS_WITH_CORE_OR_VALGRIND_ONLY=0 (These likely include some of the 'SIGKILL' issues - no core but terminated)
# * SQL hashing s/t2/t1/, hex values "0x"
# * Full MTR grammar on one-liners
# * Interleave all statements with another that is likely to cause issues, for example "USE mysql". This is already done regularly with feature testing through SQL interleaving, but it could be done per statement. For example, every second line a SELECT, next SQL file every second line an UPDATE, next SQL file every second line an ALTER etc. then use all (do not combine; too large input) files either randomly or sequentially. And instead of just SELECT, or UPDATE, or ALTER etc. use sql-interleaving to make a variety of 9 per statement.
# * It would be possible to output all new bugs to a flat text file, so that when the new bug detection is operating, it will check not only known_bugs.strings but also this new flat text file, and if a bug is seen already, it could just delete the trial. This will only leave one trial in place for testcase reduction, but over time and over different runs this should be quite fine - especially as showstopper like bugs will be all over the runs and hence will reproduce every new run with ease. For the moment, pquery-eliminate-dups.sh reduces the max number to 3, so that is quite fine also.

# ========================================= MAIN CODE

# MariaDB specific variables
DISABLE_TOKUDB_AND_JEMALLOC=1

# Internal variables: DO NOT CHANGE!
RANDOM=$(date +%s%N | cut -b10-19)
RANDOMD=$(echo $RANDOM$RANDOM$RANDOM | sed 's/..\(......\).*/\1/')
SCRIPT_AND_PATH=$(readlink -f $0)
SCRIPT=$(echo ${SCRIPT_AND_PATH} | sed 's|.*/||')
SCRIPT_PWD=$(cd "$(dirname $0)" && pwd)
WORKDIRACTIVE=0
SAVED=0
ALREADY_KNOWN=0
TRIAL=0
MYSQLD_START_TIMEOUT=60
TIMEOUT_REACHED=0
PQUERY3=0
NEWBUGS=0
INFILE_SHUFFLED=
PRE_SHUFFLE_TRIAL_ROUND=0  # Resets to 0 each time PRE_SHUFFLE_TRIALS_PER_SHUFFLE is reached

# Set SAN options
# https://github.com/google/sanitizers/wiki/SanitizerCommonFlags
# https://github.com/google/sanitizers/wiki/AddressSanitizerFlags
# https://clang.llvm.org/docs/UndefinedBehaviorSanitizer.html
# https://github.com/google/sanitizers/wiki/AddressSanitizerLeakSanitizer (LSAN is enabled by default except on OS X)
# detect_invalid_pointer_pairs changed from 1 to 3 at start of 2021 (effectively used since)
export ASAN_OPTIONS=quarantine_size_mb=512:atexit=1:detect_invalid_pointer_pairs=3:dump_instruction_bytes=1:abort_on_error=1
# check_initialization_order=1 cannot be used due to https://jira.mariadb.org/browse/MDEV-24546 TODO
# detect_stack_use_after_return=1 will likely require thread_stack increase (check error log after ./all) TODO
#export ASAN_OPTIONS=quarantine_size_mb=512:atexit=1:detect_invalid_pointer_pairs=3:dump_instruction_bytes=1:check_initialization_order=1:detect_stack_use_after_return=1:abort_on_error=1
export UBSAN_OPTIONS=print_stacktrace=1
export TSAN_OPTIONS=suppress_equal_stacks=1:suppress_equal_addresses=1:history_size=7:verbosity=1

# Print/Output function
echoit() {
  if [ "${ELIMINATE_KNOWN_BUGS}" == "1" ]; then
    echo "[$(date +'%T')] [$SAVED SAVED] [${ALREADY_KNOWN} DUPS] $1"
    if [ ${WORKDIRACTIVE} -eq 1 ]; then echo "[$(date +'%T')] [$SAVED SAVED] [${ALREADY_KNOWN} DUPS] $1" >> /${WORKDIR}/pquery-run.log; fi
  else
    echo "[$(date +'%T')] [$SAVED] $1"
    if [ ${WORKDIRACTIVE} -eq 1 ]; then echo "[$(date +'%T')] [$SAVED SAVED] $1" >> /${WORKDIR}/pquery-run.log; fi
  fi
}

# Read configuration
if [ "$1" != "" ]; then CONFIGURATION_FILE=$1; fi
if [ ! -r ${SCRIPT_PWD}/${CONFIGURATION_FILE} ]; then
  echo "Assert: the confiruation file ${SCRIPT_PWD}/${CONFIGURATION_FILE} cannot be read!"
  exit 1
fi
source ${SCRIPT_PWD}/$CONFIGURATION_FILE
echo ${WORKDIR} > /tmp/gomd_helper # gomd helper
PQUERY_TOOL_NAME=$(basename ${PQUERY_BIN})
if [ "${SEED}" == "" ]; then SEED=${RANDOMD}; fi
# TODO: research this new code (and how it affects trials, though it seeems backwards compatible; checking for PQUERY3 varialbe happens AFTER all other checks are done (i.e. first core, then other checks, then PQUERY3 check, so should be fine? Though trial-1 is apparently removed; research further))
if [[ ${PQUERY_TOOL_NAME} == "pquery3"* ]]; then PQUERY3=1; fi

# Safety checks: ensure variables are correctly set to avoid rm -Rf issues (if not set correctly, it was likely due to altering internal variables at the top of this file)
if [ "${WORKDIR}" == "/sd[a-z][/]" ]; then
  echo "Assert! \${WORKDIR} == '${WORKDIR}' - is it missing the \$RANDOMD suffix?"
  exit 1
fi
if [ "${RUNDIR}" == "/dev/shm[/]" ]; then
  echo "Assert! \$RUNDIR == '${RUNDIR}' - is it missing the \$RANDOMD suffix?"
  exit 1
fi
if [ "$(echo ${RANDOMD} | sed 's|[0-9]|/|g')" != "//////" ]; then
  echo "Assert! \$RANDOMD == '${RANDOMD}'. This looks incorrect - it should be 6 numbers exactly"
  exit 1
fi
if [ "${SKIPCHECKDIRS}" == "" ]; then # Used in/by pquery-reach.sh TODO: find a better way then hacking to avoid these checks. Check; why do they fail when called from pquery-reach.sh?
  if [ "$(echo ${WORKDIR} | grep -oi "$RANDOMD" | head -n1)" != "${RANDOMD}" ]; then
    echo "Assert! \${WORKDIR} == '${WORKDIR}' - is it missing the \$RANDOMD suffix?"
    exit 1
  fi
  if [ "$(echo ${RUNDIR} | grep -oi "$RANDOMD" | head -n1)" != "${RANDOMD}" ]; then
    echo "Assert! \${WORKDIR} == '${WORKDIR}' - is it missing the \$RANDOMD suffix?"
    exit 1
  fi
fi

# Other safety checks
if [ "$(echo ${PQUERY_BIN} | sed 's|\(^/pquery\)|\1|')" == "/pquery" ]; then
  echo "Assert! \$PQUERY_BIN == '${PQUERY_BIN}' - is it missing the \$SCRIPT_PWD prefix?"
  exit 1
fi
if [ ! -r ${PQUERY_BIN} ]; then
  echo "Assert: ${PQUERY_BIN} specified in the configuration file used (${SCRIPT_PWD}/${CONFIGURATION_FILE}) cannot be found/read"
  exit 1
fi
if [ ! -r ${OPTIONS_INFILE} ]; then
  echo "Assert: ${OPTIONS_INFILE} specified in the configuration file used (${SCRIPT_PWD}/${CONFIGURATION_FILE}) cannot be found/read"
  exit 1
fi
if [ "${PRELOAD}" == "1" ]; then
  if [ ${THREADS} -ne 1 ]; then
    echo "Assert: PRELOAD is enabled (1), and THREADS!=1 (${THREADS}). This setup is not supported (yet) as this script would not be able to prepend the preload SQL to any particular thread's SQL trace (which one to pick?). It may be possible to do a rather large framework patch where PRELOAD SQL is built into reducer.sh etc. (for single threaded runs, it is simply prepended to the SQL trace), so that it is preloaded in all tools, especially reduction. Feel free to implement this if you like."
    exit 1
  elif [ "${QUERY_CORRECTNESS_TESTING}" == "1" ]; then
    echo "Assert: PRELOAD is enabled (1), and QUERY_CORRECTNESS_TESTING is enabled (1). Pre-loading (pre-pending) SQL is not supported yet for Query Correctness Testing, feel free to add it!"
    exit 1
  elif [ -z "${PRELOAD_SQL}" ]; then
    echo "Assert: PRELOAD is enabled (1), yet PRELOAD_SQL option has not been set. Please set it to the SQL preload file you would like to use"
    exit 1
  elif [ ! -r "${PRELOAD_SQL}" ]; then
    echo "Assert: PRELOAD is enabled (1), yet the file configured with PRELOAD_SQL (${PRELOAD_SQL}) cannot be read by this script. Please check."
    exit 1
  elif [ "$(wc -l ${PRELOAD_SQL} | sed 's| .*||')" -eq "0" ]; then
    echo "Assert: PRELOAD is enabled (1), yet the file configured with PRELOAD_SQL (${PRELOAD_SQL}) is empty. Please check."
    exit 1
  else
    echo "PRELOAD SQL Active: (${PRELOAD_SQL} will be preloaded for all trials, and prepended to trial SQL traces"
  fi 
else
  echo "PRELOAD SQL enabled: NO"
fi
if [ "${RR_TRACING}" == "1" ]; then
  if [ ! -r /usr/bin/rr ]; then
    echo "Assert: /usr/bin/rr not found!"  # TODO: set to be automatic using whereis
    exit 1
  fi
fi
if [ "${PRE_SHUFFLE_SQL}" == "1" ]; then
  if [ -z "${PRE_SHUFFLE_DIR}" ]; then
    echoit "PRE_SHUFFLE_SQL is turned on, yet PRE_SHUFFLE_DIR is empty"
    exit 1
  fi
  mkdir -p "${PRE_SHUFFLE_DIR}"
  if [ ! -d "${PRE_SHUFFLE_DIR}" ]; then
    echoit "PRE_SHUFFLE_SQL is turned on, yet PRE_SHUFFLE_DIR ('${PRE_SHUFFLE_DIR}') is not an actual directory or could not be created. Double check correctness of directory and that this script can write to the location provided (mkdir -p was attempted, any failure of the same would show above this message)"
    exit 1
  fi
  if [ -z "${PRE_SHUFFLE_SQL_LINES}" ]; then
    echoit "PRE_SHUFFLE_SQL is turned on, yet PRE_SHUFFLE_SQL_LINES is not configured"
    exit 1
  fi
  if [ -z "${PRE_SHUFFLE_TRIALS_PER_SHUFFLE}" ]; then
    echoit "PRE_SHUFFLE_SQL is turned on, yet PRE_SHUFFLE_TRIALS_PER_SHUFFLE is not configured"
    exit 1
  fi
  # TODO: this seems to cause errors: ./pquery-run.sh: line 126: 324998: No such file or directory
  if [ ${PRE_SHUFFLE_SQL_LINES} < $[ $[ $[ ${PQUERY_RUN_TIMEOUT} / 15 ] * 25000 * ${PRE_SHUFFLE_TRIALS_PER_SHUFFLE} ] -2 ] ]; then
    echoit "Warning: PRE_SHUFFLE_SQL_LINES (${PRE_SHUFFLE_SQL_LINES}) is set to less than the minimum recommended 25k queries per 15 seconds times the number of PRE_SHUFFLE_TRIALS_PER_SHUFFLE (${PRE_SHUFFLE_TRIALS_PER_SHUFFLE}) trials. You may want to increase this. See the formula here or in pquery-run.conf"
    sleep 10
  fi
fi

# Nr of MDG nodes 1-n
if [ -z "${NR_OF_NODES}" ] ; then
  NR_OF_NODES=3
fi

# Try and raise ulimit for user processes (see setup_server.sh for how to set correct soft/hard nproc settings in limits.conf)
#ulimit -u 7000

# Check input file (when generator is not used)
if [ ${USE_GENERATOR_INSTEAD_OF_INFILE} -ne 1 ] && [ ! -r ${INFILE} ]; then
  echo "Assert! \$INFILE (${INFILE}) cannot be read? Check file existence and privileges!"
  exit 1
fi

#Format version string (thanks to wsrep_sst_xtrabackup-v2)
normalize_version() {
  local major=0
  local minor=0
  local patch=0

  # Only parses purely numeric version numbers, 1.2.3
  # Everything after the first three values are ignored
  if [[ $1 =~ ^([0-9]+)\.([0-9]+)\.?([0-9]*)([\.0-9])*$ ]]; then
    major=${BASH_REMATCH[1]}
    minor=${BASH_REMATCH[2]}
    patch=${BASH_REMATCH[3]}
  fi
  printf %02d%02d%02d $major $minor $patch
}

#Version comparison script (thanks to wsrep_sst_xtrabackup-v2)
check_for_version() {
  local local_version_str="$(normalize_version $1)"
  local required_version_str="$(normalize_version $2)"

  if [[ "$local_version_str" < "$required_version_str" ]]; then
    return 1
  else
    return 0
  fi
}

# Find empty port
init_empty_port(){
  # Choose a random port number in 13-65K range, with triple check to confirm it is free
  NEWPORT=$[ 13001 + ( ${RANDOM} % 52000 ) ]
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
      NEWPORT=$[ 13001 + ( ${RANDOM} % 52000 ) ]  # Try a new port
      DOUBLE_CHECK=0  # Reset the double check
      continue  # Recheck the new port
    fi
  done
}

# Diskspace OOS check function
diskspace() {
  while true; do
    if [ ! -d ${RUNDIR} ]; then mkdir -p ${RUNDIR}; fi
    echo "Diskspace Test" > ${RUNDIR}/diskspace 2>/dev/null
    if [ $? -eq 0 ]; then
      if [ -r ${RUNDIR}/diskspace ]; then
        if [ "$(grep -o 'Diskspace Test' ${RUNDIR}/diskspace 2>/dev/null | head -n1)" == "Diskspace Test" ]; then
          rm -f ${RUNDIR}/diskspace
          break  # We have at least got some diskspace available!
        fi
      fi
    fi
    echoit "Likely out of diskspace on ${RUNDIR}... Pausing 10 minutes"
    sleep 600
    echoit "Slept 10 minutes, resuming pquery-run.sh run..."
  done
}

add_handy_scripts(){
  # Add handy stack script
  if [[ ${MDG} -eq 1 ]]; then
    SAVE_STACK_LOC=${RUNDIR}/${TRIAL}/node${j}
  else
    SAVE_STACK_LOC=${RUNDIR}/${TRIAL}
  fi
  cat "${SCRIPT_PWD}/stack.sh" > ${SAVE_STACK_LOC}/stack && chmod +x ${SAVE_STACK_LOC}/stack
  # Add handy gdb script
  echo "echo 'Handy copy and paste script:'" > ${SAVE_STACK_LOC}/gdb
  echo "echo '  set pagination off'" >> ${SAVE_STACK_LOC}/gdb
  echo "echo '  set print pretty on'" >> ${SAVE_STACK_LOC}/gdb
  echo "echo '  set print frame-arguments all'" >> ${SAVE_STACK_LOC}/gdb
  echo "echo '  thread apply all backtrace full'" >> ${SAVE_STACK_LOC}/gdb
  echo "echo 'OR simple one-thread backtrace instead of all threads (i.e. instead of last line):'" >> ${SAVE_STACK_LOC}/gdb
  echo "echo '  bt'" >> ${SAVE_STACK_LOC}/gdb
  echo "sleep 5" >> ${SAVE_STACK_LOC}/gdb
  if [[ ${MDG} -eq 1 ]]; then
    echo "gdb ../mysqld/mysqld ${GALERA_CORE_LOC}" >> ${SAVE_STACK_LOC}/gdb
  else
    echo "gdb ../mysqld/mysqld ./data/*core*" >> ${SAVE_STACK_LOC}/gdb
  fi
  chmod +x ${SAVE_STACK_LOC}/gdb
  SAVE_STACK_LOC=
}

# Find mysqld binary
if [ -r ${BASEDIR}/bin/mysqld ]; then
  BIN=${BASEDIR}/bin/mysqld
else
  # Check if this is a debug build by checking if debug string is present in dirname
  if [[ ${BASEDIR} = *debug* ]]; then
    if [ -r ${BASEDIR}/bin/mysqld-debug ]; then
      BIN=${BASEDIR}/bin/mysqld-debug
    else
      echo "Assert: there is no (script readable) mysqld binary at ${BASEDIR}/bin/mysqld[-debug] ?"
      exit 1
    fi
  else
    echo "Assert: there is no (script readable) mysqld binary at ${BASEDIR}/bin/mysqld ?"
    exit 1
  fi
fi

#Store MySQL version string
MYSQL_VERSION=$(${BASEDIR}/bin/mysqld --version 2>&1 | grep -oe '[0-9]\.[0-9][\.0-9]*' | head -n1)
# JEMALLOC for PS/TokuDB
if [ "${DISABLE_TOKUDB_AND_JEMALLOC}" -eq 0 ]; then
  PSORNOT1=$(${BIN} --version | grep -oi 'Percona' | sed 's|p|P|' | head -n1)
  PSORNOT2=$(${BIN} --version | grep -oi '5.7.[0-9]\+-[0-9]' | cut -f2 -d'-' | head -n1)
  if [ "${PSORNOT2}" == "" ]; then PSORNOT2=0; fi
  if [ "${SKIP_JEMALLOC_FOR_PS}" != "1" ]; then
    if [ "${PSORNOT1}" == "Percona" ] || [ ${PSORNOT2} -ge 1 ]; then
      if [ -r $(find /usr/*lib*/ -name libjemalloc.so.1 | head -n1) ]; then
        export LD_PRELOAD=$(find /usr/*lib*/ -name libjemalloc.so.1 | head -n1)
      else
        echo "Assert! Binary (${BIN} reported itself as Percona Server, yet jemalloc was not found, please install it!"
        echoit "For Centos7 you can do this by:  sudo yum -y install epel-release; sudo yum -y install jemalloc;"
        echoit "For Ubuntu you can do this by: sudo apt-get install libjemalloc-dev;"
        exit 1
      fi
    fi
  else
    if [ "${PSORNOT1}" == "Percona" ] || [ ${PSORNOT2} -ge 1 ]; then
      echoit "*** IMPORTANT WARNING ***: SKIP_JEMALLOC_FOR_PS was set to 1, and thus JEMALLOC will not be LD_PRELOAD'ed. However, the mysqld binary (${BIN}) reports itself as Percona Server. If you are going to test TokuDB, JEMALLOC should be LD_PRELOAD'ed. If not testing TokuDB, then this warning can be safely ignored."
    fi
  fi
fi

#Sanity check for PXB Crash testing run
if [[ ${PXB_CRASH_RUN} -eq 1 ]]; then
  echoit "MODE: Percona Xtrabackup crash test run"
  if [[ ! -d ${PXB_BASEDIR} ]]; then
    echo "Assert: $PXB_BASEDIR does not exist. Terminating!"
    exit 1
  fi
fi

# Automatic variable adjustments
if [ "$(whoami)" == "root" ]; then MYEXTRA="--user=root ${MYEXTRA}"; fi
if [[ ${MDG_CLUSTER_RUN} -eq 1 && ${MDG} -eq 0 ]]; then
  echoit "As MDG_CLUSTER_RUN=1, this script is auto-assuming this is a MDG run and will set MDG=1"
  MDG=1
fi
if [[ ${GRP_RPL_CLUSTER_RUN} -eq 1 && ${GRP_RPL} -eq 0 ]]; then
  echoit "As GRP_RPL_CLUSTER_RUN=1, this script is auto-assuming this is a Group Replication run and will set GRP_RPL=1"
  GRP_RPL=1
fi
if [ "${MDG_CLUSTER_RUN}" == "1" ]; then
  if [ ${QUERIES_PER_THREAD} -lt 2147483647 ]; then # Starting up a cluster takes more time, so don't rotate too quickly
    echoit "Note: As this is a MDG_CLUSTER_RUN=1 run, and QUERIES_PER_THREAD was set to only ${QUERIES_PER_THREAD}, this script is setting the queries per thread to the required minimum of 2147483647 for this run."
    QUERIES_PER_THREAD=2147483647 # Max int
  fi
  if [ ${PQUERY_RUN_TIMEOUT} -lt 60 ]; then # Starting up a cluster takes more time, so don't rotate too quickly
    echoit "Note: As this is a MDG=1 run, and PQUERY_RUN_TIMEOUT was set to only ${PQUERY_RUN_TIMEOUT}, this script is setting the timeout to the required minimum of 120 for this run."
    PQUERY_RUN_TIMEOUT=60
  fi
  ADD_RANDOM_OPTIONS=0
  ADD_RANDOM_TOKUDB_OPTIONS=0
  ADD_RANDOM_ROCKSDB_OPTIONS=0
  GRP_RPL=0
  GRP_RPL_CLUSTER_RUN=0
fi

if [ "${GRP_RPL}" == "1" ]; then
  if [ ${QUERIES_PER_THREAD} -lt 2147483647 ]; then # Starting up a cluster takes more time, so don't rotate too quickly
    echoit "Note: As this is a GRP_RPL=1 run, and QUERIES_PER_THREAD was set to only ${QUERIES_PER_THREAD}, this script is setting the queries per thread to the required minimum of 2147483647 for this run."
    QUERIES_PER_THREAD=2147483647 # Max int
  fi
  if [ ${PQUERY_RUN_TIMEOUT} -lt 120 ]; then # Starting up a cluster takes more time, so don't rotate too quickly
    echoit "Note: As this is a GRP_RPL=1 run, and PQUERY_RUN_TIMEOUT was set to only ${PQUERY_RUN_TIMEOUT}, this script is setting the timeout to the required minimum of 120 for this run."
    PQUERY_RUN_TIMEOUT=120
  fi
  ADD_RANDOM_TOKUDB_OPTIONS=0
  ADD_RANDOM_ROCKSDB_OPTIONS=0
  MDG=0
  MDG_CLUSTER_RUN=0
fi

if [[ ${REPL} -eq 1 ]]; then
  echoit "Note: As this is a Replication testing run, setting the THREADS to 100 and PQUERY_RUN_TIMEOUT to 300 for this run."
  THREADS=100
  PQUERY_RUN_TIMEOUT=300
  CRASH_RECOVERY_TESTING=1
fi

if [ ${QUERY_DURATION_TESTING} -eq 1 ]; then echoit "MODE: Query Duration Testing"; fi
if [ ${QUERY_DURATION_TESTING} -ne 1 -a ${QUERY_CORRECTNESS_TESTING} -ne 1 -a ${CRASH_RECOVERY_TESTING} -ne 1 ]; then
  if [ "${VALGRIND_RUN}" == "1" ]; then
    if [ ${THREADS} -eq 1 ]; then
      echoit "MODE: Single threaded Valgrind pquery testing"
    else
      echoit "MODE: Multi threaded Valgrind pquery testing"
    fi
  else
    if [ ${THREADS} -eq 1 ]; then
      echoit "MODE: Single threaded pquery testing"
    else
      echoit "MODE: Multi threaded pquery testing"
    fi
  fi
fi
if [ ${THREADS} -gt 1 ]; then # We may want to drop this to 20 seconds required?
  if [ ${PQUERY_RUN_TIMEOUT} -lt 30 ]; then
    echoit "Note: As this is a multi-threaded run, and PQUERY_RUN_TIMEOUT was set to only ${PQUERY_RUN_TIMEOUT}, this script is setting the timeout to the required minimum of 30 for this run."
    PQUERY_RUN_TIMEOUT=30
  fi
  if [ ${QUERY_DURATION_TESTING} -eq 1 ]; then
    echoit "Note: As this is a QUERY_DURATION_TESTING=1 run, and THREADS was set to ${THREADS}, this script is setting the number of threads to the required setting of 1 thread for this run."
    THREADS=1
  fi
fi
if [ ${CRASH_RECOVERY_TESTING} -eq 1 ]; then
  echoit "MODE: Crash Recovery Testing"
  if [[ ${REPL} -eq 0 ]]; then
    echoit "MODE: Crash Recovery Testing"
    INFILE=$CRASH_RECOVERY_INFILE
  else
    echoit "Enabling crash recovery variable as part of replication testing"
  fi
  if [ ${QUERY_DURATION_TESTING} -eq 1 ]; then
    echoit "CRASH_RECOVERY_TESTING and QUERY_DURATION_TESTING cannot be both active at the same time due to parsing limitations. This is the case. Please disable one of them."
    exit 1
  fi
  if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 ]; then
    echoit "CRASH_RECOVERY_TESTING and QUERY_CORRECTNESS_TESTING cannot be both active at the same time due to parsing limitations. This is the case. Please disable one of them."
    exit 1
  fi
  if [ ${THREADS} -lt 50 ]; then
    echoit "Note: As this is a CRASH_RECOVERY_TESTING=1 run, and THREADS was set to only ${THREADS}, this script is setting the number of threads to the required minimum of 50 for this run."
    THREADS=50
  fi
  if [ ${PQUERY_RUN_TIMEOUT} -lt 30 ]; then
    echoit "Note: As this is a CRASH_RECOVERY_TESTING=1 run, and PQUERY_RUN_TIMEOUT was set to only ${PQUERY_RUN_TIMEOUT}, this script is setting the timeout to the required minimum of 30 for this run."
    PQUERY_RUN_TIMEOUT=30
  fi
fi
if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 ]; then
  echoit "MODE: Query Correctness Testing"
  if [ ${QUERY_DURATION_TESTING} -eq 1 ]; then
    echoit "QUERY_CORRECTNESS_TESTING and QUERY_DURATION_TESTING cannot be both active at the same time due to parsing limitations. This is the case. Please disable one of them."
    exit 1
  fi
  if [ ${THREADS} -ne 1 ]; then
    echoit "Note: As this is a QUERY_CORRECTNESS_TESTING=1 run, and THREADS was set to ${THREADS}, this script is setting the number of threads to the required setting of 1 thread for this run."
    THREADS=1
  fi
fi
if [ ${USE_GENERATOR_INSTEAD_OF_INFILE} -eq 1 -a ${STORE_COPY_OF_INFILE} -eq 1 ]; then
  echoit "Note: as the SQL Generator will be used instead of an input file (and as such there is more then one inputfile), STORE_COPY_OF_INFILE has automatically been set to 0."
  STORE_COPY_OF_INFILE=0
fi
if [ "${VALGRIND_RUN}" == "1" ]; then
  echoit "Note: As this is a VALGRIND_RUN=1 run, this script is increasing MYSQLD_START_TIMEOUT (${MYSQLD_START_TIMEOUT}) by 240 seconds because Valgrind is very slow in starting up mysqld."
  MYSQLD_START_TIMEOUT=$((${MYSQLD_START_TIMEOUT} + 240))
  if [ ${MYSQLD_START_TIMEOUT} -lt 300 ]; then
    echoit "Note: As this is a VALGRIND_RUN=1 run, and MYSQLD_START_TIMEOUT was set to only ${MYSQLD_START_TIMEOUT}), this script is setting the timeout to the required minimum of 300 for this run."
    MYSQLD_START_TIMEOUT=300
  fi
  echoit "Note: As this is a VALGRIND_RUN=1 run, this script is increasing PQUERY_RUN_TIMEOUT (${PQUERY_RUN_TIMEOUT}) by 180 seconds because Valgrind is very slow in processing SQL."
  PQUERY_RUN_TIMEOUT=$((${PQUERY_RUN_TIMEOUT} + 180))
fi

# Trap ctrl-c
trap ctrl-c SIGINT

ctrl-c() {
  echoit "CTRL+C Was pressed. Attempting to terminate running processes..."
  KILL_PIDS1=$(ps -ef | grep "$RANDOMD" | grep -v "grep" | awk '{print $2}' | tr '\n' ' ')
  KILL_PIDS2=
  if [ ${USE_GENERATOR_INSTEAD_OF_INFILE} -eq 1 ]; then
    KILL_PIDS2=$(ps -ef | grep generator | grep -v "grep" | awk '{print $2}' | tr '\n' ' ')
  fi
  KILL_PIDS="${KILL_PIDS1} ${KILL_PIDS2}"
  if [ "${KILL_PIDS}" != "" ]; then
    echoit "Terminating the following PID's: ${KILL_PIDS}"
    kill -9 ${KILL_PIDS} > /dev/null 2>&1
  fi
  if [ -d ${RUNDIR}/${TRIAL}/ ]; then
    echoit "Done. Moving the trial $0 was currently working on to workdir as ${WORKDIR}/${TRIAL}/..."
    mv ${RUNDIR}/${TRIAL}/ ${WORKDIR}/ 2>&1 | tee -a /${WORKDIR}/pquery-run.log
  fi
  if [ $USE_GENERATOR_INSTEAD_OF_INFILE -eq 1 ]; then
    echoit "Attempting to cleanup generator temporary files..."
    rm -f ${SCRIPT_PWD}/generator/generator${RANDOMD}.sh
    rm -f ${SCRIPT_PWD}/generator/out${RANDOMD}*.sql
  fi
  if [ "$PMM" == "1" ]; then
    echoit "Attempting to cleanup PMM client services..."
    sudo pmm-admin remove --all > /dev/null
  fi
  echoit "Attempting to cleanup the pquery rundir ${RUNDIR}..."
  rm -Rf ${RUNDIR}
  if [ $SAVED -eq 0 -a ${SAVE_SQL} -eq 0 ]; then
    echoit "There were no coredumps saved, and SAVE_SQL=0, so the workdir can be safely deleted. Doing so..."
    WORKDIRACTIVE=0
    rm -Rf ${WORKDIR}
  else
    echoit "The results of this run can be found in the workdir ${WORKDIR}..."
  fi
  echoit "Done. Terminating pquery-run.sh with exit code 2..."
  exit 2
}

savetrial() { # Only call this if you definitely want to save a trial
  if [ "${PRELOAD}" == "1" ]; then
    PQUERY_DEFAULT_FILE=
    if [[ "${MDG_CLUSTER_RUN}" -eq 1 ]]; then
      PQUERY_DEFAULT_FILE="${RUNDIR}/${TRIAL}/node1.md.galera_thread-0.sql"
    else
      PQUERY_DEFAULT_FILE="${RUNDIR}/${TRIAL}/default.node.tld_thread-0.sql"
    fi
    echoit "PRELOAD=1: Prepending SQL trace with executed SQL from ${PRELOAD_SQL}"
    if [ ! -d ${RUNDIR}/${TRIAL}/preload ]; then
      echoit "PRELOAD Error: PRELOAD=1, but ${RUNDIR}/${TRIAL}/preload did not exist in savetrial()"
    elif [ ! -r ${RUNDIR}/${TRIAL}/preload/default.node.tld_thread-0.sql ]; then
      echoit "PRELOAD Error: PRELOAD=1, but ${RUNDIR}/${TRIAL}/preload/default.node.tld_thread-0.sql did not exist in savetrial()"
    else 
      cp ${RUNDIR}/${TRIAL}/preload/default.node.tld_thread-0.sql ${RUNDIR}/${TRIAL}/preload/${TRIAL}.tmp.sql
      if [ ! -r ${RUNDIR}/${TRIAL}/preload/${TRIAL}.tmp.sql ]; then  
        echoit "PRELOAD cp Error: cp ${RUNDIR}/${TRIAL}/preload/default.node.tld_thread-0.sql ${RUNDIR}/${TRIAL}/preload/${TRIAL}.tmp.sql  # FAILED (target does not exist)"
      elif ! diff -q ${RUNDIR}/${TRIAL}/preload/default.node.tld_thread-0.sql ${RUNDIR}/${TRIAL}/preload/${TRIAL}.tmp.sql >/dev/null 2>&1; then
        echoit "PRELOAD cp Error: cp ${RUNDIR}/${TRIAL}/preload/default.node.tld_thread-0.sql ${RUNDIR}/${TRIAL}/preload/${TRIAL}.tmp.sql  # FAILED (files are not indentical)"
      else
        cat ${PQUERY_DEFAULT_FILE} >> ${RUNDIR}/${TRIAL}/preload/${TRIAL}.tmp.sql
        mv ${PQUERY_DEFAULT_FILE} ${RUNDIR}/${TRIAL}/sql_without_preload.sql
        mv ${RUNDIR}/${TRIAL}/preload/${TRIAL}.tmp.sql ${PQUERY_DEFAULT_FILE}
      fi
    fi
  fi
  echoit "Moving rundir from ${RUNDIR}/${TRIAL} to ${WORKDIR}/${TRIAL}"
  mv ${RUNDIR}/${TRIAL}/ ${WORKDIR}/ 2>&1 | tee -a /${WORKDIR}/pquery-run.log
  chmod -R +rX ${WORKDIR}/${TRIAL}/
  if [ "$PMM_CLEAN_TRIAL" == "1" ]; then
    echoit "Removing mysql instance (pq${RANDOMD}-${TRIAL}) from pmm-admin"
    sudo pmm-admin remove mysql pq${RANDOMD}-${TRIAL} > /dev/null
  fi
  SAVED=$(($SAVED + 1))
  PQUERY_DEFAULT_FILE=
}

removetrial() {
  echoit "Removing trial rundir ${RUNDIR}/${TRIAL}"
  if [ "${RUNDIR}" != "" -a "${TRIAL}" != "" -a -d ${RUNDIR}/${TRIAL}/ ]; then # Protection against dangerous rm's
    rm -Rf ${RUNDIR:?}/${TRIAL:?}/
  fi
  if [ "$PMM_CLEAN_TRIAL" == "1" ]; then
    echoit "Removing mysql instance (pq${RANDOMD}-${TRIAL}) from pmm-admin"
    sudo pmm-admin remove mysql pq${RANDOMD}-${TRIAL} > /dev/null
  fi
}

removelasttrial() {
  if [ ${TRIAL} -gt 2 ]; then
    echoit "Removing last successful trial workdir ${WORKDIR}/$((${TRIAL} - 2))"
    if [ "${WORKDIR}" != "" -a "${TRIAL}" != "" -a -d ${WORKDIR}/$((${TRIAL} - 2))/ ]; then
      rm -Rf ${WORKDIR:?}/$((${TRIAL} - 2))/
    fi
    echoit "Removing the ${WORKDIR}/step_$((${TRIAL} - 2)).dll file"
    rm ${WORKDIR}/step_$((${TRIAL} - 2)).dll
  fi
}

savesql() {
  echoit "Copying sql trace(s) from ${RUNDIR}/${TRIAL} to ${WORKDIR}/${TRIAL}"
  diskspace
  mkdir ${WORKDIR}/${TRIAL}
  chmod -R +rX ${WORKDIR}/${TRIAL}/
  cp ${RUNDIR}/${TRIAL}/*.sql ${WORKDIR}/${TRIAL}/
  rm -Rf ${RUNDIR}/${TRIAL}
  sync
  sleep 0.2
  if [ -d ${RUNDIR}/${TRIAL} ]; then
    echoit "Assert: tried to remove ${RUNDIR}/${TRIAL}, but it looks like removal failed. Check what is holding lock? (lsof tool may help)."
    echoit "As this is not necessarily a fatal error (there is likely enough space on ${RUNDIR} to continue working), pquery-run.sh will NOT terminate."
    echoit "However, this looks like a shortcoming in pquery-run.sh (likely in the mysqld termination code) which needs debugging and fixing. Please do."
  fi
}

check_cmd() {
  CMD_PID=$1
  ERROR_MSG=$2
  if [ ${CMD_PID} -ne 0 ]; then
    echo -e "\nERROR: $ERROR_MSG. Terminating!"
    exit 1
  fi
}

handle_bugs() {
  cd ${RUNDIR}/${TRIAL} || exit 1
  add_handy_scripts
  TEXT=$(${SCRIPT_PWD}/new_text_string.sh)
  if [[ ${MDG} -eq 1 ]]; then
    echo "${TEXT}" | grep -v '^[ \t]*$' > ${RUNDIR}/${TRIAL}/node${j}/MYBUG
  else
    echo "${TEXT}" | grep -v '^[ \t]*$' > ${RUNDIR}/${TRIAL}/MYBUG
  fi
  cd - >/dev/null || exit 1
  if [[ ${MDG} -eq 1 ]]; then
    if grep -qi "No .* found [ia][nt]" ${RUNDIR}/${TRIAL}/node${j}/MYBUG; then
      echoit "Assert: we found a coredump at $(ls ${RUNDIR}/${TRIAL}/node${j}/*core* 2> /dev/null), yet ${SCRIPT_PWD}/new_text_string.sh produced this output: ${TEXT}"
      exit 1
    fi
  else
    if grep -qi "No .* found [ia][nt]" ${RUNDIR}/${TRIAL}/MYBUG; then
      echoit "Assert: we found a coredump at $(ls ${RUNDIR}/${TRIAL}/*/*core* 2> /dev/null), yet ${SCRIPT_PWD}/new_text_string.sh produced this output: ${TEXT}"
      exit 1
    fi
  fi
  echoit "Bug found (as per new_text_string.sh): ${TEXT}"
  TRIAL_TO_SAVE=1
  if [ "${ELIMINATE_KNOWN_BUGS}" == "1" -a -r ${SCRIPT_PWD}/known_bugs.strings ]; then # "1": String check hack to ensure backwards compatibility with older pquery-run.conf files
    set +H                                                                          # Disables history substitution and avoids  -bash: !: event not found  like errors
    FINDBUG="$(grep -Fi --binary-files=text "${TEXT}" ${SCRIPT_PWD}/known_bugs.strings)"
    if [ "$(echo "${FINDBUG}" | sed 's|[ \t]*\(.\).*|\1|')" == "#" ]; then FINDBUG=""; fi  # Bugs marked as fixed need to be excluded. This cannot be done by using "^${TEXT}" as the grep is not regex aware, nor can it be, due to the many special (regex-like) characters in the unique bug strings
    if [ ! -z "${FINDBUG}" ]; then  # do not call savetrial, known/filtered bug seen
      echoit "This is aleady known and logged, non-fixed bug: ${FINDBUG}"
      echoit "Deleting trial as ELIMINATE_KNOWN_BUGS=1, bug was already logged and is still open"
      ALREADY_KNOWN=$[ ${ALREADY_KNOWN} + 1]
      TRIAL_TO_SAVE=0
    else
      NEWBUGS=$[ ${NEWBUGS} + 1 ]
      echoit "[${NEWBUGS}] *** NEW BUG *** (not found in ${SCRIPT_PWD}/known_bugs.strings, or found but marked as already fixed)"
    fi
    FINDBUG=
  fi
}

if [[ $MDG -eq 1 ]]; then
  # Creating default my.cnf file
  SUSER=root
  SPASS=
  rm -rf ${BASEDIR}/my.cnf
  echo "[mysqld]" > ${BASEDIR}/my.cnf
  echo "basedir=${BASEDIR}" >> ${BASEDIR}/my.cnf
  echo "innodb_file_per_table" >> ${BASEDIR}/my.cnf
  echo "innodb_autoinc_lock_mode=2" >> ${BASEDIR}/my.cnf
  echo "wsrep-provider=${BASEDIR}/lib/libgalera_smm.so" >> ${BASEDIR}/my.cnf
  if [ ${MDG_SST_METHOD} -eq 1 ] ; then
    echo "wsrep_sst_method=rsync" >> ${BASEDIR}/my.cnf
  else
    echo "wsrep_sst_method=mariabackup" >> ${BASEDIR}/my.cnf
  fi
  echo "wsrep_sst_auth=root:" >> ${BASEDIR}/my.cnf
  echo "binlog_format=ROW" >> ${BASEDIR}/my.cnf
  echo "core-file" >> ${BASEDIR}/my.cnf
  echo "log-output=none" >> ${BASEDIR}/my.cnf
  echo "wsrep_slave_threads=12" >> ${BASEDIR}/my.cnf
  echo "wsrep_on=1" >> ${BASEDIR}/my.cnf
  if [[ "$ENCRYPTION_RUN" == 1 ]]; then
    echo "encrypt_binlog=1" >> ${BASEDIR}/my.cnf
    echo "plugin_load_add=file_key_management" >> ${BASEDIR}/my.cnf
    echo "file_key_management_filename=${SCRIPT_PWD}/pquery/galera_encryption.key" >> ${BASEDIR}/my.cnf
    echo "file_key_management_encryption_algorithm=aes_cbc" >> ${BASEDIR}/my.cnf
    echo "innodb_encrypt_tables=ON" >> ${BASEDIR}/my.cnf
    echo "innodb_encryption_rotate_key_age=0" >> ${BASEDIR}/my.cnf
    echo "innodb_encrypt_log=ON" >> ${BASEDIR}/my.cnf
    echo "innodb_encryption_threads=4" >> ${BASEDIR}/my.cnf
    echo "innodb_encrypt_temporary_tables=ON" >> ${BASEDIR}/my.cnf
    echo "encrypt_tmp_disk_tables=1" >> ${BASEDIR}/my.cnf
    echo "encrypt_tmp_files=1" >> ${BASEDIR}/my.cnf
    echo "aria_encrypt_tables=ON" >> ${BASEDIR}/my.cnf
  fi
fi

mdg_startup() {
  IS_STARTUP=$1
  ADDR="127.0.0.1"
  SOCKET1=${RUNDIR}/${TRIAL}/node1/node1_socket.sock
  SOCKET2=${RUNDIR}/${TRIAL}/node2/node2_socket.sock
  SOCKET3=${RUNDIR}/${TRIAL}/node3/node3_socket.sock
  mdg_startup_chk() {
    ERROR_LOG=$1
    if grep -qi "Can.t create.write to file" ${RUNDIR}/${TRIAL}/log/master.err; then
      echoit "Assert! Likely an incorrect --init-file option was specified (check if the specified file actually exists)"  # Also see https://jira.mariadb.org/browse/MDEV-27232
      echoit "Terminating run as there is no point in continuing; all trials will fail with this error."
      removetrial
      exit 1
    elif grep -qi "ERROR. Aborting" $ERROR_LOG; then
      if grep -qi "TCP.IP port.*Address already in use" $ERROR_LOG; then
        echoit "Assert! The text '[ERROR] Aborting' was found in the error log due to a IP port conflict (the port was already in use)"
        removetrial
      else
        if [ ${MDG_ADD_RANDOM_OPTIONS} -eq 0 ]; then # Halt for MDG_ADD_RANDOM_OPTIONS=0 runs which have 'ERROR. Aborting' in the error log, as they should not produce errors like these, given that the MDG_MYEXTRA and WSREP_PROVIDER_OPT lists are/should be high-quality/non-faulty
          echoit "Assert! '[ERROR] Aborting' was found in the error log. This is likely an issue with one of the \$MDG_MYEXTRA (${MDG_MYEXTRA}) startup or \$WSREP_PROVIDER_OPT ($WSREP_PROVIDER_OPT) congifuration options. Saving trial for further analysis, and dumping error log here for quick analysis. Please check the output against these variables settings. The respective files for these options (${MDG_WSREP_OPTIONS_INFILE} and ${MDG_WSREP_PROVIDER_OPTIONS_INFILE}) may require editing."
          grep "ERROR" -B5 -A3 $ERROR_LOG | tee -a /${WORKDIR}/pquery-run.log
          if [ ${MDG_IGNORE_ALL_OPTION_ISSUES} -eq 1 ]; then
            echoit "MDG_IGNORE_ALL_OPTION_ISSUES=1, so irrespective of the assert given, pquery-run.sh will continue running. Please check your option files!"
          else
            if grep -qi "Could not open mysql.plugin" $ERROR_LOG; then  # Likely OOS on /dev/shm
              echoit "Found 'Could not open mysql.plugin' in error log, likely OOS on ${RUNDIR} or in /tmp or root (/). Removing trial to maximize space, and pausing 0.5 hour before trying again (reducer's may be running and consuming space)"
              removetrial
              sleep 1800
              echoit "Slept 0.5h, resuming pquery-run.sh run..."
            else
              savetrial
              echoit "Remember to cleanup/delete the rundir:  rm -Rf ${RUNDIR}"
              exit 1
            fi
          fi
        else # Do not halt for MDG_ADD_RANDOM_OPTIONS=1 runs, they are likely to produce errors like these as MDG_MYEXTRA was randomly changed
          echoit "'[ERROR] Aborting' was found in the error log. This is likely an issue with one of the \$MDG_MYEXTRA (${MDG_MYEXTRA}) startup options. As \$MDG_ADD_RANDOM_OPTIONS=1, this is likely to be encountered given the random addition of mysqld options. Not saving trial. If you see this error for every trial however, set \$MDG_ADD_RANDOM_OPTIONS=0 & try running pquery-run.sh again. If it still fails, it is likely that your base \$MYEXTRA (${MYEXTRA}) setting is faulty."
          grep "ERROR" -B5 -A3 $ERROR_LOG | tee -a /${WORKDIR}/pquery-run.log
          FAILEDSTARTABORT=1
          return
        fi
      fi
    fi
  }
  if [ "$IS_STARTUP" != "startup" ]; then
    echo "echo '=== Starting MDG cluster for recovery...'" > ${RUNDIR}/${TRIAL}/start_mdg_recovery
    echo "sed -i 's|safe_to_bootstrap:.*$|safe_to_bootstrap: 1|' ${WORKDIR}/${TRIAL}/node1/grastate.dat" >> ${RUNDIR}/${TRIAL}/start_mdg_recovery
  fi
  mdg_startup_status() {
    NR=$1
    for X in $(seq 0 ${MDG_START_TIMEOUT}); do
      sleep 1
      if ${BASEDIR}/bin/mysqladmin -uroot -S${SOCKET} ping > /dev/null 2>&1; then
        break
      fi
      if [[ $X -eq $((MDG_START_TIMEOUT - 1)) ]]; then
        mdg_startup_chk ${ERR_FILE}
      fi
    done
  }
  unset MDG_PORTS
  unset MDG_LADDRS
  MDG_PORTS=""
  MDG_LADDRS=""
  for i in $(seq 1 ${NR_OF_NODES}); do
    init_empty_port
    RBASE=${NEWPORT}
    NEWPORT=
    init_empty_port
    LADDR="127.0.0.1:${NEWPORT}"
    NEWPORT=
    init_empty_port
    SST_PORT="127.0.0.1:${NEWPORT}"
    NEWPORT=
    init_empty_port
    IST_PORT="127.0.0.1:${NEWPORT}"
    NEWPORT=
    MDG_PORTS+=("$RBASE")
    MDG_LADDRS+=("$LADDR")
    if [ "$IS_STARTUP" == "startup" ]; then
      node="${WORKDIR}/node${i}.template"
      if ! check_for_version $MYSQL_VERSION "5.7.0"; then
        diskspace
        mkdir -p $node
      fi
      DATADIR=${WORKDIR}
    else
      node="${RUNDIR}/${TRIAL}/node${i}"
      DATADIR="${RUNDIR}/${TRIAL}"
    fi
    diskspace
    mkdir -p $DATADIR/tmp${i}
    cp ${BASEDIR}/my.cnf ${DATADIR}/n${i}.cnf
    sed -i "2i server-id=10${i}" ${DATADIR}/n${i}.cnf
    sed -i "2i wsrep_node_incoming_address=$ADDR" ${DATADIR}/n${i}.cnf
    sed -i "2i wsrep_node_address=$ADDR" ${DATADIR}/n${i}.cnf
    sed -i "2i wsrep_sst_receive_address=$SST_PORT" ${DATADIR}/n${i}.cnf
    sed -i "2i log-error=$node/node${i}.err" ${DATADIR}/n${i}.cnf
    sed -i "2i port=$RBASE" ${DATADIR}/n${i}.cnf
    sed -i "2i datadir=$node" ${DATADIR}/n${i}.cnf
    sed -i "2i socket=$node/node${i}_socket.sock" ${DATADIR}/n${i}.cnf
    sed -i "2i tmpdir=$DATADIR/tmp${i}" ${DATADIR}/n${i}.cnf
    if [[ "$ENCRYPTION_RUN" != 1 ]]; then
      sed -i "2i wsrep_provider_options=\"gmcast.listen_addr=tcp://$LADDR;ist.recv_addr=$IST_PORT;$WSREP_PROVIDER_OPT\"" ${DATADIR}/n${i}.cnf
    else
      sed -i "2i wsrep_provider_options=\"gmcast.listen_addr=tcp://$LADDR;ist.recv_addr=$IST_PORT;$WSREP_PROVIDER_OPT;socket.ssl_key=${WORKDIR}/cert/server-key.pem;socket.ssl_cert=${WORKDIR}/cert/server-cert.pem;socket.ssl_ca=${WORKDIR}/cert/ca.pem\"" ${DATADIR}/n${i}.cnf
      echo "ssl-ca = ${WORKDIR}/cert/ca.pem" >> ${DATADIR}/n${i}.cnf
      echo "ssl-cert = ${WORKDIR}/cert/server-cert.pem" >> ${DATADIR}/n${i}.cnf
      echo "ssl-key = ${WORKDIR}/cert/server-key.pem" >> ${DATADIR}/n${i}.cnf

      echo "[sst]" >> ${DATADIR}/n${i}.cnf
      echo "encrypt = 3" >> ${DATADIR}/n${i}.cnf
      echo "tcert = ${WORKDIR}/cert/server-cert.pem" >> ${DATADIR}/n${i}.cnf
      echo "tkey = ${WORKDIR}/cert/server-key.pem" >> ${DATADIR}/n${i}.cnf
    fi
    if [ "$IS_STARTUP" == "startup" ]; then
      ${INIT_TOOL} ${INIT_OPT} --basedir=${BASEDIR} --datadir=$node > ${WORKDIR}/startup_node1.err 2>&1
    fi
  done
  if [ "$IS_STARTUP" == "startup" ]; then
    diskspace
    rm -rf ${WORKDIR}/cert && mkdir -p ${WORKDIR}/cert
    pushd ${WORKDIR}/cert
    # Creating CA certificate
    openssl genrsa 2048 > ca-key.pem
    openssl req -new -x509 -nodes -days 3600 -key ca-key.pem -out ca.pem -subj '/CN=www.mariadb.com/O=RDBMS/C=US'
    # Creating server certificate
    openssl req -newkey rsa:2048 -days 3600 -nodes -keyout server-key.pem -out server-req.pem -subj '/CN=www.mariadb.com/O=RDBMS/C=AU'
    openssl rsa -in server-key.pem -out server-key.pem
    openssl x509 -req -in server-req.pem -days 3600 -CA ca.pem -CAkey ca-key.pem -set_serial 01 -out server-cert.pem
    popd
  fi
  get_error_socket_file() {
    NR=$1
    if [ "$IS_STARTUP" == "startup" ]; then
      ERR_FILE="${WORKDIR}/node${NR}.template/node${NR}.err"
      SOCKET="${WORKDIR}/node${NR}.template/node${NR}_socket.sock"
    else
      ERR_FILE="${RUNDIR}/${TRIAL}/node${NR}/node${NR}.err"
      SOCKET="${RUNDIR}/${TRIAL}/node${NR}/node${NR}_socket.sock"
    fi
  }
  if [[ $WITH_KEYRING_VAULT -eq 1 ]]; then
    MYEXTRA_KEYRING="--early-plugin-load=keyring_vault.so --loose-keyring_vault_config=${WORKDIR}/vault/keyring_vault_mdg${i}.cnf"
  fi

  if [ "${VALGRIND_RUN}" == "1" ]; then
    VALGRIND_CMD="${VALGRIND_CMD}"
  else
    VALGRIND_CMD=""
  fi
  diskspace
  WSREP_CLUSTER_ADDRESS=$(printf "%s,"  "${MDG_LADDRS[@]}")
  for j in $(seq 1 ${NR_OF_NODES}); do
    sed -i "2i wsrep_cluster_address=gcomm://${WSREP_CLUSTER_ADDRESS:1}" ${DATADIR}/n${j}.cnf
    get_error_socket_file ${j}
    if [ ${j} -eq 1 ]; then
      if [ "${RR_TRACING}" == "0" ]; then
        $VALGRIND_CMD ${BASEDIR}/bin/mysqld --defaults-file=${DATADIR}/n${j}.cnf $STARTUP_OPTION $MYEXTRA_KEYRING $MYEXTRA $MDG_MYEXTRA --wsrep-new-cluster > ${ERR_FILE} 2>&1 &
      else
        if [ "$IS_STARTUP" == "startup" ]; then
          ${BASEDIR}/bin/mysqld --defaults-file=${DATADIR}/n${j}.cnf $STARTUP_OPTION $MYEXTRA_KEYRING $MYEXTRA $MDG_MYEXTRA --wsrep-new-cluster > ${ERR_FILE} 2>&1 &
        else
          export _RR_TRACE_DIR="${RUNDIR}/${TRIAL}/rr"
          mkdir -p "${_RR_TRACE_DIR}"
          /usr/bin/rr record --chaos ${BASEDIR}/bin/mysqld --defaults-file=${DATADIR}/n${j}.cnf $STARTUP_OPTION $MYEXTRA_KEYRING $MYEXTRA $MDG_MYEXTRA --wsrep-new-cluster > ${ERR_FILE} 2>&1 &
        fi
      fi
      mdg_startup_status ${j}
    else
      get_error_socket_file ${j}
      $VALGRIND_CMD ${BASEDIR}/bin/mysqld --defaults-file=${DATADIR}/n${j}.cnf \
        $STARTUP_OPTION $MYEXTRA_KEYRING $MYEXTRA $MDG_MYEXTRA > ${ERR_FILE} 2>&1 &
      mdg_startup_status ${j}
    fi
    if [ "$IS_STARTUP" != "startup" ]; then
      if [ ${j} -eq 1 ]; then
        echo "RUNDIR=$RUNDIR" >> ${RUNDIR}/${TRIAL}/start_mdg_recovery
        echo "WORKDIR=${WORKDIR}" >> ${RUNDIR}/${TRIAL}/start_mdg_recovery
        echo "startup_check(){ " >> ${RUNDIR}/${TRIAL}/start_mdg_recovery
        echo "  SOCKET=\$1" >> ${RUNDIR}/${TRIAL}/start_mdg_recovery
        echo "  for X in \`seq 0 200\`; do" >> ${RUNDIR}/${TRIAL}/start_mdg_recovery
        echo "    sleep 1" >> ${RUNDIR}/${TRIAL}/start_mdg_recovery
        echo "    if ${BASEDIR}/bin/mysqladmin -uroot -S\${SOCKET} ping > /dev/null 2>&1; then" >> ${RUNDIR}/${TRIAL}/start_mdg_recovery
        echo "      break" >> ${RUNDIR}/${TRIAL}/start_mdg_recovery
        echo "    fi" >> ${RUNDIR}/${TRIAL}/start_mdg_recovery
        echo "  done" >> ${RUNDIR}/${TRIAL}/start_mdg_recovery
        echo "}" >> ${RUNDIR}/${TRIAL}/start_mdg_recovery
        echo "" >> ${RUNDIR}/${TRIAL}/start_mdg_recovery
        echo "sed -i \"s|\$RUNDIR|\${WORKDIR}|g\" ${WORKDIR}/${TRIAL}/n${j}.cnf" >> ${RUNDIR}/${TRIAL}/start_mdg_recovery
        echo "$VALGRIND_CMD ${BASEDIR}/bin/mysqld --defaults-file=${WORKDIR}/${TRIAL}/n${j}.cnf $STARTUP_OPTION $MYEXTRA_KEYRING $MYEXTRA $MDG_MYEXTRA  --wsrep-new-cluster > ${RUNDIR}/${TRIAL}/node${j}/node${j}.err 2>&1 &" >> ${RUNDIR}/${TRIAL}/start_mdg_recovery
        echo "startup_check $node/node${j}_socket.sock" >> ${RUNDIR}/${TRIAL}/start_mdg_recovery
      fi
      echo "$VALGRIND_CMD ${BASEDIR}/bin/mysqld --defaults-file=${WORKDIR}/${TRIAL}/n${j}.cnf $STARTUP_OPTION $MYEXTRA_KEYRING $MYEXTRA $MDG_MYEXTRA > ${RUNDIR}/${TRIAL}/node${j}/node${j}.err  2>&1 &" >> ${RUNDIR}/${TRIAL}/start_mdg_recovery
      echo "startup_check $node/node${j}_socket.sock" >> ${RUNDIR}/${TRIAL}/start_mdg_recovery
    fi
  done
  if [ "$IS_STARTUP" != "startup" ]; then
    for j in $(seq 1 ${NR_OF_NODES}); do
      echo "echo \"${BASEDIR}/bin/mysqladmin -uroot -S${WORKDIR}/${TRIAL}/node${j}/node${j}_socket.sock shutdown > /dev/null 2>&1\" > ${WORKDIR}/${TRIAL}/stop_mdg_recovery" >> ${RUNDIR}/${TRIAL}/start_mdg_recovery
      echo "chmod +x ${WORKDIR}/${TRIAL}/stop_mdg_recovery" >> ${RUNDIR}/${TRIAL}/start_mdg_recovery
    done
    chmod +x ${RUNDIR}/${TRIAL}/start_mdg_recovery
    ${BASEDIR}/bin/mysql -uroot -S${RUNDIR}/${TRIAL}/node1/node1_socket.sock -e "create database if not exists test" > /dev/null 2>&1
  fi
}

gr_startup() {
  ADDR="127.0.0.1"
  RPORT=$((RANDOM % 21 + 10))
  RBASE="$((RPORT * 1000))"
  RBASE1="$((RBASE + 1))"
  RBASE2="$((RBASE + 2))"
  RBASE3="$((RBASE + 3))"
  LADDR1="$ADDR:$((RBASE + 101))"
  LADDR2="$ADDR:$((RBASE + 102))"
  LADDR3="$ADDR:$((RBASE + 103))"

  SUSER=root
  SPASS=

  MID="${BASEDIR}/bin/mysqld --no-defaults --initialize-insecure --basedir=${BASEDIR}"
  if [ ${GRP_RPL_CLUSTER_RUN} -eq 1 ]; then
    MYEXTRA="$MYEXTRA --plugin-load=group_replication.so --group_replication_single_primary_mode=OFF"
  else
    MYEXTRA="$MYEXTRA --plugin-load=group_replication.so"
  fi
  if [ "$1" == "startup" ]; then
    node1="${WORKDIR}/node1.template"
    node2="${WORKDIR}/node2.template"
    node3="${WORKDIR}/node3.template"
  else
    node1="${RUNDIR}/${TRIAL}/node1"
    node2="${RUNDIR}/${TRIAL}/node2"
    node3="${RUNDIR}/${TRIAL}/node3"
  fi

  gr_startup_chk() {
    ERROR_LOG=$1
    if grep -qi "Can.t create.write to file" ${RUNDIR}/${TRIAL}/log/master.err; then
      echoit "Assert! Likely an incorrect --init-file option was specified (check if the specified file actually exists)"  # Also see https://jira.mariadb.org/browse/MDEV-27232
      echoit "Terminating run as there is no point in continuing; all trials will fail with this error."
      removetrial
      exit 1
    elif grep -qi "ERROR. Aborting" $ERROR_LOG; then
      if grep -qi "TCP.IP port.*Address already in use" $ERROR_LOG; then
        echoit "Assert! The text '[ERROR] Aborting' was found in the error log due to a IP port conflict (the port was already in use)"
        removetrial
      else
        echoit "Assert! '[ERROR] Aborting' was found in the error log. This is likely an issue with one of the \$MYEXTRA (${MYEXTRA}) startup options. Saving trial for further analysis, and dumping error log here for quick analysis. Please check the output against these variables settings."
        grep "ERROR" -B5 -A3 $ERROR_LOG | tee -a /${WORKDIR}/pquery-run.log
        if grep -qi "Could not open mysql.plugin" $ERROR_LOG; then  # Likely OOS on /dev/shm
          echoit "Found 'Could not open mysql.plugin' in error log, likely OOS on ${RUNDIR} or in /tmp or root (/). Removing trial to maximize space, and pausing 0.5 hour before trying again (reducer's may be running and consuming space)"
          removetrial
          sleep 1800
          echoit "Slept 0.5h, resuming pquery-run.sh run..."
        else
          savetrial
          echoit "Remember to cleanup/delete the rundir:  rm -Rf ${RUNDIR}"
          exit 1
        fi
      fi
    fi
  }

  if [ "$1" == "startup" ]; then
    ${MID} --datadir=$node1 > ${WORKDIR}/startup_node1.err 2>&1 || exit 1
  fi

  ${BASEDIR}/bin/mysqld --no-defaults \
    --basedir=${BASEDIR} --datadir=$node1 \
    --innodb_file_per_table $MYEXTRA --innodb_autoinc_lock_mode=2 --innodb_locks_unsafe_for_binlog=1 \
    --server_id=1 --gtid_mode=ON --enforce_gtid_consistency=ON \
    --master_info_repository=TABLE --relay_log_info_repository=TABLE \
    --binlog_checksum=NONE --log_slave_updates=ON --log_bin=binlog \
    --binlog_format=ROW --innodb_flush_method=O_DIRECT \
    --core-file --sql-mode=no_engine_substitution \
    --loose-innodb --secure-file-priv= --loose-innodb-status-file=1 \
    --log-error=$node1/node1.err \
    --socket=$node1/node1_socket.sock --log-output=none \
    --port=$RBASE1 --transaction_write_set_extraction=XXHASH64 \
    --loose-group_replication_group_name="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" \
    --loose-group_replication_start_on_boot=off --loose-group_replication_local_address="$LADDR1" \
    --loose-group_replication_group_seeds="$LADDR1,$LADDR2,$LADDR3" \
    --loose-group_replication_bootstrap_group=off --super_read_only=OFF > $node1/node1.err 2>&1 &

  for X in $(seq 0 ${GRP_RPL_START_TIMEOUT}); do
    sleep 1
    if ${BASEDIR}/bin/mysqladmin -uroot -S$node1/node1_socket.sock ping > /dev/null 2>&1; then
      sleep 2
      if [ "$1" == "startup" ]; then
        ${BASEDIR}/bin/mysql -uroot -S$node1/node1_socket.sock -Bse "SET SQL_LOG_BIN=0;CREATE USER rpl_user@'%';GRANT REPLICATION SLAVE ON *.* TO rpl_user@'%' IDENTIFIED BY 'rpl_pass';FLUSH PRIVILEGES;SET SQL_LOG_BIN=1;" > /dev/null 2>&1
        ${BASEDIR}/bin/mysql -uroot -S$node1/node1_socket.sock -Bse "CHANGE MASTER TO MASTER_USER='rpl_user', MASTER_PASSWORD='rpl_pass' FOR CHANNEL 'group_replication_recovery';" > /dev/null 2>&1
        ${BASEDIR}/bin/mysql -uroot -S$node1/node1_socket.sock -Bse "SET GLOBAL group_replication_bootstrap_group=ON;START GROUP_REPLICATION;SET GLOBAL group_replication_bootstrap_group=OFF;SELECT SLEEP(10);" > /dev/null 2>&1
        ${BASEDIR}/bin/mysql -uroot -S$node1/node1_socket.sock -Bse "create database if not exists test" > /dev/null 2>&1
      else
        ${BASEDIR}/bin/mysql -uroot -S$node1/node1_socket.sock -Bse "SET GLOBAL group_replication_bootstrap_group=ON;START GROUP_REPLICATION;SET GLOBAL group_replication_bootstrap_group=OFF;SELECT SLEEP(5);" > /dev/null 2>&1
      fi
      break
    fi
    gr_startup_chk $node1/node1.err
  done

  if [ "$1" == "startup" ]; then
    ${MID} --datadir=$node2 > ${WORKDIR}/startup_node2.err 2>&1 || exit 1
  fi

  ${BASEDIR}/bin/mysqld --no-defaults \
    --basedir=${BASEDIR} --datadir=$node2 \
    --innodb_file_per_table $MYEXTRA --innodb_autoinc_lock_mode=2 --innodb_locks_unsafe_for_binlog=1 \
    --server_id=1 --gtid_mode=ON --enforce_gtid_consistency=ON \
    --master_info_repository=TABLE --relay_log_info_repository=TABLE \
    --binlog_checksum=NONE --log_slave_updates=ON --log_bin=binlog \
    --binlog_format=ROW --innodb_flush_method=O_DIRECT \
    --core-file --sql-mode=no_engine_substitution \
    --loose-innodb --secure-file-priv= --loose-innodb-status-file=1 \
    --log-error=$node2/node2.err \
    --socket=$node2/node2_socket.sock --log-output=none \
    --port=$RBASE2 --transaction_write_set_extraction=XXHASH64 \
    --loose-group_replication_group_name="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" \
    --loose-group_replication_start_on_boot=off --loose-group_replication_local_address="$LADDR2" \
    --loose-group_replication_group_seeds="$LADDR1,$LADDR2,$LADDR3" \
    --loose-group_replication_bootstrap_group=off --super_read_only=OFF > $node2/node2.err 2>&1 &

  for X in $(seq 0 ${GRP_RPL_START_TIMEOUT}); do
    sleep 1
    if ${BASEDIR}/bin/mysqladmin -uroot -S$node2/node2_socket.sock ping > /dev/null 2>&1; then
      sleep 2
      if [ "$1" == "startup" ]; then
        ${BASEDIR}/bin/mysql -uroot -S$node2/node2_socket.sock -Bse "SET SQL_LOG_BIN=0;CREATE USER rpl_user@'%';GRANT REPLICATION SLAVE ON *.* TO rpl_user@'%' IDENTIFIED BY 'rpl_pass';FLUSH PRIVILEGES;SET SQL_LOG_BIN=1;" > /dev/null 2>&1
        ${BASEDIR}/bin/mysql -uroot -S$node2/node2_socket.sock -Bse "CHANGE MASTER TO MASTER_USER='rpl_user', MASTER_PASSWORD='rpl_pass' FOR CHANNEL 'group_replication_recovery';" > /dev/null 2>&1
        ${BASEDIR}/bin/mysql -uroot -S$node2/node2_socket.sock -Bse "START GROUP_REPLICATION;" > /dev/null 2>&1
      else
        ${BASEDIR}/bin/mysql -uroot -S$node2/node2_socket.sock -Bse "START GROUP_REPLICATION;SELECT SLEEP(5);" > /dev/null 2>&1
      fi
      break
    fi
    gr_startup_chk $node2/node2.err
  done

  if [ "$1" == "startup" ]; then
    ${MID} --datadir=$node3 > ${WORKDIR}/startup_node3.err 2>&1 || exit 1
  fi

  ${BASEDIR}/bin/mysqld --no-defaults \
    --basedir=${BASEDIR} --datadir=$node3 \
    --innodb_file_per_table $MYEXTRA --innodb_autoinc_lock_mode=2 --innodb_locks_unsafe_for_binlog=1 \
    --server_id=1 --gtid_mode=ON --enforce_gtid_consistency=ON \
    --master_info_repository=TABLE --relay_log_info_repository=TABLE \
    --binlog_checksum=NONE --log_slave_updates=ON --log_bin=binlog \
    --binlog_format=ROW --innodb_flush_method=O_DIRECT \
    --core-file --sql-mode=no_engine_substitution \
    --loose-innodb --secure-file-priv= --loose-innodb-status-file=1 \
    --log-error=$node3/node3.err \
    --socket=$node3/node3_socket.sock --log-output=none \
    --port=$RBASE3 --transaction_write_set_extraction=XXHASH64 \
    --loose-group_replication_group_name="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" \
    --loose-group_replication_start_on_boot=off --loose-group_replication_local_address="$LADDR3" \
    --loose-group_replication_group_seeds="$LADDR1,$LADDR2,$LADDR3" \
    --loose-group_replication_bootstrap_group=off --super_read_only=OFF > $node3/node3.err 2>&1 &

  for X in $(seq 0 ${GRP_RPL_START_TIMEOUT}); do
    sleep 1
    if ${BASEDIR}/bin/mysqladmin -uroot -S$node3/node3_socket.sock ping > /dev/null 2>&1; then
      sleep 2
      if [ "$1" == "startup" ]; then
        ${BASEDIR}/bin/mysql -uroot -S$node3/node3_socket.sock -Bse "SET SQL_LOG_BIN=0;CREATE USER rpl_user@'%';GRANT REPLICATION SLAVE ON *.* TO rpl_user@'%' IDENTIFIED BY 'rpl_pass';FLUSH PRIVILEGES;SET SQL_LOG_BIN=1;" > /dev/null 2>&1
        ${BASEDIR}/bin/mysql -uroot -S$node3/node3_socket.sock -Bse "CHANGE MASTER TO MASTER_USER='rpl_user', MASTER_PASSWORD='rpl_pass' FOR CHANNEL 'group_replication_recovery';" > /dev/null 2>&1
        ${BASEDIR}/bin/mysql -uroot -S$node3/node3_socket.sock -Bse "START GROUP_REPLICATION;" > /dev/null 2>&1
      else
        ${BASEDIR}/bin/mysql -uroot -S$node3/node3_socket.sock -Bse "START GROUP_REPLICATION;SELECT SLEEP(5);" > /dev/null 2>&1
      fi
      break
    fi
    gr_startup_chk $node3/node3.err
  done
}

pquery_test() {
  TRIAL=$((${TRIAL} + 1))
  SOCKET=${RUNDIR}/${TRIAL}/socket.sock
  echoit "====== TRIAL #${TRIAL} ======"
  echoit "Ensuring there are no relevant servers running..."
  KILLPID=$(ps -ef | grep "${RUNDIR}" | grep -v grep | awk '{print $2}' | tr '\n' ' ')
  (
    sleep 0.2
    kill -9 $KILLPID > /dev/null 2>&1
    timeout -k4 -s9 4s wait $KILLPID > /dev/null 2>&1
  ) &
  timeout -k5 -s9 5s wait $KILLPID > /dev/null 2>&1 # The sleep 0.2 + subsequent wait (cought before the kill) avoids the annoying 'Killed' message from being displayed in the output. Thank you to user 'Foonly' @ forums.whirlpool.net.au
  echoit "Clearing rundir..."
  rm -Rf ${RUNDIR}/[0-9A-Za-ln-z]* # m* is avoided to leave ./mysqld in place
  if [ ${USE_GENERATOR_INSTEAD_OF_INFILE} -eq 1 ]; then
    echoit "Generating new SQL inputfile using the SQL Generator..."
    SAVEDIR=${PWD}
    cd ${SCRIPT_PWD}/generator/ || exit 1
    if [ ${TRIAL} -eq 1 -o $((${TRIAL} % ${GENERATE_NEW_QUERIES_EVERY_X_TRIALS})) -eq 0 ]; then
      if [ "${RANDOMD}" == "" ]; then
        echoit "Assert: RANDOMD is empty. This should not happen. Terminating."
        exit 1
      fi
      cp generator.sh generator${RANDOMD}.sh
      sed -i "s|^[ \t]*OUTPUT_FILE[ \t]*=.*|OUTPUT_FILE=out${RANDOMD}|" generator${RANDOMD}.sh
      ./generator${RANDOMD}.sh ${QUERIES_PER_GENERATOR_RUN} > /dev/null
      if [ ! -r out${RANDOMD}.sql ]; then
        echoit "Assert: out${RANDOMD}.sql not present in ${PWD} after generator execution! This script left ${PWD}/generator${RANDOMD}.sh in place to check what happened"
        exit 1
      fi
      rm -f generator${RANDOMD}.sh
      if [[ "${MYEXTRA^^}" != *"ROCKSDB"* ]]; then # If this is not a RocksDB run, exclude RocksDB SE
        sed -i "s|RocksDB|InnoDB|" out${RANDOMD}.sql
      fi
      if [[ "${MYEXTRA^^}" != *"HA_TOKUDB"* ]]; then # If this is not a TokuDB enabled run, exclude TokuDB SE
        sed -i "s|TokuDB|InnoDB|" out${RANDOMD}.sql
      fi
      if [ ${ADD_INFILE_TO_GENERATED_SQL} -eq 1 ]; then
        cat ${INFILE} >> out${RANDOMD}.sql
      fi
    fi
    INFILE=${PWD}/out${RANDOMD}.sql
    cd ${SAVEDIR} || exit 1
  fi
  echoit "Generating new trial workdir ${RUNDIR}/${TRIAL}..."
  ISSTARTED=0
  diskspace
  if [[ ${MDG} -eq 0 && ${GRP_RPL} -eq 0 ]]; then
    if check_for_version $MYSQL_VERSION "8.0.0"; then
      mkdir -p ${RUNDIR}/${TRIAL}/data ${RUNDIR}/${TRIAL}/tmp ${RUNDIR}/${TRIAL}/log # Cannot create /data/test, /data/mysql in 8.0
    else
      mkdir -p ${RUNDIR}/${TRIAL}/data/test ${RUNDIR}/${TRIAL}/data/mysql ${RUNDIR}/${TRIAL}/tmp ${RUNDIR}/${TRIAL}/log
    fi
    echo 'SELECT 1;' > ${RUNDIR}/${TRIAL}/startup_failure_thread-0.sql # Add fake file enabling pquery-prep-red.sh/reducer.sh to be used with/for mysqld startup issues
    diskspace
    if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 ]; then
      echoit "Copying datadir from template for Primary mysqld..."
    elif [[ ${PQUERY3} -eq 1 && ${TRIAL} -gt 1 ]]; then
      echoit "Copying datadir from Trial ${WORKDIR}/$((${TRIAL} - 1)) into ${WORKDIR}/${TRIAL}..."
    else
      echoit "Copying datadir from template..."
    fi
    if [ $(ls -l ${WORKDIR}/data.template/* | wc -l) -eq 0 ]; then
      echoit "Assert: ${WORKDIR}/data.template/ is empty? Check ${WORKDIR}/log/mysql_install_db.txt to see if the original template creation worked ok. Terminating."
      echoit "Note that this can be caused by not having perl-Data-Dumper installed (sudo yum install perl-Data-Dumper  #OR#  sudo apt-get install libdata-dumper-simple-perl), which is required for mysql_install_db."
      exit 1
    elif [[ ${PQUERY3} -eq 1 && ${TRIAL} -gt 1 ]]; then
      EXIT_CODE_CP=1
      while [ ${EXIT_CODE_CP} -eq 1]; do  # Loop till no error is observed (caters for OOS issues)
        if [ -d ${RUNDIR}/${TRIAL}/data ]; then  # Will exist if there was an OOS issue on second execution of this while loop
          rm -Rf ${RUNDIR}/${TRIAL}/data
          mkdir ${RUNDIR}/${TRIAL}/data
        fi
        cp -R ${WORKDIR}/$((${TRIAL} - 1))/data/* ${RUNDIR}/${TRIAL}/data 2>&1
        EXIT_CODE_CP=$?
      done
    else
      EXIT_CODE_CP=1
      while [ ${EXIT_CODE_CP} -eq 1]; do  # Loop till no error is observed (caters for OOS issues)
        if [ -d ${RUNDIR}/${TRIAL}/data ]; then  # Will exist if there was an OOS issue on second execution of this while loop
          rm -Rf ${RUNDIR}/${TRIAL}/data
          mkdir ${RUNDIR}/${TRIAL}/data
        fi
        cp -R ${WORKDIR}/data.template/* ${RUNDIR}/${TRIAL}/data 2>&1
        EXIT_CODE_CP=$?
      done
    fi
    if [[ ${REPL} -eq 1 ]]; then
      mkdir -p ${RUNDIR}/${TRIAL}/tmp_slave
      cp -r ${RUNDIR}/${TRIAL}/data ${RUNDIR}/${TRIAL}/data_slave
      SLAVE_SOCKET=${RUNDIR}/${TRIAL}/slave_socket.sock
    fi
    MYEXTRA_SAVE_IT=${MYEXTRA}
    if [ ${ADD_RANDOM_OPTIONS} -eq 1 ]; then # Add random mysqld --options to MYEXTRA
      OPTIONS_TO_ADD=
      NR_OF_OPTIONS_TO_ADD=$((RANDOM % MAX_NR_OF_RND_OPTS_TO_ADD + 1))
      for X in $(seq 1 ${NR_OF_OPTIONS_TO_ADD}); do
        OPTION_TO_ADD="$(shuf --random-source=/dev/urandom ${OPTIONS_INFILE} | head -n1)"
        if [ "$(echo ${OPTION_TO_ADD} | sed 's| ||g;s|.*query.alloc.block.size=1125899906842624.*||')" != "" ]; then # http://bugs.mysql.com/bug.php?id=78238
          OPTIONS_TO_ADD="${OPTIONS_TO_ADD} ${OPTION_TO_ADD}"
        fi
      done
      echoit "ADD_RANDOM_OPTIONS=1: adding mysqld option(s) ${OPTIONS_TO_ADD} to this run's MYEXTRA..."
      MYEXTRA="${MYEXTRA} ${OPTIONS_TO_ADD}"
      if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 ]; then
        MYEXTRA2="${MYEXTRA2} ${OPTIONS_TO_ADD}"
      fi
    fi
    if [ ${ADD_RANDOM_TOKUDB_OPTIONS} -eq 1 ]; then # Add random tokudb --options to MYEXTRA
      OPTIONS_TO_ADD=
      NR_OF_OPTIONS_TO_ADD=$((RANDOM % MAX_NR_OF_RND_OPTS_TO_ADD + 1))
      for X in $(seq 1 ${NR_OF_OPTIONS_TO_ADD}); do
        OPTION_TO_ADD=
        OPTION_TO_ADD="$(shuf --random-source=/dev/urandom ${TOKUDB_OPTIONS_INFILE} | head -n1)"
        OPTIONS_TO_ADD="${OPTIONS_TO_ADD} ${OPTION_TO_ADD}"
      done
      echoit "ADD_RANDOM_TOKUDB_OPTIONS=1: adding TokuDB mysqld option(s) ${OPTIONS_TO_ADD} to this run's MYEXTRA..."
      MYEXTRA="${MYEXTRA} ${OPTIONS_TO_ADD}"
      if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 ]; then
        MYEXTRA2="${MYEXTRA2} ${OPTIONS_TO_ADD}"
      fi
    fi
    if [ "${ADD_RANDOM_ROCKSDB_OPTIONS}" == "" ]; then # Backwards compatibility for .conf files without this option
      ADD_RANDOM_ROCKSDB_OPTIONS=0
    fi
    if [ ${ADD_RANDOM_ROCKSDB_OPTIONS} -eq 1 ]; then # Add random rocksdb --options to MYEXTRA
      OPTION_TO_ADD=
      OPTIONS_TO_ADD=
      NR_OF_OPTIONS_TO_ADD=$((RANDOM % MAX_NR_OF_RND_OPTS_TO_ADD + 1))
      for X in $(seq 1 ${NR_OF_OPTIONS_TO_ADD}); do
        OPTION_TO_ADD="$(shuf --random-source=/dev/urandom ${ROCKSDB_OPTIONS_INFILE} | head -n1)"
        OPTIONS_TO_ADD="${OPTIONS_TO_ADD} ${OPTION_TO_ADD}"
      done
      echoit "ADD_RANDOM_ROCKSDB_OPTIONS=1: adding RocksDB mysqld option(s) ${OPTIONS_TO_ADD} to this run's MYEXTRA..."
      MYEXTRA="${MYEXTRA} ${OPTIONS_TO_ADD}"
      if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 ]; then
        MYEXTRA2="${MYEXTRA2} ${OPTIONS_TO_ADD}"
      fi
    fi
    echo "${MYEXTRA}" | if grep -qi "innodb[_-]log[_-]checksum[_-]algorithm"; then
      # Ensure that mysqld server startup will not fail due to a mismatched checksum algo between the original MID and the changed MYEXTRA options
      rm ${RUNDIR}/${TRIAL}/data/ib_log*
    fi
    init_empty_port
    PORT=${NEWPORT}
    NEWPORT=
    if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 ]; then
      echoit "Starting Primary mysqld. Error log is stored at ${RUNDIR}/${TRIAL}/log/master.err"
    else
      echoit "Starting mysqld. Error log is stored at ${RUNDIR}/${TRIAL}/log/master.err"
    fi
    if [ "${RR_TRACING}" == "0" ]; then
      if [ "${VALGRIND_RUN}" == "0" ]; then  ## Standard run
        CMD="${BIN} ${MYSAFE} ${MYEXTRA} ${REPL_EXTRA} --basedir=${BASEDIR} --datadir=${RUNDIR}/${TRIAL}/data --tmpdir=${RUNDIR}/${TRIAL}/tmp \
         --core-file --port=$PORT --pid_file=${RUNDIR}/${TRIAL}/pid.pid --socket=${SOCKET} \
         --log-output=none --log-error=${RUNDIR}/${TRIAL}/log/master.err"
      else  ## Valgrind run
        CMD="${VALGRIND_CMD} ${BIN} ${MYSAFE} ${MYEXTRA} ${REPL_EXTRA} --basedir=${BASEDIR} --datadir=${RUNDIR}/${TRIAL}/data --tmpdir=${RUNDIR}/${TRIAL}/tmp \
         --core-file --port=$PORT --pid_file=${RUNDIR}/${TRIAL}/pid.pid --socket=${SOCKET} \
         --log-output=none --log-error=${RUNDIR}/${TRIAL}/log/master.err"
      fi
    else  ## rr tracing run
      export _RR_TRACE_DIR="${RUNDIR}/${TRIAL}/rr"
      mkdir -p "${_RR_TRACE_DIR}"
      CMD="/usr/bin/rr record --chaos ${BIN} ${MYSAFE} ${MYEXTRA} ${REPL_EXTRA} --basedir=${BASEDIR} --datadir=${RUNDIR}/${TRIAL}/data --tmpdir=${RUNDIR}/${TRIAL}/tmp \
       --core-file --port=$PORT --pid_file=${RUNDIR}/${TRIAL}/pid.pid --socket=${SOCKET} \
       --log-output=none --log-error=${RUNDIR}/${TRIAL}/log/master.err"
    fi
    diskspace
    $CMD > ${RUNDIR}/${TRIAL}/log/master.err 2>&1 &
    MPID="$!"
    if [[ ${REPL} -eq 1 ]]; then
      init_empty_port
      REPL_PORT=${NEWPORT}
      NEWPORT=
      if [ "${VALGRIND_RUN}" == "0" ]; then  ## Standard run
        SLAVE_STARTUP="${BIN} ${MYSAFE} ${MYEXTRA} ${REPL_EXTRA} --basedir=${BASEDIR} --datadir=${RUNDIR}/${TRIAL}/data_slave --tmpdir=${RUNDIR}/${TRIAL}/tmp_slave \
         --core-file --port=$REPL_PORT --pid_file=${RUNDIR}/${TRIAL}/slave_pid.pid --server_id=101 --socket=${SLAVE_SOCKET} \
         --log-output=none --log-error=${RUNDIR}/${TRIAL}/log/slave.err"
      else  ## Valgrind run
        SLAVE_STARTUP="${VALGRIND_CMD} ${BIN} ${MYSAFE} ${MYEXTRA} ${REPL_EXTRA} --basedir=${BASEDIR} --datadir=${RUNDIR}/${TRIAL}/data_slave --tmpdir=${RUNDIR}/${TRIAL}/tmp_slave \
         --core-file --port=$REPL_PORT --pid_file=${RUNDIR}/${TRIAL}/slave_pid.pid --server_id=101 --socket=${SLAVE_SOCKET} \
         --log-output=none --log-error=${RUNDIR}/${TRIAL}/log/slave.err"
      fi
      $SLAVE_STARTUP > ${RUNDIR}/${TRIAL}/log/slave.err 2>&1 &
      SLAVE_MPID="$!"
    fi
    if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 ]; then
      echoit "Starting Secondary mysqld. Error log is stored at ${RUNDIR}/${TRIAL}/log2/master.err"
      diskspace
      if check_for_version $MYSQL_VERSION "8.0.0"; then
        mkdir -p ${RUNDIR}/${TRIAL}/data2 ${RUNDIR}/${TRIAL}/tmp2 ${RUNDIR}/${TRIAL}/log2 # Cannot create /data/test, /data/mysql in 8.0
      else
        mkdir -p ${RUNDIR}/${TRIAL}/data2/test ${RUNDIR}/${TRIAL}/data2/mysql ${RUNDIR}/${TRIAL}/tmp2 ${RUNDIR}/${TRIAL}/log2
      fi
      echoit "Copying datadir from template for Secondary mysqld..."
      cp -R ${WORKDIR}/data.template/* ${RUNDIR}/${TRIAL}/data2 2>&1
      PORT2=$(($PORT + 1))
      if [ "${VALGRIND_RUN}" == "0" ]; then
        CMD2="${BIN} ${MYSAFE} ${MYEXTRA2} --basedir=${BASEDIR} --datadir=${RUNDIR}/${TRIAL}/data2 --tmpdir=${RUNDIR}/${TRIAL}/tmp2 \
          --core-file --port=$PORT2 --pid_file=${RUNDIR}/${TRIAL}/pid2.pid --socket=${RUNDIR}/${TRIAL}/socket2.sock \
          --log-output=none --log-error=${RUNDIR}/${TRIAL}/log2/master.err"
      else
        CMD2="${VALGRIND_CMD} ${BIN} ${MYSAFE} ${MYEXTRA2} --basedir=${BASEDIR} --datadir=${RUNDIR}/${TRIAL}/data2 --tmpdir=${RUNDIR}/${TRIAL}/tmp2 \
          --core-file --port=$PORT2 --pid_file=${RUNDIR}/${TRIAL}/pid2.pid --socket=${RUNDIR}/${TRIAL}/socket2.sock \
          --log-output=none --log-error=${RUNDIR}/${TRIAL}/log2/master.err"
      fi
      diskspace
      $CMD2 > ${RUNDIR}/${TRIAL}/log2/master.err 2>&1 &
      MPID2="$!"
      sleep 1
    fi
    diskspace
    echo "This script recreates the /dev/shm dirs for the trial and copies the current (crashed/ended state) data state to it." > ${RUNDIR}/${TRIAL}/start_dev_shm
    echo "This script can be considered safe to run as many times as needed, but remember to kill the running mysqld each time." >> ${RUNDIR}/${TRIAL}/start_dev_shm
    echo "echo '=== Setting up directories...'" >> ${RUNDIR}/${TRIAL}/start_dev_shm
    echo "rm -Rf ${RUNDIR}/${TRIAL}" >> ${RUNDIR}/${TRIAL}/start_dev_shm
    echo "mkdir -p ${RUNDIR}/${TRIAL}/data ${RUNDIR}/${TRIAL}/tmp ${RUNDIR}/${TRIAL}/log" >> ${RUNDIR}/${TRIAL}/start_dev_shm
    echo "cp -R ./data/* ${RUNDIR}/${TRIAL}/data  # Copy the servers current (crashed/ended state) data directory" >> ${RUNDIR}/${TRIAL}/start_dev_shm
    echo "#echo '=== Data dir init (only use when doing option startup testing)...'" >> ${RUNDIR}/${TRIAL}/start_dev_shm
    echo "#${BIN} --no-defaults --initialize-insecure --basedir=${BASEDIR} --datadir=${RUNDIR}/${TRIAL}/data --tmpdir=${RUNDIR}/${TRIAL}/tmp --core-file --port=$PORT --pid_file=${RUNDIR}/${TRIAL}/pid.pid --socket=${SOCKET} --log-output=none --log-error=${RUNDIR}/${TRIAL}/log/master.err" | sed 's|[ \t]\+| |g' >> ${RUNDIR}/${TRIAL}/start_dev_shm
    echo "echo '=== Starting mysqld...'" >> ${RUNDIR}/${TRIAL}/start_dev_shm
    echo "${CMD} > ${RUNDIR}/${TRIAL}/log/master.err 2>&1" >> ${RUNDIR}/${TRIAL}/start_dev_shm
    if [ "${MYEXTRA}" != "" ]; then
      echo "# Same startup command, but without MYEXTRA included:" >> ${RUNDIR}/${TRIAL}/start_dev_shm
      echo "#$(echo ${CMD} | sed "s|${MYEXTRA}||") > ${RUNDIR}/${TRIAL}/log/master.err 2>&1" >> ${RUNDIR}/${TRIAL}/start_dev_shm
    fi
    if [ "${MYSAFE}" != "" ]; then
      if [ "${MYEXTRA}" != "" ]; then
        echo "# Same startup command, but without MYEXTRA and MYSAFE included:" >> ${RUNDIR}/${TRIAL}/start_dev_shm
        echo "#$(echo ${CMD} | sed "s|${MYEXTRA}||;s|${MYSAFE}||") > ${RUNDIR}/${TRIAL}/log/master.err 2>&1" >> ${RUNDIR}/${TRIAL}/start_dev_shm
      else
        echo "# Same startup command, but without MYSAFE included (and MYEXTRA was already empty):" >> ${RUNDIR}/${TRIAL}/start_dev_shm
        echo "#$(echo ${CMD} | sed "s|${MYSAFE}||") > ${RUNDIR}/${TRIAL}/log/master.err 2>&1" >> ${RUNDIR}/${TRIAL}/start_dev_shm
      fi
    fi
    chmod +x ${RUNDIR}/${TRIAL}/start_dev_shm
    CLBIN="$(echo "${BIN}" | sed 's|/mysqld|/mysql|')"
    echo "${CLBIN} --socket=${SOCKET} -uroot" > ${RUNDIR}/${TRIAL}/cl_dev_shm
    chmod +x ${RUNDIR}/${TRIAL}/cl_dev_shm
    cat ${RUNDIR}/${TRIAL}/cl_dev_shm | sed "s|/dev/shm|/data|" > ${RUNDIR}/${TRIAL}/cl
    chmod +x ${RUNDIR}/${TRIAL}/cl
    echo "${CLBIN}admin --socket=$(echo "${SOCKET}" sed "s|/dev/shm|/data|") -uroot shutdown" > ${RUNDIR}/${TRIAL}/stop
    echo "${CLBIN}admin --socket=${SOCKET} -uroot shutdown" > ${RUNDIR}/${TRIAL}/stop_dev_shm
    chmod +x ${RUNDIR}/${TRIAL}/stop ${RUNDIR}/${TRIAL}/stop_dev_shm
    echo "grep -o 'port=[0-9]\\+' start | sed 's|port=||' | xargs -I{} echo \"ps -ef | grep '{}'\" | xargs -I{} bash -c \"{}\" | grep \"\${PWD}\" | awk '{print \$2}' | xargs kill -9" > ${RUNDIR}/${TRIAL}/kill
    chmod +x ${RUNDIR}/${TRIAL}/kill
    ACCMD="$(echo "set +H; ${CLBIN} --socket=${SOCKET} -uroot --batch --force -A -e 'SELECT CONCAT(\"ALTER TABLE \`\",TABLE_SCHEMA,\".\",TABLE_NAME,\"\` ENGINE=THEENGINEDUMMY;\") FROM information_schema.TABLES WHERE TABLE_SCHEMA=\"test\"' | sed 's|\`test.|\`|' | xargs -I{} echo \"echo '{}'; echo '{}' | ${CLBIN} --socket=${SOCKET} -uroot --force --binary-mode -A test | tee -a alter_test.txt\" | xargs -0 -I{} bash -c \"{}\"" | sed "s|/dev/shm|/data|g")"
    echo "${ACCMD}" | sed 's|THEENGINEDUMMY|InnoDB|g' > ${RUNDIR}/${TRIAL}/alter_tables_to_innodb_test
    echo "${ACCMD}" | sed 's|THEENGINEDUMMY|MyISAM|g' > ${RUNDIR}/${TRIAL}/alter_tables_to_myisam_test
    echo "${ACCMD}" | sed 's|THEENGINEDUMMY|Memory|g' > ${RUNDIR}/${TRIAL}/alter_tables_to_memory_test
    echo "${ACCMD}" | sed 's|THEENGINEDUMMY|Aria|g'   > ${RUNDIR}/${TRIAL}/alter_tables_to_aria_test
    chmod +x ${RUNDIR}/${TRIAL}/alter_tables*
    echo "${ACCMD}" | sed 's|ALTER TABLE|CHECK TABLE|g;s| ENGINE=THEENGINEDUMMY||g;' > ${RUNDIR}/${TRIAL}/check_tables
    echo "${ACCMD}" | sed 's|ALTER TABLE|CHECK TABLE|g;s| QUICK||g;' > ${RUNDIR}/${TRIAL}/check_tables_quick
    ACCMD=
    chmod +x ${RUNDIR}/${TRIAL}/check_tables*
    MCCMD="set +H; ${CLBIN}check --socket=${SOCKET} -uroot --force --check --extended --flush --databases test 2>&1 | grep --binary-files=text -v ' OK$' | sed 's|^test|DBREPLDUMMY1|g' | tr '\\n' ' ' | sed 's|DBREPLDUMMY1|\\ntest|g' | grep  --binary-files=text -v \"The storage engine for the table doesn't support check\" | grep -v '^[ \\t]*$' | sed \"s|^|\${PWD}:|;s|[ ]\\+| |g;s| : |: |g\""
    CLBIN=
    echo "${MCCMD}" > ${RUNDIR}/${TRIAL}/mysqlcheck_test
    echo "${MCCMD}" | sed 's|\-\-check |--check-upgrade |' > ${RUNDIR}/${TRIAL}/mysqlcheck_upg_test
    MCCMD=
    chmod +x ${RUNDIR}/${TRIAL}/mysqlcheck_*
    echo "# Recovery testing script." > ${RUNDIR}/${TRIAL}/start_recovery
    echo "# This script creates an all-privileges recovery@'%' user; ref recovery-user.sql in the wordir (no the trial dir))" >> ${RUNDIR}/${TRIAL}/start_recovery
    echo "# It thens brings up the server for a crash recovery test." >> ${RUNDIR}/${TRIAL}/start_recovery
    echo "BASEDIR=$BASEDIR" >> ${RUNDIR}/${TRIAL}/start_recovery
    echo "if [ ! -r ${WORKDIR}/${TRIAL}/log/master.original.err ]; then" >> ${RUNDIR}/${TRIAL}/start_recovery
    echo "  cp ${WORKDIR}/${TRIAL}/log/master.err ${WORKDIR}/${TRIAL}/log/master.original.err" >> ${RUNDIR}/${TRIAL}/start_recovery
    echo "fi" >> ${RUNDIR}/${TRIAL}/start_recovery
    echo "if [ ! -d ./data.original ]; then" >> ${RUNDIR}/${TRIAL}/start_recovery
    echo "  cp -r ./data ./data.original" >> ${RUNDIR}/${TRIAL}/start_recovery
    echo "fi" >> ${RUNDIR}/${TRIAL}/start_recovery
    echo "${CMD//$RUNDIR/${WORKDIR}} --init-file=${WORKDIR}/recovery-user.sql > ${WORKDIR}/${TRIAL}/log/master.err 2>&1 &" | sed 's|[ \t]\+| |g'  >> ${RUNDIR}/${TRIAL}/start_recovery
    chmod +x ${RUNDIR}/${TRIAL}/start_recovery
    cat ${RUNDIR}/${TRIAL}/start_recovery | sed 's|/recovery-user.sql|/root-access.sql|g' > ${RUNDIR}/${TRIAL}/start
    chmod +x ${RUNDIR}/${TRIAL}/start
    echo "${RUNDIR}/${TRIAL}/start" > ${RUNDIR}/${TRIAL}/all
    echo "${RUNDIR}/${TRIAL}/cl" >> ${RUNDIR}/${TRIAL}/all
    chmod +x ${RUNDIR}/${TRIAL}/all
    echo "${RUNDIR}/${TRIAL}/start_dev_shm" > ${RUNDIR}/${TRIAL}/all_dev_shm
    echo "${RUNDIR}/${TRIAL}/cl_dev_shm" >> ${RUNDIR}/${TRIAL}/all_dev_shm
    chmod +x ${RUNDIR}/${TRIAL}/all_dev_shm
    # New MYEXTRA/MYSAFE variables pass & VALGRIND run check method as of 2015-07-28 (MYSAFE & MYEXTRA stored in a text file inside the trial dir, VALGRIND file created if used)
    if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 ]; then
      echo "${MYSAFE} ${MYEXTRA}" > ${RUNDIR}/${TRIAL}/MYEXTRA.left # When changing this, also search for/edit other '\.left' and '\.right' occurences in this file
      echo "${MYSAFE} ${MYEXTRA2}" > ${RUNDIR}/${TRIAL}/MYEXTRA.right
    else
      echo "${MYSAFE} ${MYEXTRA}" > ${RUNDIR}/${TRIAL}/MYEXTRA
    fi
    echo "${MYINIT}" > ${RUNDIR}/${TRIAL}/MYINIT
    if [ "${VALGRIND_RUN}" == "1" ]; then
      touch ${RUNDIR}/${TRIAL}/VALGRIND
    fi
    # Restore orignal MYEXTRA for the next trial (MYEXTRA is no longer needed anywhere else. If this changes in the future, relocate this to below the changed code)
    MYEXTRA=${MYEXTRA_SAVE_IT}
    # Give up to x (start timeout) seconds for mysqld to start, but check intelligently for known startup issues like "Error while setting value" for options
    if [ "${VALGRIND_RUN}" == "0" ]; then
      echoit "Waiting for mysqld (pid: ${MPID}) to fully start..."
      if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 ]; then
        echoit "Waiting for mysqld (pid: ${MPID2}) to fully start..."
      fi
    else
      echoit "Waiting for mysqld (pid: ${MPID}) to fully start (note this is slow for Valgrind runs, and can easily take 35-90 seconds even on an high end server)..."
      if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 ]; then
        echoit "Waiting for mysqld (pid: ${MPID2}) to fully start (note this is slow for Valgrind runs, and can easily take 35-90 seconds even on an high end server)..."
      fi
    fi
    FAILEDSTARTABORT=0
    for X in $(seq 0 ${MYSQLD_START_TIMEOUT}); do
      sleep 1
      if ${BASEDIR}/bin/mysqladmin -uroot -S${SOCKET} ping > /dev/null 2>&1; then
        if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 ]; then
          if ${BASEDIR}/bin/mysqladmin -uroot -S${RUNDIR}/${TRIAL}/socket2.sock ping > /dev/null 2>&1; then
            break
          fi
        else
          if [[ ${REPL} -eq 1 ]]; then
            if ${BASEDIR}/bin/mysqladmin -uroot -S${SLAVE_SOCKET} ping > /dev/null 2>&1; then
              break
            fi
          else
            break
          fi
        fi
      fi
      if [ "${MPID}" == "" ]; then
        echoit "Assert! ${MPID} empty. Terminating!"
        exit 1
      fi
      if [[ ${SLAVE_MPID} -eq 1 ]]; then
        echoit "Assert! ${SLAVE_MPID} empty. Slave is not running. Terminating!"
        exit 1
      fi
      if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 ]; then
        if [ "${MPID2}" == "" ]; then
          echoit "Assert! ${MPID2} empty. Terminating!"
          exit 1
        fi
      fi
      if grep -qi "Can.t create.write to file" ${RUNDIR}/${TRIAL}/log/master.err; then
        echoit "Assert! Likely an incorrect --init-file option was specified (check if the specified file actually exists)"  # Also see https://jira.mariadb.org/browse/MDEV-27232
        echoit "Terminating run as there is no point in continuing; all trials will fail with this error."
        removetrial
        exit 1
      elif grep -qi "ERROR. Aborting" ${RUNDIR}/${TRIAL}/log/master.err; then
        if grep -qi "TCP.IP port.*Address already in use" ${RUNDIR}/${TRIAL}/log/master.err; then
          echoit "Assert! The text '[ERROR] Aborting' was found in the error log due to a IP port conflict (the port was already in use)"
          removetrial
        else
          if [ ${ADD_RANDOM_OPTIONS} -eq 0 ]; then # Halt for ADD_RANDOM_OPTIONS=0 runs, they should not produce errors like these, as MYEXTRA should be high-quality/non-faulty
            if grep -qi "Can't initialize timers" ${RUNDIR}/${TRIAL}/log/master.err; then
              echoit "Error! '[ERROR] Aborting' was found in the error log, due to a 'Can't initialize timers' issue, ref https://jira.mariadb.org/browse/MDEV-22286, currently being researched. The run should be able to continue normally. Not saving trial."
              removetrial
            else
              echoit "Assert! '[ERROR] Aborting' was found in the error log. This is likely an issue with one of the \$MEXTRA (or \$MYSAFE) startup parameters. Saving trial for further analysis, and dumping error log here for quick analysis. Please check the output against the \$MYEXTRA (or \$MYSAFE if it was modified) settings. You may also want to try setting \$MYEXTRA=\"${MYEXTRA}\" directly in start (as created by startup.sh using your base directory)."
              grep "ERROR" ${RUNDIR}/${TRIAL}/log/master.err | tee -a /${WORKDIR}/pquery-run.log
              if grep -qi "Could not open mysql.plugin" $ERROR_LOG; then  # Likely OOS on /dev/shm
                echoit "Found 'Could not open mysql.plugin' in error log, likely OOS on ${RUNDIR} or in /tmp or root (/). Removing trial to maximize space, and pausing 0.5 hour before trying again (reducer's may be running and consuming space)"
                removetrial
                sleep 1800
                echoit "Slept 0.5h, resuming pquery-run.sh run..."
              else
                savetrial
                echoit "Remember to cleanup/delete the rundir:  rm -Rf ${RUNDIR}"
                exit 1
              fi
            fi
          else # Do not halt for ADD_RANDOM_OPTIONS=1 runs, they are likely to produce errors like these as MYEXTRA was randomly changed
            echoit "'[ERROR] Aborting' was found in the error log. This is likely an issue with one of the MYEXTRA startup parameters. As ADD_RANDOM_OPTIONS=1, this is likely to be encountered. Not saving trial. If you see this error for every trial however, set \$ADD_RANDOM_OPTIONS=0 & try running pquery-run.sh again. If it still fails, your base \$MYEXTRA setting is faulty."
            grep "ERROR" ${RUNDIR}/${TRIAL}/log/master.err | tee -a /${WORKDIR}/pquery-run.log
            FAILEDSTARTABORT=1
            break
          fi
        fi
      fi
      if [ "${REPL}" -eq 1 ]; then
        if grep -qi "Can.t create.write to file" ${RUNDIR}/${TRIAL}/log/master.err; then
          echoit "Assert! Likely an incorrect --init-file option was specified (check if the specified file actually exists)"  # Also see https://jira.mariadb.org/browse/MDEV-27232
          echoit "Terminating run as there is no point in continuing; all trials will fail with this error."
          removetrial
          exit 1
        elif grep -qi "ERROR. Aborting" ${RUNDIR}/${TRIAL}/log/slave.err; then
          echoit "Assert! The text '[ERROR] Aborting' was found in the slave error log"
          removetrial
        fi
      fi
      if [ $(ls -l ${RUNDIR}/${TRIAL}/*/*core* 2> /dev/null | wc -l) -ge 1 ]; then break; fi # Break the wait-for-server-started loop if a core file is found. Handling of core is done below.
    done
    # Check if mysqld is alive and if so, set ISSTARTED=1 so pquery will run
    if ${BASEDIR}/bin/mysqladmin -uroot -S${SOCKET} ping > /dev/null 2>&1; then
      ISSTARTED=1
      if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 ]; then
        echoit "Primary Server started ok. Client: $(echo ${BIN} | sed 's|/mysqld|/mysql|') -uroot -S${SOCKET}"
        if ${BASEDIR}/bin/mysqladmin -uroot -S${RUNDIR}/${TRIAL}/socket2.sock ping > /dev/null 2>&1; then
          echoit "Secondary server started ok. Client: $(echo ${BIN} | sed 's|/mysqld|/mysql|') -uroot -S${SOCKET}"
          ${BASEDIR}/bin/mysql -uroot -S${RUNDIR}/${TRIAL}/socket2.sock -e "CREATE DATABASE IF NOT EXISTS test;" > /dev/null 2>&1
        fi
      else
        echoit "Server started ok. Client: $(echo ${BIN} | sed 's|/mysqld|/mysql|') -uroot -S${SOCKET}"
        ${BASEDIR}/bin/mysql -uroot -S${SOCKET} -e "CREATE DATABASE IF NOT EXISTS test;" > /dev/null 2>&1
      fi
      if [[ ${REPL} -eq 1 ]]; then
        ${BASEDIR}/bin/mysql -uroot -S${SOCKET} -e "DELETE FROM mysql.user WHERE user='';" 2> /dev/null
        ${BASEDIR}/bin/mysql -uroot -S${SOCKET} -e "GRANT REPLICATION SLAVE ON *.* TO 'repl_user'@'%' IDENTIFIED BY 'repl_pass'; FLUSH PRIVILEGES;" 2> /dev/null
        ${BASEDIR}/bin/mysql -uroot -S${SLAVE_SOCKET} -e "CHANGE MASTER TO MASTER_HOST='127.0.0.1', MASTER_PORT=$PORT, MASTER_USER='repl_user', MASTER_PASSWORD='repl_pass', MASTER_USE_GTID=slave_pos ; START SLAVE;" 2> /dev/null
      fi
      if [ "$PMM" == "1" ]; then
        echoit "Adding Orchestrator user for MySQL replication topology management.."
        printf "[client]\nuser=root\nsocket=${SOCKET}\n" |
          ${BASEDIR}/bin/mysql --defaults-file=/dev/stdin -e "GRANT SUPER, PROCESS, REPLICATION SLAVE, RELOAD ON *.* TO 'orc_client_user'@'%' IDENTIFIED BY 'orc_client_password'" 2> /dev/null
        echoit "Starting pmm client for this server..."
        sudo pmm-admin add mysql pq${RANDOMD}-${TRIAL} --socket=${SOCKET} --user=root --query-source=perfschema
      fi
    fi
  elif [[ "${MDG}" == "1" ]]; then
    diskspace
    for i in $(seq 1 ${NR_OF_NODES}); do
      if [[ ${PQUERY3} -eq 1 && ${TRIAL} -gt 1 ]]; then
        mkdir -p ${RUNDIR}/${TRIAL}/
        echoit "Copying datadir from ${WORKDIR}/$((${TRIAL} - 1))/node${i} into ${RUNDIR}/${TRIAL}/node${i} ..."
        cp -R ${WORKDIR}/$((${TRIAL} - 1))/node${i} ${RUNDIR}/${TRIAL}/node${i} 2>&1
        if [ ${i} -eq 1 ]; then
          sed -i 's|safe_to_bootstrap:.*$|safe_to_bootstrap: 1|' ${RUNDIR}/${TRIAL}/node${i}/grastate.dat
        fi
      else
        mkdir -p ${RUNDIR}/${TRIAL}/
        cp -R ${WORKDIR}/node${i}.template ${RUNDIR}/${TRIAL}/node${i} 2>&1
      fi
    done
    MDG_MYEXTRA=
    # === MDG Options Stage 1: Add random mysqld options to MDG_MYEXTRA
    if [ ${MDG_ADD_RANDOM_OPTIONS} -eq 1 ]; then
      OPTIONS_TO_ADD=
      NR_OF_OPTIONS_TO_ADD=$((RANDOM % MDG_MAX_NR_OF_RND_OPTS_TO_ADD + 1))
      for X in $(seq 1 ${NR_OF_OPTIONS_TO_ADD}); do
        OPTION_TO_ADD="$(shuf --random-source=/dev/urandom ${MDG_OPTIONS_INFILE} | head -n1)"
        if [ "$(echo ${OPTION_TO_ADD} | sed 's| ||g;s|.*query.alloc.block.size=1125899906842624.*||')" != "" ]; then # http://bugs.mysql.com/bug.php?id=78238
          OPTIONS_TO_ADD="${OPTIONS_TO_ADD} ${OPTION_TO_ADD}"
        fi
      done
      echoit "MDG_ADD_RANDOM_OPTIONS=1: adding mysqld option(s) ${OPTIONS_TO_ADD} to this run's MDG_MYEXTRA..."
      MDG_MYEXTRA="${OPTIONS_TO_ADD}"
      if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 ]; then
        MYEXTRA2="${MYEXTRA2} ${OPTIONS_TO_ADD}"
      fi
    fi
    # === MDG Options Stage 2: Add random wsrep mysqld options to MDG_MYEXTRA
    if [ ${MDG_WSREP_ADD_RANDOM_WSREP_MYSQLD_OPTIONS} -eq 1 ]; then
      OPTIONS_TO_ADD=
      NR_OF_OPTIONS_TO_ADD=$((RANDOM % MDG_WSREP_MAX_NR_OF_RND_OPTS_TO_ADD + 1))
      for X in $(seq 1 ${NR_OF_OPTIONS_TO_ADD}); do
        OPTION_TO_ADD="$(shuf --random-source=/dev/urandom ${MDG_WSREP_OPTIONS_INFILE} | head -n1)"
        OPTIONS_TO_ADD="${OPTIONS_TO_ADD} ${OPTION_TO_ADD}"
      done
      echoit "MDG_WSREP_ADD_RANDOM_WSREP_MYSQLD_OPTIONS=1: adding wsrep provider mysqld option(s) ${OPTIONS_TO_ADD} to this run's MDG_MYEXTRA..."
      MDG_MYEXTRA="${MDG_MYEXTRA} ${OPTIONS_TO_ADD}"
    fi
    # === MDG Options Stage 3: Add random wsrep (Galera) configuration options
    if [ ${MDG_WSREP_PROVIDER_ADD_RANDOM_WSREP_PROVIDER_CONFIG_OPTIONS} -eq 1 ]; then
      OPTIONS_TO_ADD=
      NR_OF_OPTIONS_TO_ADD=$((RANDOM % MDG_WSREP_PROVIDER_MAX_NR_OF_RND_OPTS_TO_ADD + 1))
      for X in $(seq 1 ${NR_OF_OPTIONS_TO_ADD}); do
        OPTION_TO_ADD="$(shuf --random-source=/dev/urandom ${MDG_WSREP_PROVIDER_OPTIONS_INFILE} | head -n1)"
        OPTIONS_TO_ADD="${OPTION_TO_ADD};${OPTIONS_TO_ADD}"
      done
      echoit "MDG_WSREP_PROVIDER_ADD_RANDOM_WSREP_PROVIDER_CONFIG_OPTIONS=1: adding wsrep provider configuration option(s) ${OPTIONS_TO_ADD} to this run..."
      WSREP_PROVIDER_OPT="$OPTIONS_TO_ADD"
    fi
    echo "${MYEXTRA} ${MDG_MYEXTRA}" > ${RUNDIR}/${TRIAL}/MYEXTRA
    echo "${MYINIT}" > ${RUNDIR}/${TRIAL}/MYINIT
    echo "$WSREP_PROVIDER_OPT" > ${RUNDIR}/${TRIAL}/WSREP_PROVIDER_OPT
    if [ "${VALGRIND_RUN}" == "1" ]; then
      touch ${RUNDIR}/${TRIAL}/VALGRIND
      echoit "Waiting for all MDG nodes to fully start (note this is slow for Valgrind runs, and can easily take 90-180 seconds even on an high end server)..."
    fi
    mdg_startup
    echoit "Checking ${NR_OF_NODES} node MDG Cluster startup..."
    CLUSTER_UP=0
    for i in $(seq 1 ${NR_OF_NODES}); do
      sleep 1
      if [ "$(${BASEDIR}/bin/mysql -uroot -S${RUNDIR}/${TRIAL}/node${i}/node${i}_socket.sock -e"show global status like 'wsrep_local_state_comment'" | sed 's/[| \t]\+/\t/g' | grep "wsrep_local" | awk '{print $2}')" == "Synced" ]; then CLUSTER_UP=$((${CLUSTER_UP} + 1)); fi
    done
    if [ ${CLUSTER_UP} -eq ${NR_OF_NODES} ]; then
      ISSTARTED=1
      for i in $(seq 1 ${NR_OF_NODES}); do
        echoit "${NR_OF_NODES} Node MDG Cluster started ok. Clients:"
        echoit "Node #${i}: $(echo ${BIN} | sed 's|/mysqld|/mysql|') -uroot -S${RUNDIR}/${TRIAL}/node${i}/node${i}_socket.sock"
      done
    fi
  elif [[ ${GRP_RPL} -eq 1 ]]; then
    diskspace
    mkdir -p ${RUNDIR}/${TRIAL}/
    cp -R ${WORKDIR}/node1.template ${RUNDIR}/${TRIAL}/node1 2>&1
    cp -R ${WORKDIR}/node2.template ${RUNDIR}/${TRIAL}/node2 2>&1
    cp -R ${WORKDIR}/node3.template ${RUNDIR}/${TRIAL}/node3 2>&1
    gr_startup

    CLUSTER_UP=0
    if [ $(${BASEDIR}/bin/mysql -uroot -S${SOCKET1} -Bse"select count(1) from performance_schema.replication_group_members where member_state='ONLINE'") -eq 3 ]; then CLUSTER_UP=$((${CLUSTER_UP} + 1)); fi
    if [ $(${BASEDIR}/bin/mysql -uroot -S${SOCKET2} -Bse"select count(1) from performance_schema.replication_group_members where member_state='ONLINE'") -eq 3 ]; then CLUSTER_UP=$((${CLUSTER_UP} + 1)); fi
    if [ $(${BASEDIR}/bin/mysql -uroot -S${SOCKET3} -Bse"select count(1) from performance_schema.replication_group_members where member_state='ONLINE'") -eq 3 ]; then CLUSTER_UP=$((${CLUSTER_UP} + 1)); fi

    # If count reached 3, then the Cluster is up & running and consistent in it's Cluster topology views (as seen by each node)
    if [ ${CLUSTER_UP} -eq 3 ]; then
      ISSTARTED=1
      echoit "3 Node Group Replication Cluster started ok. Clients:"
      echoit "Node #1: $(echo ${BIN} | sed 's|/mysqld|/mysql|') -uroot -S${SOCKET1}"
      echoit "Node #2: $(echo ${BIN} | sed 's|/mysqld|/mysql|') -uroot -S${SOCKET2}"
      echoit "Node #3: $(echo ${BIN} | sed 's|/mysqld|/mysql|') -uroot -S${SOCKET3}"
    fi
  fi

  if [ ${ISSTARTED} -eq 1 ]; then
    rm -f ${RUNDIR}/${TRIAL}/startup_failure_thread-0.sql # Remove the earlier created fake (SELECT 1; only) file present for startup issues (server is started OK now)
    if [ ${THREADS} -eq 1 ]; then                       # Single-threaded run (1 client only)
      if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 ]; then   # Single-threaded query correctness run using a chunk from INFILE against two servers to then compare outcomes
        echoit "Taking ${QC_NR_OF_STATEMENTS_PER_TRIAL} lines randomly from ${INFILE} as testcase for this query correctness trial..."
        # Make sure that the code below generates exactly 3 lines (DROP/CREATE/USE) -OR- change the "head -n3" and "sed '1,3d'" (both below) to match any updates made
        echo 'DROP DATABASE test;' > ${RUNDIR}/${TRIAL}/${TRIAL}.sql
        if [ "$(echo ${QC_PRI_ENGINE} | tr [:upper:] [:lower:])" == "rocksdb" -o "$(echo ${QC_SEC_ENGINE} | tr [:upper:] [:lower:])" == "rocksdb" ]; then
          case "$(echo $((RANDOM % 4 + 1)))" in
            1) echo 'CREATE DATABASE test DEFAULT CHARACTER SET="Binary" DEFAULT COLLATE="Binary";' >> ${RUNDIR}/${TRIAL}/${TRIAL}.sql ;;
            2) echo 'CREATE DATABASE test DEFAULT CHARACTER SET="utf8" DEFAULT COLLATE="utf8_bin";' >> ${RUNDIR}/${TRIAL}/${TRIAL}.sql ;;
            3) echo 'CREATE DATABASE test DEFAULT CHARACTER SET="latin1" DEFAULT COLLATE="latin1_bin";' >> ${RUNDIR}/${TRIAL}/${TRIAL}.sql ;;
            4) echo 'CREATE DATABASE test DEFAULT CHARACTER SET="utf8mb4" DEFAULT COLLATE="utf8mb4_bin";' >> ${RUNDIR}/${TRIAL}/${TRIAL}.sql ;;
          esac
        else
          echo 'CREATE DATABASE test;' >> ${RUNDIR}/${TRIAL}/${TRIAL}.sql
        fi
        echo 'USE test;' >> ${RUNDIR}/${TRIAL}/${TRIAL}.sql
        shuf --random-source=/dev/urandom ${INFILE} | head -n${QC_NR_OF_STATEMENTS_PER_TRIAL} >> ${RUNDIR}/${TRIAL}/${TRIAL}.sql
        awk -v seed=$RANDOM 'BEGIN{srand();} {ORS="#@"int(999999999*rand())"\n"} {print $0}' ${RUNDIR}/${TRIAL}/${TRIAL}.sql > ${RUNDIR}/${TRIAL}/${TRIAL}.new
        rm -f ${RUNDIR}/${TRIAL}/${TRIAL}.sql && mv ${RUNDIR}/${TRIAL}/${TRIAL}.new ${RUNDIR}/${TRIAL}/${TRIAL}.sql 2>&1 | tee -a /${WORKDIR}/pquery-run.log
        echoit "Further processing testcase into two testcases against primary (${QC_PRI_ENGINE}) and secondary (${QC_SEC_ENGINE}) engines..."
        if [ "$(echo ${QC_PRI_ENGINE} | tr [:upper:] [:lower:])" == "rocksdb" -o "$(echo ${QC_SEC_ENGINE} | tr [:upper:] [:lower:])" == "rocksdb" ]; then
          head -n3 ${RUNDIR}/${TRIAL}/${TRIAL}.sql > ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_PRI_ENGINE} # Setup testcase with DROP/CREATE/USE test db
          sed '1,3d' ${RUNDIR}/${TRIAL}/${TRIAL}.sql |
            sed 's|FOREIGN[ \t]\+KEY||i' |
            sed 's|FULLTEXT||i' |
            sed 's|VIRTUAL||i' |
            sed 's|[ \t]\+TEMPORARY||i' |
            sed -E 's/row_format.*=.*(;| )+//i' |
            grep -vi "variables" |
            grep -vi "\@\@" |
            grep -viE "show[ \t]+" |
            grep -viE "analyze[ \t]+" |
            grep -viE "optimize[ \t]+" |
            grep -vi "information_schema" |
            grep -vi "performance_schema" |
            grep -viE "check[ \t]+" |
            grep -viE "repair[ \t]+" |
            grep -viE "explain[ \t]+" |
            grep -vi "point" |
            grep -vi "geometry" |
            grep -vi "linestring" |
            grep -vi "polygon" |
            grep -vi "unique" |
            grep -vi "rand" |
            grep -vi "uuid" |
            grep -vi "charset" |
            grep -vi "character" |
            grep -vi "collate" |
            grep -vi "db_row_id" |
            grep -vi "db_trx_id" |
            grep -vi "gen_clust_index" |
            grep -vi "current_time" |
            grep -vi "curtime" |
            grep -vi "timestamp" |
            grep -vi "localtime" |
            grep -vi "utc_time" |
            grep -vi "connection_id" |
            grep -vi "sysdate" |
            grep -vEi "now[ \t]*\(.{0,4}\)" |
            grep -vi "flush.*for[ \t]*export" |
            grep -vi "encrypt[ \t]*(.*)" |
            grep -vi "compression_dictionary" |
            grep -vi "start transaction .*with consistent snapshot" |
            grep -vi "limit rows examined" |
            grep -vi "set .*read[ -]uncommitted" |
            grep -vi "set .*serializable" |
            grep -vi "set .*binlog_format" |
            grep -vi "max_join_size" |
            grep -vi "^create table.*unicode" |
            grep -vi "^create table.*tablespace" |
            grep -viE "^(create table|alter table).*column_format.*compressed" |
            grep -vi "^create table.*generated" |
            grep -vi "^create table.*/tmp/not-existing" |
            grep -vi "^create table.*compression" |
            grep -viE "^create( temporary)?.*table.*key_block_size" |
            grep -vi "^create table.*encryption" |
            grep -viE "^(create table|alter table).*comment.*__system__" |
            grep -vi "^select.* sys\." |
            grep -vi "^select.* mysql\." |
            grep -vi "^call.* sys\." |
            grep -vi "^use " |
            grep -vi "^describe" |
            grep -vi "password[ \t]*(.*)" |
            grep -vi "old_password[ \t]*(.*)" |
            grep -vi "row_count[ \t]*(.*)" |
            grep -vi "^handler" |
            grep -vi "^lock.*for backup" |
            grep -vi "^uninstall.*plugin" |
            grep -vi "^alter table.*algorithm.*inplace" |
            grep -vi "^set.*innodb_encrypt_tables" |
            grep -vi "^insert.*into.*select.*from" |
            grep -vi "^alter table.*discard tablespace" >> ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_PRI_ENGINE}
          cp ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_PRI_ENGINE} ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_SEC_ENGINE}
        elif [ "$(echo ${QC_PRI_ENGINE} | tr [:upper:] [:lower:])" == "tokudb" -o "$(echo ${QC_SEC_ENGINE} | tr [:upper:] [:lower:])" == "tokudb" ]; then
          head -n3 ${RUNDIR}/${TRIAL}/${TRIAL}.sql > ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_PRI_ENGINE} # Setup testcase with DROP/CREATE/USE test db
          sed '1,3d' ${RUNDIR}/${TRIAL}/${TRIAL}.sql |
            sed 's|FOREIGN[ \t]\+KEY||i' |
            sed 's|FULLTEXT||i' |
            sed 's|VIRTUAL||i' |
            sed 's|CLUSTERING||i' |
            sed -E 's/row_format.*=.*(;| )+//i' |
            grep -vi "variables" |
            grep -vi "\@\@" |
            grep -viE "show[ \t]+" |
            grep -viE "analyze[ \t]+" |
            grep -viE "optimize[ \t]+" |
            grep -vi "information_schema" |
            grep -vi "performance_schema" |
            grep -viE "check[ \t]+" |
            grep -viE "repair[ \t]+" |
            grep -viE "explain[ \t]+" |
            grep -vi "point" |
            grep -vi "geometry" |
            grep -vi "linestring" |
            grep -vi "polygon" |
            grep -vi "rand" |
            grep -vi "uuid" |
            grep -vi "db_row_id" |
            grep -vi "db_trx_id" |
            grep -vi "gen_clust_index" |
            grep -vi "current_time" |
            grep -vi "curtime" |
            grep -vi "timestamp" |
            grep -vi "localtime" |
            grep -vi "utc_time" |
            grep -vi "connection_id" |
            grep -vi "sysdate" |
            grep -vEi "now[ \t]*\(.{0,4}\)" |
            grep -vi "flush.*for[ \t]*export" |
            grep -vi "encrypt[ \t]*(.*)" |
            grep -vi "compression_dictionary" |
            grep -vi "limit rows examined" |
            grep -vi "max_join_size" |
            grep -vi "^create table.*tablespace" |
            grep -viE "^(create table|alter table).*column_format.*compressed" |
            grep -vi "^create table.*generated" |
            grep -vi "^create table.*/tmp/not-existing" |
            grep -vi "^create table.*compression" |
            grep -viE "^create( temporary)?.*table.*key_block_size" |
            grep -vi "^create table.*encryption" |
            grep -vi "^select.* sys\." |
            grep -vi "^select.* mysql\." |
            grep -vi "^call.* sys\." |
            grep -vi "^use " |
            grep -vi "^describe" |
            grep -vi "password[ \t]*(.*)" |
            grep -vi "old_password[ \t]*(.*)" |
            grep -vi "row_count[ \t]*(.*)" |
            grep -vi "^alter table.*algorithm.*inplace" |
            grep -vi "^set.*innodb_encrypt_tables" |
            grep -vi "^uninstall.*plugin" >> ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_PRI_ENGINE}
          cp ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_PRI_ENGINE} ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_SEC_ENGINE}
        else
          cp ${RUNDIR}/${TRIAL}/${TRIAL}.sql ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_PRI_ENGINE}
          cp ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_PRI_ENGINE} ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_SEC_ENGINE}
        fi
        sed -i "s|innodb|${QC_PRI_ENGINE}|gi" ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_PRI_ENGINE}
        sed -i "s|innodb|${QC_SEC_ENGINE}|gi" ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_SEC_ENGINE}
        sed -i "s|tokudb|${QC_PRI_ENGINE}|gi" ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_PRI_ENGINE}
        sed -i "s|tokudb|${QC_SEC_ENGINE}|gi" ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_SEC_ENGINE}
        sed -i "s|rocksdb|${QC_PRI_ENGINE}|gi" ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_PRI_ENGINE}
        sed -i "s|rocksdb|${QC_SEC_ENGINE}|gi" ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_SEC_ENGINE}
        sed -i "s|myisam|${QC_PRI_ENGINE}|gi" ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_PRI_ENGINE}
        sed -i "s|myisam|${QC_SEC_ENGINE}|gi" ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_SEC_ENGINE}
        sed -i "s|memory|${QC_PRI_ENGINE}|gi" ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_PRI_ENGINE}
        sed -i "s|memory|${QC_SEC_ENGINE}|gi" ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_SEC_ENGINE}
        sed -i "s|merge|${QC_PRI_ENGINE}|gi" ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_PRI_ENGINE}
        sed -i "s|merge|${QC_SEC_ENGINE}|gi" ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_SEC_ENGINE}
        sed -i "s|csv|${QC_PRI_ENGINE}|gi" ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_PRI_ENGINE}
        sed -i "s|csv|${QC_SEC_ENGINE}|gi" ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_SEC_ENGINE}
        sed -i "s|[m]aria|${QC_PRI_ENGINE}|gi" ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_PRI_ENGINE}
        sed -i "s|[m]aria|${QC_SEC_ENGINE}|gi" ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_SEC_ENGINE}
        sed -i "s|heap|${QC_PRI_ENGINE}|gi" ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_PRI_ENGINE}
        sed -i "s|heap|${QC_SEC_ENGINE}|gi" ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_SEC_ENGINE}
        sed -i "s|federated|${QC_PRI_ENGINE}|gi" ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_PRI_ENGINE}
        sed -i "s|federated|${QC_SEC_ENGINE}|gi" ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_SEC_ENGINE}
        sed -i "s|archive|${QC_PRI_ENGINE}|gi" ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_PRI_ENGINE}
        sed -i "s|archive|${QC_SEC_ENGINE}|gi" ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_SEC_ENGINE}
        sed -i "s|mrg_myisam|${QC_PRI_ENGINE}|gi" ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_PRI_ENGINE}
        sed -i "s|mrg_myisam|${QC_SEC_ENGINE}|gi" ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_SEC_ENGINE}
        sed -i "s|cassandra|${QC_PRI_ENGINE}|gi" ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_PRI_ENGINE}
        sed -i "s|cassandra|${QC_SEC_ENGINE}|gi" ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_SEC_ENGINE}
        sed -i "s|ndb|${QC_PRI_ENGINE}|gi" ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_PRI_ENGINE}
        sed -i "s|ndb|${QC_SEC_ENGINE}|gi" ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_SEC_ENGINE}
        sed -i "s|ndbcluster|${QC_PRI_ENGINE}|gi" ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_PRI_ENGINE}
        sed -i "s|ndbcluster|${QC_SEC_ENGINE}|gi" ${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_SEC_ENGINE}
        SQL_FILE_1="--infile=${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_PRI_ENGINE}"
        SQL_FILE_2="--infile=${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_SEC_ENGINE}"
        if [[ ${MDG} -eq 0 && ${GRP_RPL} -eq 0 ]]; then
          echoit "Starting Primary pquery run for engine ${QC_PRI_ENGINE} (log stored in ${RUNDIR}/${TRIAL}/pquery1.log)..."
          if [ ${QUERY_CORRECTNESS_MODE} -ne 2 ]; then
            ${PQUERY_BIN} ${SQL_FILE_1} --threads=${THREADS} --queries-per-thread=${QUERIES_PER_THREAD} --logdir=${RUNDIR}/${TRIAL} --log-all-queries --log-failed-queries --no-shuffle --log-query-statistics --user=root --socket=${SOCKET} > ${RUNDIR}/${TRIAL}/pquery1.log 2>&1
            PQPID="$!"
            mv ${RUNDIR}/${TRIAL}/pquery_thread-0.sql ${RUNDIR}/${TRIAL}/pquery_thread-0.${QC_PRI_ENGINE}.sql 2>&1 | tee -a /${WORKDIR}/pquery-run.log
            mv ${RUNDIR}/${TRIAL}/pquery_thread-0.out ${RUNDIR}/${TRIAL}/pquery_thread-0.${QC_PRI_ENGINE}.out 2>&1 | tee -a /${WORKDIR}/pquery-run.log
          else
            ${PQUERY_BIN} ${SQL_FILE_1} --threads=${THREADS} --queries-per-thread=${QUERIES_PER_THREAD} --logdir=${RUNDIR}/${TRIAL} --log-all-queries --log-failed-queries --no-shuffle --log-query-statistics --log-client-output --user=root --log-query-number --socket=${SOCKET} > ${RUNDIR}/${TRIAL}/pquery1.log 2>&1
            PQPID="$!"
            mv ${RUNDIR}/${TRIAL}/default.node.tld_thread-0.sql ${RUNDIR}/${TRIAL}/pquery_thread-0.${QC_PRI_ENGINE}.sql 2>&1 | tee -a /${WORKDIR}/pquery-run.log
            mv ${RUNDIR}/${TRIAL}/default.node.tld_thread-0.out ${RUNDIR}/${TRIAL}/pquery_thread-0.${QC_PRI_ENGINE}.out 2>&1 | tee -a /${WORKDIR}/pquery-run.log
          fi
          echoit "Starting Secondary pquery run for engine ${QC_SEC_ENGINE} (log stored in ${RUNDIR}/${TRIAL}/pquery2.log)..."
          if [ ${QUERY_CORRECTNESS_MODE} -ne 2 ]; then
            ${PQUERY_BIN} ${SQL_FILE_2} --threads=${THREADS} --queries-per-thread=${QUERIES_PER_THREAD} --logdir=${RUNDIR}/${TRIAL} --log-all-queries --log-failed-queries --no-shuffle --log-query-statistics --user=root --socket=${RUNDIR}/${TRIAL}/socket2.sock > ${RUNDIR}/${TRIAL}/pquery2.log 2>&1
            PQPID2="$!"
            mv ${RUNDIR}/${TRIAL}/pquery_thread-0.sql ${RUNDIR}/${TRIAL}/pquery_thread-0.${QC_SEC_ENGINE}.sql 2>&1 | tee -a /${WORKDIR}/pquery-run.log
            mv ${RUNDIR}/${TRIAL}/pquery_thread-0.out ${RUNDIR}/${TRIAL}/pquery_thread-0.${QC_SEC_ENGINE}.out 2>&1 | tee -a /${WORKDIR}/pquery-run.log
            grep -o "CHANGED: [0-9]\+" ${RUNDIR}/${TRIAL}/pquery_thread-0.${QC_PRI_ENGINE}.sql > ${RUNDIR}/${TRIAL}/${QC_PRI_ENGINE}.result
            grep -o "CHANGED: [0-9]\+" ${RUNDIR}/${TRIAL}/pquery_thread-0.${QC_SEC_ENGINE}.sql > ${RUNDIR}/${TRIAL}/${QC_SEC_ENGINE}.result
          else
            ${PQUERY_BIN} ${SQL_FILE_2} --threads=${THREADS} --queries-per-thread=${QUERIES_PER_THREAD} --logdir=${RUNDIR}/${TRIAL} --log-all-queries --log-failed-queries --no-shuffle --log-query-statistics --log-client-output --user=root --log-query-number --socket=${RUNDIR}/${TRIAL}/socket2.sock > ${RUNDIR}/${TRIAL}/pquery2.log 2>&1
            PQPID2="$!"
            mv ${RUNDIR}/${TRIAL}/default.node.tld_thread-0.sql ${RUNDIR}/${TRIAL}/pquery_thread-0.${QC_SEC_ENGINE}.sql 2>&1 | tee -a /${WORKDIR}/pquery-run.log
            mv ${RUNDIR}/${TRIAL}/default.node.tld_thread-0.out ${RUNDIR}/${TRIAL}/pquery_thread-0.${QC_SEC_ENGINE}.out 2>&1 | tee -a /${WORKDIR}/pquery-run.log
            diff ${RUNDIR}/${TRIAL}/pquery_thread-0.${QC_PRI_ENGINE}.out ${RUNDIR}/${TRIAL}/pquery_thread-0.${QC_SEC_ENGINE}.out > ${RUNDIR}/${TRIAL}/diff.result
            echo "${QC_PRI_ENGINE}" > ${RUNDIR}/${TRIAL}/diff.left # When changing this, also search for/edit other '\.left' and '\.right' occurences in this file
            echo "${QC_SEC_ENGINE}" > ${RUNDIR}/${TRIAL}/diff.right
          fi
        else
          ## TODO: Add QUERY_CORRECTNESS_MODE checks (as seen above) to the code below also. FTM, the code below only does "changed rows" comparison
          echoit "Starting Primary pquery run for engine ${QC_PRI_ENGINE} (log stored in ${RUNDIR}/${TRIAL}/pquery1.log)..."
          ${PQUERY_BIN} ${SQL_FILE_1} --threads=${THREADS} --queries-per-thread=${QUERIES_PER_THREAD} --logdir=${RUNDIR}/${TRIAL} --log-all-queries --log-failed-queries --no-shuffle --log-query-statistics --user=root --socket=${SOCKET1} > ${RUNDIR}/${TRIAL}/pquery1.log 2>&1
          PQPID="$!"
          mv ${RUNDIR}/${TRIAL}/pquery_thread-0.sql ${RUNDIR}/${TRIAL}/pquery_thread-0.${QC_PRI_ENGINE}.sql 2>&1 | tee -a /${WORKDIR}/pquery-run.log
          grep -o "CHANGED: [0-9]\+" ${RUNDIR}/${TRIAL}/pquery_thread-0.${QC_PRI_ENGINE}.sql > ${RUNDIR}/${TRIAL}/${QC_PRI_ENGINE}.result
          echoit "Starting Secondary pquery run for engine ${QC_SEC_ENGINE} (log stored in ${RUNDIR}/${TRIAL}/pquery2.log)..."
          ${PQUERY_BIN} ${SQL_FILE_2} --threads=${THREADS} --queries-per-thread=${QUERIES_PER_THREAD} --logdir=${RUNDIR}/${TRIAL} --log-all-queries --log-failed-queries --no-shuffle --log-query-statistics --user=root --socket=${SOCKET2} > ${RUNDIR}/${TRIAL}/pquery2.log 2>&1
          PQPID2="$!"
          mv ${RUNDIR}/${TRIAL}/pquery_thread-0.sql ${RUNDIR}/${TRIAL}/pquery_thread-0.${QC_SEC_ENGINE}.sql 2>&1 | tee -a /${WORKDIR}/pquery-run.log
          grep -o "CHANGED: [0-9]\+" ${RUNDIR}/${TRIAL}/pquery_thread-0.${QC_SEC_ENGINE}.sql > ${RUNDIR}/${TRIAL}/${QC_SEC_ENGINE}.result
        fi
      else # Not a query correctness testing run
        echoit "Starting pquery (log stored in ${RUNDIR}/${TRIAL}/pquery.log)..."
        if [ ${QUERY_DURATION_TESTING} -eq 1 ]; then # Query duration testing run
          if [[ ${MDG} -eq 0 && ${GRP_RPL} -eq 0 ]]; then
            ${PQUERY_BIN} --infile=${INFILE} --database=test --threads=${THREADS} --queries-per-thread=${QUERIES_PER_THREAD} --logdir=${RUNDIR}/${TRIAL} --log-all-queries --log-failed-queries --log-query-duration --user=root --socket=${SOCKET} > ${RUNDIR}/${TRIAL}/pquery.log 2>&1 &
            PQPID="$!"
          else
            if [[ ${MDG_CLUSTER_RUN} -eq 1 ]]; then
              cat ${MDG_CLUSTER_CONFIG} |
                sed "s|\/tmp|${RUNDIR}\/${TRIAL}|" |
                sed "s|\/home\/$(whoami)\/mariadb-qa|${SCRIPT_PWD}|" \
                  > ${RUNDIR}/${TRIAL}/pquery-cluster.cfg
              ${PQUERY_BIN} --config-file=${RUNDIR}/${TRIAL}/pquery-cluster.cfg > ${RUNDIR}/${TRIAL}/pquery.log 2>&1 &
              PQPID="$!"
            elif [[ ${GRP_RPL_CLUSTER_RUN} -eq 1 ]]; then
              cat ${GRP_RPL_CLUSTER_CONFIG} |
                sed "s|\/tmp|${RUNDIR}\/${TRIAL}|" |
                sed "s|\/home\/$(whoami)\/mariadb-qa|${SCRIPT_PWD}|" \
                  > ${RUNDIR}/${TRIAL}/pquery-cluster.cfg
              ${PQUERY_BIN} --config-file=${RUNDIR}/${TRIAL}/pquery-cluster.cfg > ${RUNDIR}/${TRIAL}/pquery.log 2>&1 &
              PQPID="$!"
            else  # Query duration testing run
              ${PQUERY_BIN} --infile=${INFILE} --database=test --threads=${THREADS} --queries-per-thread=${QUERIES_PER_THREAD} --logdir=${RUNDIR}/${TRIAL} --log-all-queries --log-failed-queries --log-query-duration --user=root --socket=${SOCKET1} > ${RUNDIR}/${TRIAL}/pquery.log 2>&1 &
              PQPID="$!"
            fi
          fi
        else # Standard pquery run / Not a query duration testing run
          if [[ ${MDG} -eq 0 && ${GRP_RPL} -eq 0 ]]; then
            # Preload SQL if the PRELOAD feature is enabled (this SQL will be prepended to the trial's SQL later)
            if [ "${PRELOAD}" == "1" -a ! -z "${PRELOAD_SQL}" ]; then
              echoit "PRELOAD=1: Pre-loading SQL in ${PRELOAD_SQL}"
              mkdir -p ${RUNDIR}/${TRIAL}/preload
              ${PQUERY_BIN} --infile=${PRELOAD_SQL} --database=test --threads=1 --queries-per-thread=99999999 --logdir=${RUNDIR}/${TRIAL}/preload --log-all-queries --log-failed-queries --no-shuffle --user=root --socket=${SOCKET} > ${RUNDIR}/${TRIAL}/preload/pquery_preload_sql.log 2>&1 &
            fi
            # Standard/default (non-GRP-RPL non-Galera non-Query-duration-testing) pquery run
            ## Check pre-shuffle directory
            if [ "${PRE_SHUFFLE_SQL}" == "1" ]; then
              if [ ! -d "${PRE_SHUFFLE_DIR}" ]; then
                echoit "PRE_SHUFFLE_SQL_DIR ('${PRE_SHUFFLE_DIR}') is no longer available. Was it deleted? Attempting to recreate"
                mkdir -p "${PRE_SHUFFLE_SQL}"
                if [ ! -d "${PRE_SHUFFLE_DIR}" ]; then
                  echoit "PRE_SHUFFLE_SQL_DIR ('${PRE_SHUFFLE_DIR}') could not be recreated. Turning off SQL pre-shuffling for now. Please fix whatever is gonig wrong"
                  PRE_SHUFFLE_SQL=0
                fi
              fi
            fi 
            ## Pre-shuffle (if activated)
            if [ "${PRE_SHUFFLE_SQL}" == "1" ]; then
              PRE_SHUFFLE_TRIAL_ROUND=$[ ${PRE_SHUFFLE_TRIAL_ROUND} + 1 ]  # Reset to 1 each time PRE_SHUFFLE_TRIALS_PER_SHUFFLE is reached
              if [ ${PRE_SHUFFLE_TRIAL_ROUND} -eq 1 ]; then 
                local WORKNRDIR="$(echo ${RUNDIR} | sed 's|.*/||' | grep -o '[0-9]\+')"
                INFILE_SHUFFLED="${PRE_SHUFFLE_DIR}/${WORKNRDIR}_${TRIAL}.sql"
                WORKNRDIR=
                echoit "Randomly pre-shuffling ${PRE_SHUFFLE_SQL_LINES} lines of SQL into ${INFILE_SHUFFLED} | Trial ${PRE_SHUFFLE_TRIAL_ROUND}/${PRE_SHUFFLE_TRIALS_PER_SHUFFLE}"
                RANDOM=$(date +%s%N | cut -b10-19)
                shuf --random-source=/dev/urandom -n ${PRE_SHUFFLE_SQL_LINES} ${INFILE} > ${INFILE_SHUFFLED}
              else
                echoit "Re-using pre-shuffled SQL ${INFILE_SHUFFLED} (${PRE_SHUFFLE_SQL_LINES} lines) | Trial ${PRE_SHUFFLE_TRIAL_ROUND}/${PRE_SHUFFLE_TRIALS_PER_SHUFFLE}"
              fi
              if [ ${PRE_SHUFFLE_TRIAL_ROUND} -eq ${PRE_SHUFFLE_TRIALS_PER_SHUFFLE} ]; then
                PRE_SHUFFLE_TRIAL_ROUND=0  # Next trial will reshuffle the SQL
              fi
              # Pre-shuffled trial
              ${PQUERY_BIN} --infile=${INFILE_SHUFFLED} --database=test --threads=${THREADS} --queries-per-thread=${QUERIES_PER_THREAD} --logdir=${RUNDIR}/${TRIAL} --log-all-queries --log-failed-queries --user=root --socket=${SOCKET} > ${RUNDIR}/${TRIAL}/pquery.log 2>&1 &
              PQPID="$!"
            else  # Standard non-shuffled trial
              ${PQUERY_BIN} --infile=${INFILE} --database=test --threads=${THREADS} --queries-per-thread=${QUERIES_PER_THREAD} --logdir=${RUNDIR}/${TRIAL} --log-all-queries --log-failed-queries --user=root --socket=${SOCKET} > ${RUNDIR}/${TRIAL}/pquery.log 2>&1 &
              PQPID="$!"
            fi
          else
            # Preload SQL if the PRELOAD feature is enabled (this SQL will be prepended to the trial's SQL later)
            if [ "${PRELOAD}" == "1" -a ! -z "${PRELOAD_SQL}" ]; then
              echoit "PRELOAD=1: Pre-loading SQL in ${PRELOAD_SQL}"
              mkdir -p ${RUNDIR}/${TRIAL}/preload
              ${PQUERY_BIN} --infile=${PRELOAD_SQL} --database=test --threads=1 --queries-per-thread=99999999 --logdir=${RUNDIR}/${TRIAL}/preload --log-all-queries --log-failed-queries --no-shuffle --user=root --socket=${SOCKET1} > ${RUNDIR}/${TRIAL}/preload/pquery_preload_sql.log 2>&1 &
            fi
            if [[ ${MDG_CLUSTER_RUN} -eq 1 ]]; then
              for i in $(seq 1 ${NR_OF_NODES}); do
                cat << EOF >> ${RUNDIR}/${TRIAL}/pquery-cluster.cfg
[node${i}.md.galera]
database = test
address = localhost
infile = ${INFILE}
logdir = ${RUNDIR}/${TRIAL}
socket = ${RUNDIR}/${TRIAL}/node${i}/node${i}_socket.sock
user = root
password =
threads = 1
queries-per-thread = 10000000
verbose = No
log-all-queries = Yes
log-failed-queries = Yes
shuffle = Yes
log-query-statistics = No
log-query-duration = No
log-client-output = No
log-query-number = No
run= Yes

EOF
              done
              echoit "${PQUERY_BIN} --config-file=${RUNDIR}/${TRIAL}/pquery-cluster.cfg"
              ${PQUERY_BIN} --config-file=${RUNDIR}/${TRIAL}/pquery-cluster.cfg > ${RUNDIR}/${TRIAL}/pquery.log 2>&1 &
              PQPID="$!"
            elif [[ ${GRP_RPL_CLUSTER_RUN} -eq 1 ]]; then
              cat ${GRP_RPL_CLUSTER_CONFIG} |
                sed "s|\/tmp|${RUNDIR}\/${TRIAL}|" |
                sed "s|\/home\/$(whoami)\/mariadb-qa|${SCRIPT_PWD}|" \
                  > ${RUNDIR}/${TRIAL}/pquery-cluster.cfg
              ${PQUERY_BIN} --config-file=${RUNDIR}/${TRIAL}/pquery-cluster.cfg > ${RUNDIR}/${TRIAL}/pquery.log 2>&1 &
              PQPID="$!"
            else 
              ${PQUERY_BIN} --infile=${INFILE} --database=test --threads=${THREADS} --queries-per-thread=${QUERIES_PER_THREAD} --logdir=${RUNDIR}/${TRIAL} --log-all-queries --log-failed-queries --log-query-duration --user=root --socket=${SOCKET1} > ${RUNDIR}/${TRIAL}/pquery.log 2>&1 &
              PQPID="$!" 
              #echoit "Assert: GRP_RPL_CLUSTER_RUN=${GRP_RPL_CLUSTER_RUN} and MDG_CLUSTER_RUN=${MDG_CLUSTER_RUN}"
              #exit 1
            fi
          fi
        fi
      fi
    else
      # Multi-threaded run using a chunk from INFILE (${THREADS} clients)
      if [ ${PQUERY3} -eq 1 ]; then
        if [ "${TRIAL}" == "1" ]; then
          echoit "Creating metadata randomly using random seed ${SEED} ..."
        else
          echoit "Loading metadata from ${WORKDIR}/step_$((${TRIAL} - 1)).dll ..."
        fi
        if [[ ${MDG} -eq 0 && ${GRP_RPL} -eq 0 ]]; then
          CMD="${PQUERY_BIN} --database=test --threads=${THREADS} --queries-per-thread=${QUERIES_PER_THREAD} --logdir=${RUNDIR}/${TRIAL} --user=root --socket=${SOCKET} --seed ${SEED} --step ${TRIAL} --metadata-path ${WORKDIR}/ --seconds ${PQUERY_RUN_TIMEOUT} ${DYNAMIC_QUERY_PARAMETER}"
        elif [ ${MDG_CLUSTER_RUN} -eq 1 ]; then
          cat ${MDG_CLUSTER_CONFIG} |
              sed "s|\/tmp|${RUNDIR}\/${TRIAL}|" \
                > ${RUNDIR}/${TRIAL}/pquery3-cluster-mdg.cfg
          CMD="${PQUERY_BIN} --database=test --config-file=${RUNDIR}/${TRIAL}/pquery3-cluster-mdg.cfg --queries-per-thread=${QUERIES_PER_THREAD} --seed ${SEED} --step ${TRIAL} --metadata-path ${WORKDIR}/ --seconds ${PQUERY_RUN_TIMEOUT} ${DYNAMIC_QUERY_PARAMETER}"
        else
          CMD="${PQUERY_BIN} --database=test --threads=${THREADS} --queries-per-thread=${QUERIES_PER_THREAD} --logdir=${RUNDIR}/${TRIAL}/node1/ --user=root --socket=${SOCKET1} --seed ${SEED} --step ${TRIAL} --metadata-path ${WORKDIR}/ --seconds ${PQUERY_RUN_TIMEOUT} ${DYNAMIC_QUERY_PARAMETER}"
        fi
        echoit "$CMD"
        diskspace
        $CMD > ${RUNDIR}/${TRIAL}/pquery.log 2>&1 &
        PQPID="$!"
      else
        echoit "Taking ${MULTI_THREADED_TESTC_LINES} lines randomly from ${INFILE} as testcase for this multi-threaded trial..."
        shuf --random-source=/dev/urandom ${INFILE} | head -n${MULTI_THREADED_TESTC_LINES} > ${RUNDIR}/${TRIAL}/${TRIAL}.sql
        SQL_FILE="--infile=${RUNDIR}/${TRIAL}/${TRIAL}.sql"
        if [[ ${MDG} -eq 0 && ${GRP_RPL} -eq 0 ]]; then
          ${PQUERY_BIN} ${SQL_FILE} --database=test --threads=${THREADS} --queries-per-thread=${QUERIES_PER_THREAD} --logdir=${RUNDIR}/${TRIAL} --log-all-queries --log-failed-queries --user=root --socket=${SOCKET} > ${RUNDIR}/${TRIAL}/pquery.log 2>&1 &
          PQPID="$!"
        else
          if [[ ${MDG_CLUSTER_RUN} -eq 1 ]]; then
            cat ${MDG_CLUSTER_CONFIG} |
               sed "s|\/tmp|${RUNDIR}\/${TRIAL}|" |
               sed "s|\/home\/$(whoami)\/mariadb-qa|${SCRIPT_PWD}|" \
                 > ${RUNDIR}/${TRIAL}/pquery-cluster.cfg
            ${PQUERY_BIN} --config-file=${RUNDIR}/${TRIAL}/pquery-cluster.cfg > ${RUNDIR}/${TRIAL}/pquery.log 2>&1 &
            PQPID="$!"
          else
            ${PQUERY_BIN} ${SQL_FILE} --database=test --threads=${THREADS} --queries-per-thread=${QUERIES_PER_THREAD} --logdir=${RUNDIR}/${TRIAL} --log-all-queries --log-failed-queries --user=root --socket=${SOCKET1} > ${RUNDIR}/${TRIAL}/pquery.log 2>&1 &
            PQPID="$!"
          fi
        fi
      fi
    fi
    TIMEOUT_REACHED=0
    if [ ${QUERY_CORRECTNESS_TESTING} -ne 1 ]; then
      echoit "pquery running (Max duration: ${PQUERY_RUN_TIMEOUT}s)..."
      for X in $(seq 1 ${PQUERY_RUN_TIMEOUT}); do
        sleep 1
        if grep -qi "error while loading shared libraries" ${RUNDIR}/${TRIAL}/pquery.log; then
          if grep -qi "error while loading shared libraries.*libssl" ${RUNDIR}/${TRIAL}/pquery.log; then
            echoit "$(grep -i "error while loading shared libraries" ${RUNDIR}/${TRIAL}/pquery.log)"
            echoit "Assert: There was an error loading the shared/dynamic libssl library linked to from within pquery. You may want to try and install a package similar to libssl-dev. If that is already there, try instead to build pquery on this particular machine. Sometimes there are differences seen between Centos and Ubuntu. Perhaps we need to have a pquery build for each of those separately."
          else
            echoit "Assert: There was an error loading the shared/dynamic mysql client library linked to from within pquery. Ref. ${RUNDIR}/${TRIAL}/pquery.log to see the error. The solution is to ensure that LD_LIBRARY_PATH is set correctly (for example: execute '$ export LD_LIBRARY_PATH=<your_mysql_base_directory>/lib' in your shell. This will happen only if you use pquery without statically linked client libraries, and this in turn would happen only if you compiled pquery yourself instead of using the pre-built binaries available in https://github.com/Percona-QA/mariadb-qa (ref subdirectory/files ./pquery/pquery*) - which are normally used by this script (hence this situation is odd to start with). The pquery binaries in mariadb-qa all include a statically linked mysql client library matching the mysql flavor (PS,MS,MD,WS) it was built for. Another reason for this error may be that (having used pquery without statically linked client binaries as mentioned earlier) the client libraries are not available at the location set in LD_LIBRARY_PATH (which is currently set to '${LD_LIBRARY_PATH}'."
          fi
          exit 1
        fi
        if [ "$(ps -ef | grep ${PQPID} | grep -v grep)" == "" ]; then # pquery ended
          break
        fi
        if [ ${CRASH_RECOVERY_TESTING} -eq 1 ]; then
          if [[ ${REPL} -eq 1 ]]; then
            # Shutdown/kill servers for replication crash recovery testing before finishing pquery run
            if [ $X -ge ${REPLICATION_SHUTDOWN_OR_KILL_TIMEOUT} ]; then
              if [[ ${REPLICATION_SHUTDOWN_OR_KILL} -eq 1 ]]; then
                # kill servers for replication crash recovery testing
                kill -9 ${MPID} > /dev/null 2>&1
                kill -9 ${SLAVE_MPID} > /dev/null 2>&1
              else
                # shutdown servers for replication crash recovery testing
                timeout --signal=9 90s ${BASEDIR}/bin/mysqladmin -uroot -S${SOCKET} shutdown > /dev/null 2>&1
                timeout --signal=9 90s ${BASEDIR}/bin/mysqladmin -uroot -S${SLAVE_SOCKET} shutdown > /dev/null 2>&1
              fi
              sleep 2
              echoit "killed for crash testing"
              CRASH_CHECK=1
              break
            fi
          else
            if [ $X -ge $CRASH_RECOVERY_KILL_BEFORE_END_SEC ]; then
              if [ $MDG -eq 1 ]; then
                ps -ef | grep -e 'node1_socket\|node2_socket\|node3_socket' | grep -v grep | grep $RANDOMD | awk '{print $2}' | xargs kill -9 > /dev/null 2>&1
              else
                kill -9 ${MPID} > /dev/null 2>&1
              fi
            fi
            sleep 2
            echoit "killed for crash testing"
            CRASH_CHECK=1
            break
          fi
        fi
        # Initiate Percona Xtrabackup
        if [[ ${PXB_CRASH_RUN} -eq 1 ]]; then
          if [[ $X -ge $PXB_INITIALIZE_BACKUP_SEC ]]; then
            $PXB_BASEDIR/bin/xtrabackup --user=root --password='' --backup --target-dir=${RUNDIR}/${TRIAL}/xb_full -S${SOCKET} --datadir=${RUNDIR}/${TRIAL}/data --lock-ddl > ${RUNDIR}/${TRIAL}/backup.log 2>&1
            $PXB_BASEDIR/bin/xtrabackup --prepare --target_dir=${RUNDIR}/${TRIAL}/xb_full --lock-ddl > ${RUNDIR}/${TRIAL}/prepare_backup.log 2>&1
            echoit "Backup completed"
            PXB_CHECK=1
            break
          fi
        fi
        if [ $X -ge ${PQUERY_RUN_TIMEOUT} ]; then
          echoit "${PQUERY_RUN_TIMEOUT}s timeout reached. Terminating this trial..."
          TIMEOUT_REACHED=1
          if [ ${TIMEOUT_INCREMENT} != 0 ]; then
            echoit "TIMEOUT_INCREMENT option was enabled and set to ${TIMEOUT_INCREMENT} sec"
            echoit "${TIMEOUT_INCREMENT}s will be added to the next trial timeout."
          #else  # No need to show this when it is was not set
          #  echoit "TIMEOUT_INCREMENT option was disabled and set to 0"
          fi
          PQUERY_RUN_TIMEOUT=$((${PQUERY_RUN_TIMEOUT} + ${TIMEOUT_INCREMENT}))
          break
        fi
      done
      if [ "$PMM" == "1" ]; then
        if ps -p ${MPID} > /dev/null; then
          echoit "PMM trial info : Sleeping 5 mints to check the data collection status"
          sleep 300
        fi
      fi
    fi
  else
    if [[ ${MDG} -eq 0 && ${GRP_RPL} -eq 0 ]]; then
      if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 ]; then
        echoit "Either the Primary server (PID: ${MPID} | Socket: ${SOCKET}), or the Secondary server (PID: ${MPID2} | Socket: ${RUNDIR}/${TRIAL}/socket2.sock) failed to start after ${MYSQLD_START_TIMEOUT} seconds. Will issue extra kill -9 to ensure it's gone..."
        (
          sleep 0.2
          kill -9 ${MPID2} > /dev/null 2>&1
          timeout -k4 -s9 4s wait ${MPID2} > /dev/null 2>&1
        ) &
        timeout -k5 -s9 5s wait ${MPID2} > /dev/null 2>&1
      else
        echoit "Server (PID: ${MPID} | Socket: ${SOCKET}) failed to start after ${MYSQLD_START_TIMEOUT} seconds. Will issue extra kill -9 to ensure it's gone..."
      fi
      (
        sleep 0.2
        kill -9 ${MPID} > /dev/null 2>&1
        timeout -k4 -s9 4s wait ${MPID} > /dev/null 2>&1
      ) &
      timeout -k5 -s9 5s wait ${MPID} > /dev/null 2>&1
      sleep 2
      sync
    elif [[ ${MDG} -eq 1 ]]; then
      echoit "${NR_OF_NODES} Node MDG Cluster failed to start after ${MDG_START_TIMEOUT} seconds. Will issue an extra cleanup to ensure nothing remains..."
      (ps -ef | grep 'n[0-9].cnf' | grep ${RUNDIR} | grep -v grep | awk '{print $2}' | xargs kill -9 > /dev/null 2>&1 || true)
      sleep 2
      sync
    elif [[ ${GRP_RPL} -eq 1 ]]; then
      echoit "3 Node Group Replication Cluster failed to start after ${GRP_RPL_START_TIMEOUT} seconds. Will issue an extra cleanup to ensure nothing remains..."
      (ps -ef | grep 'node[0-9]_socket' | grep ${RUNDIR} | grep -v grep | awk '{print $2}' | xargs kill -9 > /dev/null 2>&1 || true)
      sleep 2
      sync
    fi
  fi
  if [ "${VALGRIND_RUN}" == "1" ]; then
    echoit "Cleaning up & saving results if needed. Note that this may take up to 10 minutes because this is a Valgrind run. You may also see a mysqladmin killed message..."
  else
    echoit "Cleaning up & saving results if needed..."
  fi
  TRIAL_SAVED=0
  sleep 2 # Delay to ensure core was written completely (if any)
  # First cleanup any temporary SQL if PRE_SHUFFLE_TRIAL_ROUND=0 (i.e. the number of PRE_SHUFFLE_TRIALS_PER_SHUFFLE trials was completed)
  if [ ! -z "${INFILE_SHUFFLED}" -a -r "${INFILE_SHUFFLED}" -a ! -d "${INFILE_SHUFFLED}" ]; then
    if [ ${PRE_SHUFFLE_TRIAL_ROUND} -eq 0 ]; then
      echoit "Deleting pre-shuffle SQL file ${INFILE_SHUFFLED} as ${PRE_SHUFFLE_TRIALS_PER_SHUFFLE}/${PRE_SHUFFLE_TRIALS_PER_SHUFFLE} trials were completed"
      rm -f "${INFILE_SHUFFLED}"
      INFILE_SHUFFLED=
    fi
  fi
  # NOTE**: Do not kill PQPID here/before shutdown. The reason is that pquery may still be writing queries it's executing to the log. The only way to halt pquery correctly is by actually shutting down the server which will auto-terminate pquery due to 250 consecutive queries failing. If 250 queries failed and ${PQUERY_RUN_TIMEOUT}s timeout was reached, and if there is no core/Valgrind issue and there is no output of mariadb-qa/text_string.sh either (in case core dumps are not configured correctly, and thus no core file is generated, text_string.sh will still produce output in case the server crashed based on the information in the error log), then we do not need to save this trial (as it is a standard occurence for this to happen). If however we saw 250 queries failed before the timeout was complete, then there may be another problem and the trial should be saved.
  if [[ ${MDG} -eq 0 && ${GRP_RPL} -eq 0 ]]; then
    if [ "${VALGRIND_RUN}" == "1" ]; then # For Valgrind, we want the full Valgrind output in the error log, hence we need a proper/clean (and slow...) shutdown
      # Note that even if mysqladmin is killed with the 'timeout --signal=9', it will not affect the actual state of mysqld, all that was terminated was mysqladmin.
      # Thus, mysqld would (presumably) have received a shutdown signal (even if the timeout was 2 seconds it likely would have)
      timeout --signal=9 90s ${BASEDIR}/bin/mysqladmin -uroot -S${SOCKET} shutdown > /dev/null 2>&1 # Proper/clean shutdown attempt (up to 90 sec wait), necessary to get full Valgrind output in error log + see NOTE** above
      if [ $? -gt 124 ]; then
        echoit "mysqld failed to shutdown within 90 seconds for this trial, saving it (pquery-results.sh will show these trials seperately)..."
        touch ${RUNDIR}/${TRIAL}/SHUTDOWN_TIMEOUT_ISSUE
        # Note we are not checking for RR tracing here, as it is unlikely that Valgrind tracing + RR tracing is used at the same time
        savetrial
        TRIAL_SAVED=1
      fi
      VALGRIND_SUMMARY_FOUND=0
      for X in $(# Wait for full Valgrind output in error log
        seq 0 600
      ); do
        sleep 1
        if [ ! -r ${RUNDIR}/${TRIAL}/log/master.err ]; then
          echoit "Assert: ${RUNDIR}/${TRIAL}/log/master.err not found during a Valgrind run. Please check. Trying to continue, but something is wrong already..."
          break
        elif egrep -qi "==[0-9]+== ERROR SUMMARY: [0-9]+ error" ${RUNDIR}/${TRIAL}/log/master.err; then # Summary found, Valgrind is done
          VALGRIND_SUMMARY_FOUND=1
          sleep 2
          break
        fi
      done
      if [ ${VALGRIND_SUMMARY_FOUND} -eq 0 ]; then
        kill -9 ${MPID} ${SLAVE_MPID} > /dev/null 2>&1
        if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 ]; then
          kill -9 ${MPID2} > /dev/null 2>&1
        fi
        sleep 2 # <^ Make sure mysqld is gone
        echoit "Odd mysqld hang detected (mysqld did not terminate even after 600 seconds), saving this trial... "
        if [ ${TRIAL_SAVED} -eq 0 ]; then
          savetrial
          TRIAL_SAVED=1
        fi
      fi
    else
      if [ ${QUERY_CORRECTNESS_TESTING} -ne 1 ]; then
        # This shutdown in the main shutdown done for every standard/default options pquery trial
        timeout --signal=9 90s ${BASEDIR}/bin/mysqladmin -uroot -S${SOCKET} shutdown > /dev/null 2>&1 # Proper/clean shutdown attempt (up to 90 sec wait), necessary to get full Valgrind output in error log + see NOTE** above
        if [ $? -gt 124 ]; then
          echoit "mysqld failed to shutdown within 90 seconds for this trial, saving it (pquery-results.sh will show these trials seperately)..."
          touch ${RUNDIR}/${TRIAL}/SHUTDOWN_TIMEOUT_ISSUE
          if [ "${RR_TRACING}" == "1" ]; then
            # If the rr trace is saved at this point, it would be marked as incomplete (./incomplete in mysqld-0)
            # To avoid this, we need to SIGABRT (kill -6) the tracee (mysqld) so that the rr trace can finish correctly
            echoit "RR Tracing is active, sending SIGABRT to tracee mysqld and providing time for RR trace to finish correctly"
            echo -n "$(cat ${RUNDIR}/${TRIAL}/pid.pid | xargs -I{} kill -6 {})"  # Hack, which works well
            MAX_RR_WAIT=60; CUR_RR_WAIT=0;
            while [ -r ${RUNDIR}/${TRIAL}/rr/mysqld-0/incomplete ]; do
              sleep 1
              CUR_RR_WAIT=$[ ${CUR_RR_WAIT} + 1 ]
              if [ ${CUR_RR_WAIT} -gt ${MAX_RR_WAIT} ]; then
                echoit "pquery-run waited ${CUR_RR_WAIT} seconds for the RR trace to finish correctly, but it did not complete within this time: terminating this trial, but the trace is highly likely to be incomplete"
                break
              fi
            done
            if [ ${CUR_RR_WAIT} -le ${MAX_RR_WAIT} ]; then
              echoit "RR traces completed successfully and trace was saved in the rr/mysqld-0 directory inside the trial directory"
            fi
          fi
          sleep 1
          savetrial
          TRIAL_SAVED=1
        fi
        if [[ ${REPL} -eq 1 ]]; then
          timeout --signal=9 90s ${BASEDIR}/bin/mysqladmin -uroot -S${SLAVE_SOCKET} shutdown > /dev/null 2>&1 # Proper/clean shutdown attempt (up to 90 sec wait), necessary to get full Valgrind output in error log + see NOTE** above
          if [ $? -gt 124 ]; then
            echoit "mysqld failed to shutdown within 90 seconds for this trial, saving it (pquery-results.sh will show these trials seperately)..."
            touch ${RUNDIR}/${TRIAL}/SHUTDOWN_TIMEOUT_ISSUE
            if [ "${RR_TRACING}" == "1" ]; then
              # If the rr trace is saved at this point, it would be marked as incomplete (./incomplete in mysqld-0)
              # To avoid this, we need to SIGABRT (kill -6) the tracee (mysqld) so that the rr trace can finish correctly
              echoit "RR Tracing is active, sending SIGABRT to tracee mysqld and providing time for RR trace to finish correctly"
              kill -6 ${SLAVE_MPID}
              kill -6 $(ps -o ppid= -p ${SLAVE_MPID})  # Kill the PPID, which is more succesful than killing the PID of the server
              MAX_RR_WAIT=60; CUR_RR_WAIT=0;
              while [ -r ${RUNDIR}/${TRIAL}/rr/mysqld-0/incomplete ]; do
                sleep 1
                 CUR_RR_WAIT=$[ ${CUR_RR_WAIT} + 1 ]
                if [ ${CUR_RR_WAIT} -gt ${MAX_RR_WAIT} ]; then
                  echoit "pquery-run waited ${CUR_RR_WAIT} seconds for the RR trace to finish correctly, but it did not complete within this time: terminating this trial, but the trace is highly likely to be incomplete"
                  break
                fi
              done
              if [ ${CUR_RR_WAIT} -le ${MAX_RR_WAIT} ]; then
                echoit "RR traces completed successfully and trace was saved in the rr/mysqld-0 directory inside the trial directory"
              fi
            fi
            sleep 1
            savetrial
            TRIAL_SAVED=1
          fi
        fi
        sleep 2
      fi
    fi
    (
      sleep 0.2
      kill -9 ${MPID} ${SLAVE_MPID} > /dev/null 2>&1
      timeout -k5 -s9 5s wait ${MPID} ${SLAVE_MPID} > /dev/null 2>&1
    ) & # Terminate mysqld
    if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 ]; then
      (
        sleep 0.2
        kill -9 ${MPID2} > /dev/null 2>&1
        timeout -k5 -s9 5s wait ${MPID2} > /dev/null 2>&1
      ) & # Terminate mysqld
      (
        sleep 0.2
        kill -9 ${PQPID2} > /dev/null 2>&1
        timeout -k5 -s9 5s wait ${PQPID2} > /dev/null 2>&1
      ) & # Terminate pquery (if it went past ${PQUERY_RUN_TIMEOUT} time, also see NOTE** above)
    fi
    sleep 1 # <^ Make sure all is gone
  elif [[ ${MDG} -eq 1 || ${GRP_RPL} -eq 1 ]]; then
    if [ "${VALGRIND_RUN}" == "1" ]; then # For Valgrind, we want the full Valgrind output in the error log, hence we need a proper/clean (and slow...) shutdown
      # Note that even if mysqladmin is killed with the 'timeout --signal=9', it will not affect the actual state of mysqld, all that was terminated was mysqladmin.
      # Thus, mysqld would (presumably) have received a shutdown signal (even if the timeout was 2 seconds it likely would have)
      # Proper/clean shutdown attempt (up to 20 sec wait), necessary to get full Valgrind output in error log
      timeout --signal=9 90s ${BASEDIR}/bin/mysqladmin -uroot -S${SOCKET3} shutdown > /dev/null 2>&1
      if [ $? -gt 124 ]; then
        echoit "mysqld for node3 failed to shutdown within 90 seconds for this trial, saving it (pquery-results.sh will show these trials seperately)..."
        touch ${RUNDIR}/${TRIAL}/SHUTDOWN_TIMEOUT_ISSUE
        #if [ "${RR_TRACING}" == "1" ]; then
        #  # If the rr trace is saved at this point, it would be marked as incomplete (./incomplete in mysqld-0)
        #  # To avoid this, we need to SIGABRT (kill -6) the tracee (mysqld) so that the rr trace can finish correctly
        #  echoit "RR Tracing is active, sending SIGABRT to tracee mysqld and providing time for RR trace to finish correctly"
        #  kill -6 ${SLAVE_MPID}
        #  kill -6 $(ps -o ppid= -p ${SLAVE_MPID})  # Kill the PPID, which is more succesful than killing the PID of the server
        #  MAX_RR_WAIT=60; CUR_RR_WAIT=0;
        #  while [ -r ${RUNDIR}/${TRIAL}/rr/mysqld-0/incomplete ]; do
        #    sleep 1
        #     CUR_RR_WAIT=$[ ${CUR_RR_WAIT} + 1 ]
        #    if [ ${CUR_RR_WAIT} -gt ${MAX_RR_WAIT} ]; then
        #      echoit "pquery-run waited ${CUR_RR_WAIT} seconds for the RR trace to finish correctly, but it did not complete within this time: terminating this trial, but the trace is highly likely to be incomplete"
        #      break
        #    fi
        #   done
        #  if [ ${CUR_RR_WAIT} -le ${MAX_RR_WAIT} ]; then
        #    echoit "RR traces completed successfully and trace was saved in the rr/mysqld-0 directory inside the trial directory"
        #  fi
        sleep 1
        savetrial
        TRIAL_SAVED=1
      fi
      timeout --signal=9 90s ${BASEDIR}/bin/mysqladmin -uroot -S${SOCKET2} shutdown > /dev/null 2>&1
      if [ $? -gt 124 ]; then
        echoit "mysqld for node2 failed to shutdown within 90 seconds for this trial, saving it (pquery-results.sh will show these trials seperately)..."
        sleep 1
        touch ${RUNDIR}/${TRIAL}/SHUTDOWN_TIMEOUT_ISSUE
        savetrial
        TRIAL_SAVED=1
      fi
      timeout --signal=9 90s ${BASEDIR}/bin/mysqladmin -uroot -S${SOCKET1} shutdown > /dev/null 2>&1
      if [ $? -gt 124 ]; then
        echoit "mysqld for node1 failed to shutdown within 90 seconds for this trial, saving it (pquery-results.sh will show these trials seperately)..."
        touch ${RUNDIR}/${TRIAL}/SHUTDOWN_TIMEOUT_ISSUE
        sleep 1
        savetrial
        TRIAL_SAVED=1
      fi
      for X in $(# Wait for full Valgrind output in error log
        seq 0 600
      ); do
        sleep 1
        if [[ ! -r ${RUNDIR}/${TRIAL}/node1/node1.err || ! -r ${RUNDIR}/${TRIAL}/node2/node2.err || ! -r ${RUNDIR}/${TRIAL}/node2/node2.err ]]; then
          echoit "Assert: MariaDB Galera error logs (${RUNDIR}/${TRIAL}/node[13]/node[13].err) not found during a Valgrind run. Please check. Trying to continue, but something is wrong already..."
          break
        elif [ $(egrep "==[0-9]+== ERROR SUMMARY: [0-9]+ error" ${RUNDIR}/${TRIAL}/node*/node*.err | wc -l) -eq 3 ]; then # Summary found, Valgrind is done
          VALGRIND_SUMMARY_FOUND=1
          sleep 2
          break
        fi
      done
      if [ ${VALGRIND_SUMMARY_FOUND} -eq 0 ]; then
        kill -9 ${PQPID} > /dev/null 2>&1
        (ps -ef | grep 'node[0-9]_socket' | grep ${RUNDIR} | grep -v grep | awk '{print $2}' | xargs kill -9 > /dev/null 2>&1 || true)
        sleep 1 # <^ Make sure mysqld is gone
        echoit "Odd mysqld hang detected (mysqld did not terminate even after 600 seconds), saving this trial... "
        if [ ${TRIAL_SAVED} -eq 0 ]; then
          savetrial
          TRIAL_SAVED=1
        fi
      fi
    fi
    (ps -ef | grep 'n[0-9].cnf' | grep ${RUNDIR} | grep -v grep | awk '{print $2}' | xargs kill -9 > /dev/null 2>&1 || true)
    sleep 2
    sync
  fi
  if [ ${ISSTARTED} -eq 1 -a ${TRIAL_SAVED} -ne 1 ]; then # Do not try and print pquery log for a failed mysqld start
    if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 ]; then
      echoit "Pri engine pquery run details:$(grep -i 'SUMMARY.*queries failed' ${RUNDIR}/${TRIAL}/*.sql ${RUNDIR}/${TRIAL}/*.log | sed 's|.*:||')"
      echoit "Sec engine pquery run details:$(grep -i 'SUMMARY.*queries failed' ${RUNDIR}/${TRIAL}/*.sql ${RUNDIR}/${TRIAL}/*.log | sed 's|.*:||')"
    else
      echoit "pquery run details:$(grep -i 'SUMMARY.*queries failed' ${RUNDIR}/${TRIAL}/*.sql ${RUNDIR}/${TRIAL}/*.log | sed 's|.*:||')"
    fi
  fi
  if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 -a $(ls -l ${RUNDIR}/${TRIAL}/*/*core* 2> /dev/null | wc -l) -eq 0 -a "$(${SCRIPT_PWD}/OLD/text_string.sh ${RUNDIR}/${TRIAL}/log/master.err 2> /dev/null)" == "" ]; then # If a core is found (or text_string.sh sees a crash) when query correctness testing is in progress, it will process it as a normal crash (without considering query correctness)
    if [ "${FAILEDSTARTABORT}" != "1" ]; then
      if [ ${QUERY_CORRECTNESS_MODE} -ne 2 ]; then
        QC_RESULT1=$(diff ${RUNDIR}/${TRIAL}/${QC_PRI_ENGINE}.result ${RUNDIR}/${TRIAL}/${QC_SEC_ENGINE}.result)
        #QC_RESULT2=$(cat ${RUNDIR}/${TRIAL}/pquery1.log | grep -i 'SUMMARY' | sed 's|^.*:|pquery summary:|')
        #QC_RESULT3=$(cat ${RUNDIR}/${TRIAL}/pquery2.log | grep -i 'SUMMARY' | sed 's|^.*:|pquery summary:|')
      else
        QC_RESULT1=$(diff <(sed "s@${QC_PRI_ENGINE}@${QC_SEC_ENGINE}@g" ${RUNDIR}/${TRIAL}/pquery_thread-0.${QC_PRI_ENGINE}.out) ${RUNDIR}/${TRIAL}/pquery_thread-0.${QC_SEC_ENGINE}.out)
      fi
      QC_DIFF_FOUND=0
      if [ "${QC_RESULT1}" != "" ]; then
        echoit "Found $(echo ${QC_RESULT1} | wc -l) differences between ${QC_PRI_ENGINE} and ${QC_SEC_ENGINE} results. Saving trial..."
        QC_DIFF_FOUND=1
      fi
      #if [ "${QC_RESULT2}" != "${QC_RESULT3}" ]; then
      #  echoit "Found differences in pquery execution success between ${QC_PRI_ENGINE} and ${QC_SEC_ENGINE} results. Saving trial..."
      #  QC_DIFF_FOUND=1
      #fi
      if [ ${QC_DIFF_FOUND} -eq 1 ]; then
        savetrial
        TRIAL_SAVED=1
      fi
    fi
  else
    if [ "${VALGRIND_RUN}" == "1" ]; then
      VALGRIND_ERRORS_FOUND=0
      VALGRIND_CHECK_1=
      # What follows next are 3 different ways of checking if Valgrind issues were seen, mostly to ensure that no Valgrind issues go unseen, especially if log is not complete
      VALGRIND_CHECK_1=$(grep "==[0-9]\+== ERROR SUMMARY: [0-9]\+ error" ${RUNDIR}/${TRIAL}/log/master.err | sed 's|.*ERROR SUMMARY: \([0-9]\+\) error.*|\1|')
      if [ "${VALGRIND_CHECK_1}" == "" ]; then VALGRIND_CHECK_1=0; fi
      if [ ${VALGRIND_CHECK_1} -gt 0 ]; then
        VALGRIND_ERRORS_FOUND=1
      fi
      if egrep -qi "^[ \t]*==[0-9]+[= \t]+[atby]+[ \t]*0x" ${RUNDIR}/${TRIAL}/log/master.err; then
        VALGRIND_ERRORS_FOUND=1
      fi
      if egrep -qi "==[0-9]+== ERROR SUMMARY: [1-9]" ${RUNDIR}/${TRIAL}/log/master.err; then
        VALGRIND_ERRORS_FOUND=1
      fi
      if [ ${VALGRIND_ERRORS_FOUND} -eq 1 ]; then
        VALGRIND_TEXT=$(${SCRIPT_PWD}/valgrind_string.sh ${RUNDIR}/${TRIAL}/log/master.err)
        echoit "Valgrind error detected: ${VALGRIND_TEXT}"
        if [ ${TRIAL_SAVED} -eq 0 ]; then
          savetrial
          TRIAL_SAVED=1
        fi
      else
        # Report that no Valgrnid errors were found & Include ERROR SUMMARY from error log
        echoit "No Valgrind errors detected. $(grep "==[0-9]\+== ERROR SUMMARY: [0-9]\+ error" ${RUNDIR}/${TRIAL}/log/master.err | sed 's|.*ERROR S|ERROR S|')"
      fi
    fi
    if [ ${TRIAL_SAVED} -eq 0 ]; then
      TRIAL_TO_SAVE=0
      # Checking for a core has to always come before all other checks; If there is a core, there is the possibility of gaining a unique bug identifier using new_text.string.sh.
      # The /*/ in the /*/*core* core search pattern is for to the /node1/ dir setup for cluster runs
      # TODO: verify if this means that /data/ is completely replaced by /node1/ at the same level
      if [ $(ls -l ${RUNDIR}/${TRIAL}/*/*core* 2> /dev/null | wc -l) -ge 1 -o "$(${SCRIPT_PWD}/OLD/text_string.sh ${RUNDIR}/${TRIAL}/log/master.err 2> /dev/null)" != "" -o "$(${SCRIPT_PWD}/OLD/text_string.sh ${RUNDIR}/${TRIAL}/node1/node1.err 2> /dev/null)" != "" -o "$(${SCRIPT_PWD}/OLD/text_string.sh ${RUNDIR}/${TRIAL}/node2/node2.err 2> /dev/null)" != "" -o "$(${SCRIPT_PWD}/OLD/text_string.sh ${RUNDIR}/${TRIAL}/node3/node3.err 2> /dev/null)" != "" ]; then
        if [ $(ls -l ${RUNDIR}/${TRIAL}/*/*core* 2> /dev/null | wc -l) -ge 1 ]; then
          if [[ ${MDG} -eq 1 ]]; then
            for j in $(seq 1 ${NR_OF_NODES}); do
              if [ $(ls -l ${RUNDIR}/${TRIAL}/node${j}/*core* 2> /dev/null | wc -l) -ge 1 ]; then
                export GALERA_ERROR_LOG=${RUNDIR}/${TRIAL}/node${j}/node${j}.err
                export GALERA_CORE_LOC=$(ls -t ${RUNDIR}/${TRIAL}/node${j}/*core* 2> /dev/null)
                export node=node${j}
                echoit "mysqld coredump detected at $(ls ${RUNDIR}/${TRIAL}/node${j}/*core* 2> /dev/null)"
                handle_bugs
              fi
            done
          else
            echoit "mysqld coredump detected at $(ls ${RUNDIR}/${TRIAL}/*/*core* 2> /dev/null)"
            handle_bugs
          fi
        else
          echoit "mysqld crash detected in the error log via old text_string.sh scan #TODO" #TODO marker is placed here because the new_text_string.sh may not be able to handle all cases correctly yet (like where there is an error log with a crash, but no coredump - though that may be OOS caused also). Also adding a #TODO marker into ${RUNDIR}/${TRIAL}/MYBUG to make it easy to scan for these trials.
          echo "#TODO" > ${RUNDIR}/${TRIAL}/MYBUG
        fi
        if [[ ${MDG} -eq 0 && ${GRP_RPL} -eq 0 && -r ${WORKDIR}/${TRIAL}/log/master.err ]]; then
          echoit "Bug found (as per error log)(as per old text_string.sh): $(${SCRIPT_PWD}/OLD/text_string.sh ${WORKDIR}/${TRIAL}/log/master.err)"
        elif [[ ${MDG} -eq 1 || ${GRP_RPL} -eq 1 && -r ${WORKDIR}/${TRIAL}/node1/node1.err ]]; then
          if [ "$(${SCRIPT_PWD}/OLD/text_string.sh ${WORKDIR}/${TRIAL}/node1/node1.err 2> /dev/null)" != "" ]; then echoit "Bug found in MDG/GR node #1 (as per error log)(as per old text_string.sh): $(${SCRIPT_PWD}/OLD/text_string.sh ${RUNDIR}/${TRIAL}/node1/node1.err)"; fi
          if [ "$(${SCRIPT_PWD}/OLD/text_string.sh ${WORKDIR}/${TRIAL}/node2/node2.err 2> /dev/null)" != "" ]; then echoit "Bug found in MDG/GR node #2 (as per error log)(as per old text_string.sh): $(${SCRIPT_PWD}/OLD/text_string.sh ${RUNDIR}/${TRIAL}/node2/node2.err)"; fi
          if [ "$(${SCRIPT_PWD}/OLD/text_string.sh ${WORKDIR}/${TRIAL}/node3/node3.err 2> /dev/null)" != "" ]; then echoit "Bug found in MDG/GR node #3 (as per error log)(as per old text_string.sh): $(${SCRIPT_PWD}/OLD/text_string.sh ${RUNDIR}/${TRIAL}/node3/node3.err)"; fi
        fi
        if [ ${TRIAL_TO_SAVE} -eq 1 ]; then
          savetrial
          TRIAL_SAVED=1
        fi
      elif [ $(grep "SIGKILL myself" ${RUNDIR}/${TRIAL}/log/master.err 2> /dev/null | wc -l) -ge 1 ]; then
        echoit "'SIGKILL myself' detected in the mysqld error log for this trial; saving this trial"
        savetrial
        TRIAL_SAVED=1
      elif [[ ${CRASH_CHECK} -eq 1 ]]; then
        echoit "Saving this trial for backup restore analysis"
        savetrial
        TRIAL_SAVED=1
        CRASH_CHECK=0
      elif [ $(grep "MySQL server has gone away" ${RUNDIR}/${TRIAL}/*.sql 2> /dev/null | wc -l) -ge 200 -a ${TIMEOUT_REACHED} -eq 0 ]; then
        echoit "'MySQL server has gone away' detected >=200 times for this trial, and the pquery timeout was not reached; saving this trial for further analysis"
        savetrial
        TRIAL_SAVED=1
      elif [ $(grep -im1 --binary-files=text "=ERROR:" ${RUNDIR}/${TRIAL}/log/master.err 2> /dev/null | wc -l) -ge 1 ]; then
        echoit "ASAN issue detected in the mysqld error log for this trial; saving this trial"
        savetrial
        TRIAL_SAVED=1
      elif [ $(grep -im1 --binary-files=text "ThreadSanitizer:" ${RUNDIR}/${TRIAL}/log/master.err 2> /dev/null | wc -l) -ge 1 ]; then
        echoit "TSAN issue detected in the mysqld error log for this trial; saving this trial"
        savetrial
        TRIAL_SAVED=1
      elif [ $(grep -im1 --binary-files=text "runtime error:" ${RUNDIR}/${TRIAL}/log/master.err 2> /dev/null | wc -l) -ge 1 ]; then
        echoit "UBSAN issue detected in the mysqld error log for this trial; saving this trial"
        savetrial
        TRIAL_SAVED=1
      elif [ ${SAVE_TRIALS_WITH_CORE_OR_VALGRIND_ONLY} -eq 0 ]; then
        echoit "Saving full trial outcome (as SAVE_TRIALS_WITH_CORE_OR_VALGRIND_ONLY=0 and so trials are saved irrespective of whether an issue was detected or not)"
        savetrial
        TRIAL_SAVED=1
      elif [[ ${PQUERY3} -eq 1 ]]; then
        if [ ${TRIAL} -gt 1 ]; then
          savetrial
          removelasttrial
        else
          savetrial
        fi
        TRIAL_SAVED=1
      elif [[ ${PXB_CHECK} -eq 1 ]]; then
        echoit "Saving this trial for backup restore analysis"
        savetrial
        TRIAL_SAVED=1
        PXB_CHECK=0
      else
        if [ ${SAVE_SQL} -eq 1 ]; then
          if [ "${VALGRIND_RUN}" == "1" ]; then
            if [ ${VALGRIND_ERRORS_FOUND} -ne 1 ]; then
              echoit "Not saving anything for this trial (as SAVE_TRIALS_WITH_CORE_OR_VALGRIND_ONLY=1, and no issue was seen), except the SQL trace (as SAVE_SQL=1)"
            fi
          else
            echoit "Not saving anything for this trial (as SAVE_TRIALS_WITH_CORE_OR_VALGRIND_ONLY=1, and no issue was seen), except the SQL trace (as SAVE_SQL=1)"
          fi
          savesql
        else
          if [ "${VALGRIND_RUN}" == "1" ]; then
            if [ ${VALGRIND_ERRORS_FOUND} -ne 1 ]; then
              echoit "Not saving anything for this trial (as SAVE_TRIALS_WITH_CORE_OR_VALGRIND_ONLY=1 and SAVE_SQL=0, and no issue was seen)"
            fi
          else
            echoit "Not saving anything for this trial (as SAVE_TRIALS_WITH_CORE_OR_VALGRIND_ONLY=1 and SAVE_SQL=0, and no issue was seen)"
          fi
        fi
      fi
    fi
    if [ ${TRIAL_SAVED} -eq 0 ]; then
      removetrial
    fi
  fi
}

# Setup
if [[ "${INFILE}" == *".tar."* ]]; then
  echoit "The input file is a compressed tarball. This script will untar the file in the same location as the tarball. Please note this overwrites any existing files with the same names as those in the tarball, if any. If the sql input file needs patching (and is part of the github repo), please remember to update the tarball with the new file."
  STORECURPWD=${PWD}
  cd $(echo ${INFILE} | sed 's|/[^/]\+\.tar\..*|/|') || exit 1 # Change to the directory containing the input file
  tar -xf ${INFILE}
  cd ${STORECURPWD} || exit 1
  INFILE=$(echo ${INFILE} | sed 's|\.tar\..*||')
fi
rm -Rf ${WORKDIR} ${RUNDIR}
diskspace
mkdir ${WORKDIR} ${WORKDIR}/log ${RUNDIR}
chmod -R +rX ${WORKDIR}
echo "grep -E '^BASEDIR=|^INFILE=|^THREADS=|^MYEXTRA=|^MYINIT=|^ADD_RANDOM_OPTIONS=' pquery*run*conf | sed 's|   #.*||;s|ADD_RANDOM|RND|;s|=|: \\t|'" > ${WORKDIR}/i
echo "find . | grep '_out$' | xargs -I{} wc -l {} | sort -n | sort -h" > ${WORKDIR}/my
chmod +x ${WORKDIR}/i ${WORKDIR}/my
WORKDIRACTIVE=1
ONGOING=
# User for recovery testing
echo "CREATE USER recovery@'%';" > ${WORKDIR}/recovery-user.sql
echo "GRANT ALL ON *.* TO recovery@'%';" >> ${WORKDIR}/recovery-user.sql
echo "FLUSH PRIVILEGES;" >> ${WORKDIR}/recovery-user.sql
# User for root access after a trial is done (which may have modified user table)
# TODO: add a mysql.user touch/creation here in case that tible was removed/wiped or broken
# i.e. DROP TABLE mysql.user then CREATE TABLE, but may be version-specific
echo "CREATE USER root@'%';" > ${WORKDIR}/root-access.sql
echo "GRANT ALL ON *.* TO root@'%';" >> ${WORKDIR}/root-access.sql
echo "FLUSH PRIVILEGES;" >> ${WORKDIR}/root-access.sql
if [[ "${MDG}" -eq 0 && "${GRP_RPL}" -eq 0 ]]; then
  ONGOING="Workdir: ${WORKDIR} | Rundir: ${RUNDIR} | Basedir: ${BASEDIR} "
  echoit "${ONGOING}"
elif [[ "${MDG}" -eq 1 ]]; then
  ONGOING="Workdir: ${WORKDIR} | Rundir: ${RUNDIR} | Basedir: ${BASEDIR} | MDG Mode: TRUE"
  echoit "${ONGOING}"
  echoit "Number of Galera Cluster nodes: $NR_OF_NODES"
  if [[ "${MDG_SST_METHOD}" -eq 1 ]] ; then
    echoit "MDG SST Method: 'rsync'"
  else
    echoit "MDG SST Method: 'mariabackup'"
  fi
  if [[ "${MDG_CLUSTER_RUN}" -eq 1 ]]; then
    echoit "MDG Cluster run: 'YES'"
  else
    echoit "MDG Cluster run: 'NO'"
  fi
  if [[ "${ENCRYPTION_RUN}" -eq 1 ]]; then
    echoit "MDG Encryption run: 'YES'"
  else
    echoit "MDG Encryption run: 'NO'"
  fi
elif [[ "${GRP_RPL}" -eq 1 ]]; then
  ONGOING="Workdir: ${WORKDIR} | Rundir: ${RUNDIR} | Basedir: ${BASEDIR} | Group Replication Mode: TRUE"
  echoit "${ONGOING}"
  if [[ "${GRP_RPL_CLUSTER_RUN}" -eq 1 ]]; then
    echoit "Group Replication Cluster run: 'YES'"
  else
    echoit "Group Replication Cluster run: 'NO'"
  fi
fi
echo "[$(date +'%D %T')] ${ONGOING}" >> ~/ongoing.pquery-runs.txt
ONGOING=
if [[ "${RR_TRACING}" -eq 1 ]]; then
  echoit "RR Tracing enabled: YES"
else
  echoit "RR Tracing enabled: NO"
fi

if [[ "${PXB_CRASH_RUN}" -eq 1 ]]; then
  echoit "PXB Base: ${PXB_BASEDIR}"
fi
# Start vault server for pquery encryption run
if [[ "${WITH_KEYRING_VAULT}" -eq 1 ]]; then
  echoit "Setting up vault server"
  diskspace
  mkdir ${WORKDIR}/vault
  rm -rf ${WORKDIR}/vault/*
  killall vault
  if [[ $MDG -eq 1 ]]; then
    ${SCRIPT_PWD}/vault_test_setup.sh --workdir=${WORKDIR}/vault --setup-mdg-mount-points --use-ssl
  else
    ${SCRIPT_PWD}/vault_test_setup.sh --workdir=${WORKDIR}/vault --use-ssl
    #MYEXTRA="$MYEXTRA --early-plugin-load=keyring_vault.so --loose-keyring_vault_config=${WORKDIR}/vault/keyring_vault.cnf"
  fi
fi

if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 ]; then
  echoit "mysqld Start Timeout: ${MYSQLD_START_TIMEOUT} | Client Threads: ${THREADS} | Trials: ${TRIALS} | Statements per trial: ${QC_NR_OF_STATEMENTS_PER_TRIAL} | Primary Engine: ${QC_PRI_ENGINE} | Secondary Engine: ${QC_SEC_ENGINE} | Eliminate Known Bugs: ${ELIMINATE_KNOWN_BUGS}"
else
  echoit "mysqld Start Timeout: ${MYSQLD_START_TIMEOUT} | Client Threads: ${THREADS} | Queries/Thread: ${QUERIES_PER_THREAD} | Trials: ${TRIALS} | Save coredump/valgrind issue trials only: $(if [ ${SAVE_TRIALS_WITH_CORE_OR_VALGRIND_ONLY} -eq 1 ]; then
    echo -n 'TRUE'
    if [ ${SAVE_SQL} -eq 1 ]; then echo ' + save all SQL traces'; else echo ''; fi
  else echo 'FALSE'; fi)"
fi

if [[ ${REPL} -eq 1 ]]; then
  if [[ $REPLICATION_SHUTDOWN_OR_KILL -eq 1 ]]; then
    echoit "Replication testing: YES | Mode: Normal shutdown"
  else
    echoit "Replication testing: YES | Mode: Forceful shutdown using kill -9 command"
  fi
fi

if [ "${PRE_SHUFFLE_SQL}" == "1" ]; then
  echoit "PRE_SHUFFLE_SQL=1: This script will randomly pre-shuffle ${PRE_SHUFFLE_SQL_LINES} lines of SQL into a temporary file in ${PRE_SHUFFLE_DIR} and reuse this file for ${PRE_SHUFFLE_TRIALS_PER_SHUFFLE} trial(s)"
fi

 
SQL_INPUT_TEXT="SQL file used: ${INFILE}"
if [ ${USE_GENERATOR_INSTEAD_OF_INFILE} -eq 1 ]; then
  if [ ${ADD_INFILE_TO_GENERATED_SQL} -eq 0 ]; then
    SQL_INPUT_TEXT="Using SQL Generator"
  else
    SQL_INPUT_TEXT="Using SQL Generator combined with SQL file ${INFILE}"
  fi
fi
echoit "Valgrind run: $(if [ "${VALGRIND_RUN}" == "1" ]; then echo -n 'TRUE'; else echo -n 'FALSE'; fi) | pquery timeout: ${PQUERY_RUN_TIMEOUT} | ${SQL_INPUT_TEXT} $(if [ ${THREADS} -ne 1 ]; then echo -n "| Testcase size (chunked from infile): ${MULTI_THREADED_TESTC_LINES}"; fi)"
echoit "pquery Binary: ${PQUERY_BIN}"
if [ "${MYINIT}" != "" ]; then echoit "MYINIT: ${MYINIT}"; fi
if [ "${MYSAFE}" != "" ]; then echoit "MYSAFE: ${MYSAFE}"; fi
if [ "${MYEXTRA}" != "" ]; then echoit "MYEXTRA: ${MYEXTRA}"; fi
if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 -a "${MYEXTRA2}" != "" ]; then echoit "MYEXTRA2: ${MYEXTRA2}"; fi
echoit "Making a copy of the pquery binary used (${PQUERY_BIN}) to ${WORKDIR}/ (handy for later re-runs/reference etc.)"
cp ${PQUERY_BIN} ${WORKDIR}
echoit "Making a copy of this script (${SCRIPT}) to ${WORKDIR}/ for reference & adding a pquery- prefix (this avoids pquery-prep-run not finding the script)..." # pquery- prefix avoids pquer-prep-red.sh script-locating issues if this script had been renamed to a name without 'pquery' in it.
cp ${SCRIPT_AND_PATH} ${WORKDIR}/pquery-${SCRIPT}
echoit "Making a copy of the configuration file (${CONFIGURATION_FILE}) to ${WORKDIR}/ for reference & adding a pquery- prefix (this avoids pquery-prep-run not finding the script)..." # pquery- prefix avoids pquer-prep-red.sh script-locating issues if this script had been renamed to a name without 'pquery' in it.
SHORT_CONFIGURATION_FILE=$(echo ${CONFIGURATION_FILE} | sed 's|.*/[\.]*||')
cp ${SCRIPT_PWD}/${CONFIGURATION_FILE} ${WORKDIR}/pquery-${SHORT_CONFIGURATION_FILE}
if [ ${STORE_COPY_OF_INFILE} -eq 1 ]; then
  echoit "Making a copy of the SQL input file used (${INFILE}) to ${WORKDIR}/ for reference..."
  cp ${INFILE} ${WORKDIR}
fi

# Get version specific options
MID=
if [ -r ${BASEDIR}/scripts/mysql_install_db ]; then MID="${BASEDIR}/scripts/mysql_install_db"; fi
if [ -r ${BASEDIR}/bin/mysql_install_db ]; then MID="${BASEDIR}/bin/mysql_install_db"; fi
START_OPT="--core-file"                                  # Compatible with 5.6,5.7,8.0
INIT_OPT="--no-defaults --initialize-insecure ${MYINIT}" # Compatible with 5.7,8.0 (mysqld init)
INIT_TOOL="${BIN}"                                       # Compatible with 5.7,8.0 (mysqld init), changed to MID later if version <=5.6
VERSION_INFO=$(${BIN} --version | grep -oe '[58]\.[01567]' | head -n1)
VERSION_INFO_2=$(${BIN} --version | grep --binary-files=text -i 'MariaDB' | grep -oe '10\.[1-9][0-9]*' | head -n1)
if [ -z "${VERSION_INFO_2}" ]; then VERSION_INFO_2="NA"; fi

if [ "${VERSION_INFO_2}" == "10.4" -o "${VERSION_INFO_2}" == "10.5" -o "${VERSION_INFO_2}" == "10.6" -o "${VERSION_INFO_2}" == "10.7" -o "${VERSION_INFO_2}" == "10.8" -o "${VERSION_INFO_2}" == "10.9" -o "${VERSION_INFO_2}" == "10.10" -o "${VERSION_INFO_2}" == "10.11" -o "${VERSION_INFO_2}" == "10.12" -o "${VERSION_INFO_2}" == "10.13" ]; then
  VERSION_INFO="5.6"
  INIT_TOOL="${BASEDIR}/scripts/mariadb-install-db"
  INIT_OPT="--no-defaults --force --auth-root-authentication-method=normal ${MYINIT}"
  START_OPT="--core-file --core"
elif [ "${VERSION_INFO_2}" == "10.1" -o "${VERSION_INFO_2}" == "10.2" -o "${VERSION_INFO_2}" == "10.3" ]; then
  VERSION_INFO="5.1"
  INIT_TOOL="${BASEDIR}/scripts/mysql_install_db"
  INIT_OPT="--no-defaults --force ${MYINIT}"
  START_OPT="--core"
elif [ "${VERSION_INFO}" == "5.1" -o "${VERSION_INFO}" == "5.5" -o "${VERSION_INFO}" == "5.6" ]; then
  if [ -z "${MID}" ]; then
    echoit "Assert: Version was detected as ${VERSION_INFO}, yet ./scripts/mysql_install_db nor ./bin/mysql_install_db is present!"
    exit 1
  fi
  INIT_TOOL="${MID}"
  INIT_OPT="--no-defaults --force ${MYINIT}"
  START_OPT="--core"
elif [ "${VERSION_INFO}" != "5.7" -a "${VERSION_INFO}" != "8.0" ]; then
  echo "=========================================================================================="
  echo "WARNING: mysqld (${BIN}) version detection failed. This is likely caused by using this script with a non-supported distribution or version of mysqld, or simply because this directory is not a proper MySQL[-fork] base directory. Please expand this script to handle (which shoud be easy to do). Even so, the scipt will now try and continue as-is, but this may and will likely fail."
  echo "=========================================================================================="
fi

echoit "Generating datadir template (using mysql_install_db or mysqld --init)..."
if [ ! -r ${INIT_TOOL} ]; then  # TODO: This is a hack, improve it
  ALT_INIT_TOOL="$(echo "${INIT_TOOL}" | sed 's|mariadb-install-db|mysql_install_db|')"
  if [ -r ${ALT_INIT_TOOL} ]; then
    echoit "Swapped ${INIT_TOOL} for ${ALT_INIT_TOOL}! (It's a hack, please improve this script to handle this version of MariaDB better)"
    INIT_TOOL="${ALT_INIT_TOOL}"
    ALT_INIT_TOOL=
  else
    echoit "Assert: neither ${INIT_TOOL} nor ${ALT_INIT_TOOL} were found/readable, please check. Terminating."
    exit 1
  fi
fi

if [[ ${MDG} -eq 0 && ${GRP_RPL} -eq 0 ]]; then
  echoit "Making a copy of the mysqld used to ${RUNDIR} for in-run coredump analysis..."
  cp ${BIN} ${RUNDIR}
  echoit "${BIN} ${RUNDIR}"
  echoit "Making a copy of the mysqld used to ${WORKDIR}/mysqld (handy for coredump analysis and manual bundle creation)..."
  mkdir ${WORKDIR}/mysqld
  cp ${BIN} ${WORKDIR}/mysqld
  echoit "Making a copy of the ldd files required for mysqld core analysis to ${WORKDIR}/mysqld..."
  PWDTMPSAVE="${PWD}"
  cd ${WORKDIR}/mysqld || exit 1
  ${SCRIPT_PWD}/ldd_files.sh
  cd ${PWDTMPSAVE} || exit 1

  ${INIT_TOOL} ${INIT_OPT} --basedir=${BASEDIR} --datadir=${WORKDIR}/data.template > ${WORKDIR}/log/mysql_install_db.txt 2>&1
  # Sysbench dataload
  diskspace
  if [ ${SYSBENCH_DATALOAD} -eq 1 ]; then
    echoit "Starting mysqld for sysbench data load. Error log is stored at ${WORKDIR}/data.template/master.err"
    CMD="${BIN} --basedir=${BASEDIR} --datadir=${WORKDIR}/data.template --tmpdir=${WORKDIR}/data.template \
     --core-file --port=$PORT --pid_file=${WORKDIR}/data.template/pid.pid --socket=${WORKDIR}/data.template/socket.sock \
     --log-output=none --log-error=${WORKDIR}/data.template/master.err"
    diskspace
    $CMD > ${WORKDIR}/data.template/master.err 2>&1 &
    MPID="$!"

    for X in $(seq 0 ${MYSQLD_START_TIMEOUT}); do
      sleep 1
      if ${BASEDIR}/bin/mysqladmin -uroot -S${WORKDIR}/data.template/socket.sock ping > /dev/null 2>&1; then
        break
      fi
      if [ "${MPID}" == "" ]; then
        echoit "Assert! ${MPID} empty. Terminating!"
        exit 1
      fi
    done
    # Sysbench run for data load
    /usr/bin/sysbench --test=${SCRIPT_PWD}/sysbench_scripts/parallel_prepare.lua --num-threads=1 --oltp-tables-count=1 --oltp-table-size=1000000 --mysql-db=test --mysql-user=root --db-driver=mysql --mysql-socket=${WORKDIR}/data.template/socket.sock run > ${WORKDIR}/data.template/sysbench_prepare.txt 2>&1

    # Terminate mysqld
    timeout --signal=9 20s ${BASEDIR}/bin/mysqladmin -uroot -S${WORKDIR}/data.template/socket.sock shutdown > /dev/null 2>&1
    (
      sleep 0.2
      kill -9 ${MPID} > /dev/null 2>&1
      timeout -k5 -s9 5s wait ${MPID} > /dev/null 2>&1
    ) & # Terminate mysqld
  fi
  echo "${MYEXTRA}${MYSAFE}" | if grep -qi "innodb[_-]log[_-]checksum[_-]algorithm"; then
    # Ensure that if MID created log files with the standard checksum algo, whilst we start the server with another one, that log files are re-created by mysqld
    rm ${WORKDIR}/data.template/ib_log*
  fi
  if [ "$PMM" == "1" ]; then
    echoit "Initiating PMM configuration"
    if ! docker ps -a | grep 'pmm-data' > /dev/null; then
      docker create -v /opt/prometheus/data -v /opt/consul-data -v /var/lib/mysql --name pmm-data percona/pmm-server:${PMM_VERSION_CHECK} /bin/true > /dev/null
      check_cmd $? "pmm-server docker creation failed"
    fi
    if ! docker ps -a | grep 'pmm-server' | grep ${PMM_VERSION_CHECK} | grep -v pmm-data > /dev/null; then
      docker run -d -p 80:80 --volumes-from pmm-data --name pmm-server --restart always percona/pmm-server:${PMM_VERSION_CHECK} > /dev/null
      check_cmd $? "pmm-server container creation failed"
    elif ! docker ps | grep 'pmm-server' | grep ${PMM_VERSION_CHECK} > /dev/null; then
      docker start pmm-server > /dev/null
      check_cmd $? "pmm-server container not started"
    fi
    if [[ ! -e $(which pmm-admin 2> /dev/null) ]]; then
      echoit "Assert! The pmm-admin client binary was not found, please install the pmm-admin client package"
      exit 1
    else
      PMM_ADMIN_VERSION=$(sudo pmm-admin --version)
      if [ "$PMM_ADMIN_VERSION" != "${PMM_VERSION_CHECK}" ]; then
        echoit "Assert! The pmm-admin client version is $PMM_ADMIN_VERSION. Required version is ${PMM_VERSION_CHECK}"
        exit 1
      else
        IP_ADDRESS=$(ip route get 8.8.8.8 | head -1 | cut -d' ' -f8)
        sudo pmm-admin config --server $IP_ADDRESS
      fi
    fi
  fi
elif [[ ${MDG} -eq 1 || ${GRP_RPL} -eq 1 ]]; then
  echoit "Making a copy of the mysqld used to ${RUNDIR} for in-run coredump analysis..."
  cp ${BIN} ${RUNDIR}
  echoit "Making a copy of the mysqld used to ${WORKDIR}/mysqld (handy for coredump analysis and manual bundle creation)..."
  mkdir ${WORKDIR}/mysqld
  cp ${BIN} ${WORKDIR}/mysqld
  echoit "Making a copy of the ldd files required for mysqld core analysis to ${WORKDIR}/mysqld..."
  PWDTMPSAVE=${PWD}
  cd ${WORKDIR}/mysqld || exit 1
  ${SCRIPT_PWD}/ldd_files.sh
  cd ${PWDTMPSAVE} || exit 1
  if [[ ${MDG} -eq 1 ]]; then
    echoit "Creating ${NR_OF_NODES} MariaDB Galera Node data directory templates..."
    mdg_startup startup
    sleep 2
    for i in $(seq 1 ${NR_OF_NODES}); do
      if ${BASEDIR}/bin/mysqladmin -uroot -S${WORKDIR}/node${i}.template/node${i}_socket.sock ping > /dev/null 2>&1; then
        echoit "MariaDB Galera 'node${i}.template' data directory template creation started"
      else
        echoit "Assert: MariaDB Galera 'node${i}.template' data directory template creation failed..."
        exit 1
      fi
    done
    echoit "Shutting down ${NR_OF_NODES} MariaDB Galera data directory template creation nodes..."
    for i in $(seq ${NR_OF_NODES} -1 1); do
      ${BASEDIR}/bin/mysqladmin -uroot -S${WORKDIR}/node${i}.template/node${i}_socket.sock shutdown > /dev/null 2>&1
    done
    echoit "Completed ${NR_OF_NODES} Node MDG data templates creations"
  elif [[ ${GRP_RPL} -eq 1 ]]; then
    echoit "Creating 3 Group Replication data directory templates..."
    gr_startup startup
    sleep 5
    if ${BASEDIR}/bin/mysqladmin -uroot -S${WORKDIR}/node1.template/node1_socket.sock ping > /dev/null 2>&1; then
      echoit "Group Replication 'node1.template' data directory template creation started"
    else
      echoit "Assert: Group Replication 'node1.template' data directory template creation failed..."
      exit 1
    fi
    if ${BASEDIR}/bin/mysqladmin -uroot -S${WORKDIR}/node2.template/node2_socket.sock ping > /dev/null 2>&1; then
      echoit "Group Replication 'node2.template' data directory template creation started"
    else
      echoit "Assert: Group Replication 'node2.template' data directory template creation failed..."
      exit 1
    fi
    if ${BASEDIR}/bin/mysqladmin -uroot -S${WORKDIR}/node3.template/node3_socket.sock ping > /dev/null 2>&1; then
      echoit "Group Replication 'node3.template' data directory template creation started"
    else
      echoit "Assert: Group Replication 'node3.template' data directory template creation failed..."
      exit 1
    fi
    echoit "Shutting down 3 Group Replication data directory template creation nodes..."
    ${BASEDIR}/bin/mysqladmin -uroot -S${WORKDIR}/node3.template/node3_socket.sock shutdown > /dev/null 2>&1
    ${BASEDIR}/bin/mysqladmin -uroot -S${WORKDIR}/node2.template/node2_socket.sock shutdown > /dev/null 2>&1
    ${BASEDIR}/bin/mysqladmin -uroot -S${WORKDIR}/node1.template/node1_socket.sock shutdown > /dev/null 2>&1
    echoit "Completed 3 Node Group Replication data templates creations"
  fi
fi

# Start actual pquery testing
echoit "Starting pquery testing iterations..."
COUNT=0
for X in $(seq 1 ${TRIALS}); do
  pquery_test
  COUNT=$(($COUNT + 1))
done
# All done, wrap up pquery run
echoit "pquery finished requested number of trials (${TRIALS})... Terminating..."
if [[ ${MDG} -eq 1 || ${GRP_RPL} -eq 1 ]]; then
  echoit "Cleaning up any leftover processes..."
  KILL_PIDS=$(ps -ef | grep "$RANDOMD" | grep -v "grep" | awk '{print $2}' | tr '\n' ' ')
  if [ "${KILL_PIDS}" != "" ]; then
    echoit "Terminating the following PID's: ${KILL_PIDS}"
    kill -9 ${KILL_PIDS} > /dev/null 2>&1
  fi
else
  (ps -ef | grep 'node[0-9]_socket' | grep ${RUNDIR} | grep -v grep | awk '{print $2}' | xargs kill -9 > /dev/null 2>&1 || true)
  sleep 2
  sync
fi
echoit "Done. Attempting to cleanup the pquery rundir ${RUNDIR}..."
rm -Rf ${RUNDIR}
echoit "The results of this run can be found in the workdir ${WORKDIR}..."
echoit "Done. Exiting $0 with exit code 0..."
exit 0
