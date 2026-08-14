#!/bin/bash
# Created by Roel Van de Paar, Percona LLC
# Updated by Ramesh Sivaraman, Percona LLC
# Updated by Mohit Joshi, Percona LLC
# Updated by Roel Van de Paar, MariaDB
# Updated by Ramesh Sivaraman, MariaDB

# ========================================= User configurable variables
# Note: if an option is passed to this script, it will use that option as the configuration file instead, for example ./pquery-run.sh pquery-run-MD105.conf
CONFIGURATION_FILE=pquery-run.conf # Do not use any path specifiers, the .conf file should be in the same path as pquery-run.sh
ADV_FILTER_LIST="debug_dbug|debug_|_debug|debug[ \t]*=|'\+d,|shutdown|release|kill|aria_encrypt_tables|_size|length_|_length|timer|schedule|event|csv|recursive|oracle|track_system_variables|^#|^\-\-|set.*ndb_|^let|^[ \t]*$"  # The advanced filter, applied to the per-trial SQL when a configuration file sets ADV_FILTER_SQL=1, and to the all-disk SQL pool always. Keep ADV_FILTER_SQL=0 for a purpose-built input file, whose own queries this list would remove, a debug_dbug statement for example. FILTER_SQL=1 is the separate, lighter filter in mariadb-qa/filter.sql, and the two can be combined. This list is a global variable of this script, not bound to a configuration file # TODO: consider moving it to config files

# ========================================= Improvement ideas
# * SAVE_TRIALS_WITH_BUGS_ONLY=0 (These likely include some of the 'SIGKILL' issues - no core but terminated)
# * SQL hashing s/t2/t1/, hex values "0x"
# * Full MTR grammar on one-liners
# * Interleave all statements with another that is likely to cause issues, for example "USE mysql". This is already done regularly with feature testing through SQL interleaving, but it could be done per statement. For example, every second line a SELECT, next SQL file every second line an UPDATE, next SQL file every second line an ALTER etc. then use all (do not combine; too large input) files either randomly or sequentially. And instead of just SELECT, or UPDATE, or ALTER etc. use sql-interleaving to make a variety of 9 per statement.
# * It would be possible to output all new bugs to a flat text file, so that when the new bug detection is operating, it will check not only known_bugs.strings but also this new flat text file, and if a bug is seen already, it could just delete the trial. This will only leave one trial in place for testcase reduction, but over time and over different runs this should be quite fine - especially as showstopper like bugs will be all over the runs and hence will reproduce every new run with ease. For the moment, pquery-eliminate-dups.sh reduces the max number to 3, so that is quite fine also.

# ========================================= MAIN CODE

# Disables history substitution and avoids  -bash: !: event not found  like errors
set +H

# Shrink mariadbd cores: anon-private (stacks/heap) + ELF headers only (0x11);
# drops anon-shared (InnoDB buffer pool) and private hugepages. Inherited by
# every forked child, including the mariadbd CMD launches via eval.
echo 0x11 > /proc/self/coredump_filter 2>/dev/null

# Cap any gdb / elfutils debuginfod fetch attempt that escapes the in-script
# `-iex set debuginfod enabled off` covers, so a single missed call site
# cannot stall a trial for 7+ min on remote symbol lookups.
export DEBUGINFOD_TIMEOUT=13
export DEBUGINFOD_PROGRESS=0

# Discourage OOM killer on this process
sudo echo -1000 > /proc/$$/oom_score_adj

# MariaDB specific variables
DISABLE_TOKUDB_AND_JEMALLOC=1

# Internal variables: DO NOT CHANGE!
SCRIPT_AND_PATH=$(readlink -f $0)
SCRIPT=$(echo ${SCRIPT_AND_PATH} | sed 's|.*/||')
SCRIPT_PWD=$(dirname $(readlink -f "${0}"))
RANDOM_BIN="${SCRIPT_PWD}/random"  # xoshiro256++ entropy source; build it with ./build_random.sh
if [ ! -x "${RANDOM_BIN}" ]; then
  echo "Assert: ${RANDOM_BIN} is missing or not executable. Run ${SCRIPT_PWD}/build_random.sh"
  exit 1
fi
# 6-digit workdir/rundir number, uniform over 000000..999999. Redrawn while any of the
# directories a configuration file may build from it is already taken, so a repeat number
# never lands on a live run
RANDOMD=$(${RANDOM_BIN} --digits 6)
while [ -d "/data/${RANDOMD}" -o -d "/sda/${RANDOMD}" -o -d "/dev/shm/${RANDOMD}" -o -d "${HOME}/test_p/${RANDOMD}" ]; do
  RANDOMD=$(${RANDOM_BIN} --digits 6)
done
WORKDIRACTIVE=0
SAVED=0
ALREADY_KNOWN=0
TRIAL=0
MYSQLD_START_TIMEOUT=60
TIMEOUT_REACHED=0
PQUERY3=0
NEWBUGS=0
TRIAL_SQL=  # The assembled per-trial SQL input file, the one pquery reads. Set by assemble_trial_sql()
TRIAL_SAVED=0
SAN_KNOWN_BUGS_DROPPED_FROM_ERROR_LOG_FLAG=0  # Reset to 0 at the start of each trial, ref top of pquery_test()
ENCRYPTION_OPTIONS=''  # Configured with per-trial options when ENABLE_ENCRYPTION=1 in the .conf configuration file

# Set SAN options
# https://github.com/google/sanitizers/wiki/SanitizerCommonFlags
# https://github.com/google/sanitizers/wiki/AddressSanitizerFlags
# https://clang.llvm.org/docs/UndefinedBehaviorSanitizer.html
# https://github.com/google/sanitizers/wiki/AddressSanitizerLeakSanitizer (LSAN is enabled by default except on OS X)
# detect_invalid_pointer_pairs changed from 1 to 3 at start of 2021 (effectively used since)
export ASAN_OPTIONS=suppressions=${SCRIPT_PWD}/ASAN.filter:quarantine_size_mb=512:atexit=0:detect_invalid_pointer_pairs=3:dump_instruction_bytes=1:abort_on_error=1:allocator_may_return_null=1
# check_initialization_order=1 cannot be used due to https://jira.mariadb.org/browse/MDEV-24546 TODO
# detect_stack_use_after_return=1 will likely require thread_stack increase (check error log after ./all) TODO
#export ASAN_OPTIONS=suppressions=${SCRIPT_PWD}/ASAN.filter:quarantine_size_mb=512:atexit=0:detect_invalid_pointer_pairs=3:dump_instruction_bytes=1:abort_on_error=1:allocator_may_return_null=1
export UBSAN_OPTIONS=suppressions=${SCRIPT_PWD}/UBSAN.filter:print_stacktrace=1:report_error_type=1
export TSAN_OPTIONS=suppressions=${SCRIPT_PWD}/TSAN.filter:suppress_equal_stacks=1:history_size=7:second_deadlock_stack=1:verbosity=1
export MSAN_OPTIONS=abort_on_error=1:poison_in_dtor=0

# Print/Output function
echoit() {
  local ECHOIT_STYLE="${2}" ECHOIT_COLOR= ECHOIT_DIM=$'\e[2m' ECHOIT_RESET=$'\e[0m' ECHOIT_VAL= ECHOIT_FRAC= ECHOIT_EMPH= ECHOIT_MSG="$1"
  if [ -z "${ECHOIT_STYLE}" ]; then  # No style was passed, so classify the message. An explicit second argument always wins
    case "$1" in
      *'*** NEW '*'BUG ***'*)                            ECHOIT_STYLE=NEW;;
      'Bug found'*)                                      ECHOIT_STYLE=BUG; ECHOIT_EMPH='Bug found';;
      'SAN Bug found'*)                                  ECHOIT_STYLE=BUG; ECHOIT_EMPH='SAN Bug found';;
      'Error log bug found'*)                            ECHOIT_STYLE=BUG; ECHOIT_EMPH='Error log bug found';;
      'This is an already known'*|'Deleting trial as'*)   ECHOIT_STYLE=DIM;;
      Assert*|*'[ERROR]'*|*Aborting*|*'failed to start'*) ECHOIT_STYLE=ALERT;;  # After the bug and known bug lines, whose UniqueID can hold one of these words
      *'====== TRIAL #'*)                                ECHOIT_STYLE=TRIAL;;
      'Saving Trial:'*|'Saving full trial outcome'*)     ECHOIT_STYLE=GREEN;;
      *'coredump detected'*|*'shut down within'*|*'shutdown within'*) ECHOIT_STYLE=ORANGE;;
      'No Valgrind errors detected'*)                    ECHOIT_STYLE=DIMGREEN;;  # Ahead of the rule below, as this one is a clean result
      *' detected'*)                                     ECHOIT_STYLE=BUG;;  # A sanitizer, Valgrind, hang or SIGKILL finding, which carries no UniqueID
      Warning*|*'WARNING'*|*'Error:'*|*'no point in continuing'*|*'cannot be both active'*) ECHOIT_STYLE=ORANGE;;  # A framework problem worth reading
      *'No core present'*|*'was cut at'*|*'is missing or not executable'*|*' failed.'*|*'ERROR_LOG_SCAN_ISSUE is present'*) ECHOIT_STYLE=ORANGE;;  # Rare, and each one changes what the trial means
      *'pquery run details:'*)  # Tiered on the share of queries the server accepted. Random SQL makes a
        # mid-teens share a healthy trial and 30% a very good one, so orange means the server rejects more
        # than usual, and red means it rejects nearly everything
        ECHOIT_VAL="${1##*\(}"  # The share pquery reports, for example 7.50% were successful
        if [[ "${ECHOIT_VAL}" =~ ^([0-9]+)(\.([0-9]+))?% ]]; then
          ECHOIT_FRAC="${BASH_REMATCH[3]}00"  # The tiers carry two decimals, so compare in hundredths of a percent
          ECHOIT_VAL=$(( 10#${BASH_REMATCH[1]} * 100 + 10#${ECHOIT_FRAC:0:2} ))
          if [ ${ECHOIT_VAL} -ge 1500 ]; then ECHOIT_STYLE=GREEN; elif [ ${ECHOIT_VAL} -ge 750 ]; then ECHOIT_STYLE=ORANGE; else ECHOIT_STYLE=RED; fi
        fi;;
      'Input SQL: '*)  # Tiered on the seconds spent building the per-trial SQL, which is time not spent testing
        ECHOIT_VAL="${1##*built in }"
        if [[ "${ECHOIT_VAL}" =~ ^([0-9]+) ]]; then
          if [ ${BASH_REMATCH[1]} -ge 60 ]; then ECHOIT_STYLE=ALERT
          elif [ ${BASH_REMATCH[1]} -ge 25 ]; then ECHOIT_STYLE=RED
          elif [ ${BASH_REMATCH[1]} -ge 10 ]; then ECHOIT_STYLE=ORANGE
          else ECHOIT_STYLE=GREEN; fi
        fi;;
      Workdir:*|'RR Tracing'*|*'Start Timeout'*|'Replication testing:'*|'Valgrind run:'*|'pquery Binary:'*|MYSAFE:*|MYEXTRA:*) ECHOIT_STYLE=HEAD;;
      *) if [ "${TRIALS_STARTED}" == "1" ]; then ECHOIT_STYLE=DIM; fi;;  # A routine step inside the trial loop
    esac
  fi
  case "${ECHOIT_STYLE}" in  # The log file always holds the plain text
    GREEN) ECHOIT_COLOR=$'\e[32m';;    # A healthy measurement, or a trial saved
    ORANGE) ECHOIT_COLOR=$'\e[33m';;   # Attention, but no crash
    RED) ECHOIT_COLOR=$'\e[31m';;      # A crash, assert or sanitizer report
    BUG) ECHOIT_COLOR=$'\e[94m';;      # A UniqueID for a crash, assert or sanitizer report
    DIM) ECHOIT_COLOR=$'\e[2m';;       # A routine step
    DIMGREEN) ECHOIT_COLOR=$'\e[2;32m';;  # A healthy measurement on a line that should stay quiet
    HEAD) ECHOIT_COLOR=$'\e[1m';;      # Run configuration
    TRIAL) ECHOIT_COLOR=$'\e[1;36m';;  # Trial separator
    NEW) ECHOIT_COLOR=$'\e[1;32m';;    # A bug not in the known bug lists
    ALERT) ECHOIT_COLOR=$'\e[1;31m';;  # A framework problem, or a measurement far outside its band
  esac
  if [ ! -t 1 ]; then ECHOIT_COLOR=; ECHOIT_DIM=; ECHOIT_RESET=; fi  # Plain text whenever stdout is not a terminal
  if [ -n "${ECHOIT_EMPH}" ] && [ -n "${ECHOIT_COLOR}" ]; then  # Bold the lead-in words, keeping the colour of the line
    ECHOIT_MSG="${ECHOIT_MSG/${ECHOIT_EMPH}/$'\e[1m'${ECHOIT_EMPH}$'\e[22m'}"
  fi
  if [ "${ELIMINATE_KNOWN_BUGS}" == "1" ]; then
    echo "${ECHOIT_DIM}[$(date +'%T')] [$SAVED SAVED] [${ALREADY_KNOWN} DUPS]${ECHOIT_RESET} ${ECHOIT_COLOR}${ECHOIT_MSG}${ECHOIT_RESET}"
    if [ ${WORKDIRACTIVE} -eq 1 ]; then echo "[$(date +'%T')] [$SAVED SAVED] [${ALREADY_KNOWN} DUPS] $1" >> /${WORKDIR}/pquery-run.log; fi
  else
    echo "${ECHOIT_DIM}[$(date +'%T')] [$SAVED]${ECHOIT_RESET} ${ECHOIT_COLOR}${ECHOIT_MSG}${ECHOIT_RESET}"
    if [ ${WORKDIRACTIVE} -eq 1 ]; then echo "[$(date +'%T')] [$SAVED SAVED] $1" >> /${WORKDIR}/pquery-run.log; fi
  fi
}

duration(){  # $1=EPOCHREALTIME as it was when the work started. Gives the seconds since, with two decimals
  local DUR_US=$(( ${EPOCHREALTIME/[.,]/} - ${1/[.,]/} ))  # EPOCHREALTIME always holds six decimals, so this is microseconds
  printf '%d.%02d' $(( DUR_US / 1000000 )) $(( ( DUR_US % 1000000 ) / 10000 ))
}

duration_style(){  # $1=seconds as duration() gives them. The echoit style for a server start or shutdown wait
  # $2=the wait limit in seconds when it is not the standard 35, so a longer window scales the bands with it.
  # An rr traced shutdown gets 240 seconds instead of 35, which makes its bands 48, 137 and 205 seconds
  local DS_SEC="${1%%.*}" DS_ORANGE=7 DS_RED=20 DS_ALERT=30
  if [ -n "${2}" ] && [ "${2}" -ne 35 ]; then
    DS_ORANGE=$(( 7 * ${2} / 35 )); DS_RED=$(( 20 * ${2} / 35 )); DS_ALERT=$(( 30 * ${2} / 35 ))
  fi
  if [ ${DS_SEC} -ge ${DS_ALERT} ]; then echo ALERT; elif [ ${DS_SEC} -ge ${DS_RED} ]; then echo RED
  elif [ ${DS_SEC} -ge ${DS_ORANGE} ]; then echo ORANGE; else echo DIMGREEN; fi
}

# Read configuration
MDG=0;GRP_RPL=0;MDG_CLUSTER_RUN=0;MARIADB_BINLOG_RECOVERY_TESTING=0;  # Ensure these are preset (will be overwritten by source below if set in conf file)
if [ "$1" != "" ]; then CONFIGURATION_FILE=$1; fi
if [ ! -r ${SCRIPT_PWD}/${CONFIGURATION_FILE} ]; then
  echo "Assert: the confiruation file ${SCRIPT_PWD}/${CONFIGURATION_FILE} cannot be read!"
  exit 1
fi
source ${SCRIPT_PWD}/$CONFIGURATION_FILE
# Defaults for the SQL source options, so a configuration file that predates them still runs.
USE_GENERATOR=${USE_GENERATOR:-0}
USE_REVGEN=${USE_REVGEN:-0}
USE_INFILE=${USE_INFILE:-0}
QUERIES_PER_INFILE=${QUERIES_PER_INFILE:-0}  # 0 = the whole file, which is what configuration files that predate this option expect
USE_ALL_DISK_SQL=${USE_ALL_DISK_SQL:-0}
QUERIES_PER_ALL_DISK_RUN=${QUERIES_PER_ALL_DISK_RUN:-100000}
ALL_DISK_SQL_NEW_QUERIES_EVERY_X_TRIALS=${ALL_DISK_SQL_NEW_QUERIES_EVERY_X_TRIALS:-45}
ADV_FILTER_SQL=${ADV_FILTER_SQL:-0}  # Removes any SQL line matching ADV_FILTER_LIST from the assembled per-trial SQL
FILTER_SQL=${FILTER_SQL:-0}  # Removes any SQL line matching a line in filter.sql from the assembled per-trial SQL
TRIAL_SQL_DIR=${TRIAL_SQL_DIR:-"/dev/shm/trial_sql"}
INTERLEAVE=${INTERLEAVE:-0}
INTERLEAVE_SQL=${INTERLEAVE_SQL:-""}
INTERLEAVE_LINES=${INTERLEAVE_LINES:-100}
REVGEN_OPTIONS=${REVGEN_OPTIONS:-"--depth 10"}  # Measured best balance of parse-valid SQL against grammar reach; see pquery-run-MD-revgen.conf
REVGEN_YACC=${REVGEN_YACC:-${SCRIPT_PWD}/yacc/13.1_sql_yacc.yy}
REVGEN_VALIDATE_SOCKET=${REVGEN_VALIDATE_SOCKET:-}  # Optional: socket of a separate server revgen PREPARE-tests its output against, dropping unparseable statements. Ignored when unset or absent
QUERIES_PER_REVGEN_RUN=${QUERIES_PER_REVGEN_RUN:-25000}
QUERIES_PER_GENERATOR_RUN=${QUERIES_PER_GENERATOR_RUN:-25000}
GENERATION_THREADS=${GENERATION_THREADS:-0}  # Threads for the generator and revgen per trial; 0 = auto (CPU cores / 4)
if ! [[ "${GENERATION_THREADS}" =~ ^[0-9]+$ ]] || [ "${GENERATION_THREADS}" -eq 0 ]; then GENERATION_THREADS=$(( $(nproc) / 4 )); fi
[ "${GENERATION_THREADS}" -lt 1 ] && GENERATION_THREADS=1
# Upper bounds for the random-option counts. Defaulted because an unset bound would make the
# count come out as 0, which silently adds no options at all instead of failing.
MAX_NR_OF_RND_OPTS_TO_ADD=${MAX_NR_OF_RND_OPTS_TO_ADD:-4}
MDG_MAX_NR_OF_RND_OPTS_TO_ADD=${MDG_MAX_NR_OF_RND_OPTS_TO_ADD:-4}
MDG_WSREP_MAX_NR_OF_RND_OPTS_TO_ADD=${MDG_WSREP_MAX_NR_OF_RND_OPTS_TO_ADD:-4}
MDG_WSREP_PROVIDER_MAX_NR_OF_RND_OPTS_TO_ADD=${MDG_WSREP_PROVIDER_MAX_NR_OF_RND_OPTS_TO_ADD:-4}
# PQUERY_MAX_SQL_LINES caps the assembled per-trial SQL input file. The default is pquery's own line maximum.
PQUERY_MAX_SQL_LINES=${PQUERY_MAX_SQL_LINES:-5141189}
echo ${WORKDIR} > /tmp/gomd_helper # gomd helper
PQUERY_TOOL_NAME=$(basename ${PQUERY_BIN})
if [ "${SEED}" == "" ]; then SEED=$(${RANDOM_BIN} 1 2147483647); fi
# TODO: research this new code (and how it affects trials, though it seeems backwards compatible; checking for PQUERY3 varialbe happens AFTER all other checks are done (i.e. first core, then other checks, then PQUERY3 check, so should be fine? Though trial-1 is apparently removed; research further))
if [[ ${PQUERY_TOOL_NAME} == "pquery3"* ]]; then PQUERY3=1; fi

# MSAN: symbolized stack traces in handle_fatal_signal are very slow on the multi-GB MSAN binary; the server may be stopped/killed before the handler reaches the core dump, leaving assert trials without a core (and thus without a frames-based UniqueID). Skip the in-log trace so the core is written promptly; UniqueID frames come from gdb on the core
if [[ "${BASEDIR}" == *"MSAN"* || "${BASEDIR}" == *"msan"* || "${BASEDIR}" == *"Msan"* ]]; then
  MYSAFE="${MYSAFE} --skip-stack-trace"
fi

# TSAN/VAL: the 13.0+ innodb_buffer_pool_size_max default (8 TiB address-space reservation) cannot map within the TSAN-restricted address space, and stalls Valgrind's memcheck address-range tracking; cap it (VALGRIND_RUN=1 covers Valgrind runs on plain, non-VAL_ named builds)
if [[ "${BASEDIR}" == *"TSAN"* || "${BASEDIR}" == *"tsan"* || "${BASEDIR}" == *"Tsan"* || "${BASEDIR}" == *"VAL_"* ]] || [ "${VALGRIND_RUN}" == "1" ]; then
  MYSAFE="${MYSAFE} --loose-innodb-buffer-pool-size-max=2G"
  MYINIT="${MYINIT} --loose-innodb-buffer-pool-size-max=2G"
fi

# VAL: Valgrind-instrumented (VAL_) builds are meant to run under Valgrind (VALGRIND_RUN=1 + VALGRIND_CMD in the config); without it mariadbd runs plain and no Valgrind errors can be detected
if [[ "${BASEDIR}" == *"VAL_"* ]] && [ "${VALGRIND_RUN}" != "1" ]; then
  echoit "Warning: BASEDIR (${BASEDIR}) is a Valgrind (VAL_) build, but VALGRIND_RUN is not set to 1 in the config; mariadbd will run without Valgrind"
fi

# Valgrind does not support io_uring: InnoDB hangs right after the 'Using io_uring' startup line when running under Valgrind; disable native AIO
if [ "${VALGRIND_RUN}" == "1" ]; then
  MYSAFE="${MYSAFE} --loose-innodb-use-native-aio=0"
  MYINIT="${MYINIT} --loose-innodb-use-native-aio=0"
fi

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
  #if [ ${THREADS} -ne 1 ]; then
  #  echo "Assert: PRELOAD is enabled (1), and THREADS!=1 (${THREADS}). This setup is not supported (yet) as this script would not be able to prepend the preload SQL to any particular thread's SQL trace (which one to pick?). It may be possible to do a rather large framework patch where PRELOAD SQL is built into reducer.sh etc. (for single threaded runs, it is simply prepended to the SQL trace), so that it is preloaded in all tools, especially reduction. Feel free to implement this if you like."
  #  exit 1
  if [ "${QUERY_CORRECTNESS_TESTING}" == "1" ]; then
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
  fi
fi
if [ "${RR_TRACING}" == "1" ]; then
  if [ ! -r /usr/bin/rr ]; then
    echo "Assert: /usr/bin/rr not found"  # TODO: set to be automatic using whereis
    exit 1
  fi
fi
if [[ ${FILTER_SQL} -eq 1 ]]; then
  if [ ! -r ${SCRIPT_PWD}/filter.sql ]; then
    echo "Assert: FILTER_SQL is enabled, yet filter.sql (${SCRIPT_PWD}/filter.sql) cannot be found"
    exit 1
  fi
fi
TRIAL_SQL_DIR="$(echo "${TRIAL_SQL_DIR}" | tr -d '\n')"
if [ -z "${TRIAL_SQL_DIR}" ]; then
  echoit "Assert: TRIAL_SQL_DIR is empty. It holds the assembled per-trial SQL, so every run needs it"
  exit 1
fi
mkdir -p "${TRIAL_SQL_DIR}"
if [ ! -d "${TRIAL_SQL_DIR}" ]; then
  echoit "Assert: TRIAL_SQL_DIR ('${TRIAL_SQL_DIR}') is not an actual directory or could not be created. Double check correctness of directory and that this script can write to the location provided (mkdir -p was attempted, any failure of the same would show above this message)"
  exit 1
fi

# Nr of MDG nodes 1-n
if [ -z "${NR_OF_NODES}" ] ; then
  NR_OF_NODES=3
fi

# Try and raise ulimit for user processes (see setup_server.sh for how to set correct soft/hard nproc settings in limits.conf)
#ulimit -u 7000

# The SQL input is a set of sources: USE_GENERATOR, USE_REVGEN, USE_INFILE and USE_ALL_DISK_SQL. Each one
# contributes lines to one file per trial, the share of each source is simply its line count, and that file
# is shuffled once it is assembled.
for RETIRED_VAR in PRE_SHUFFLE_SQL PRE_SHUFFLE_MIN_SQL_LINES PRE_SHUFFLE_TWO_MIN_SQL_LINES PRE_SHUFFLE_TRIALS_PER_SHUFFLE PRE_SHUFFLE_DIR PRE_SHUFFLE_INTERLEAVE GENERATE_NEW_QUERIES_EVERY_X_TRIALS REVGEN_NEW_QUERIES_EVERY_X_TRIALS; do
  if [ ! -z "${!RETIRED_VAR}" ]; then
    echoit "Assert: the configuration file sets ${RETIRED_VAR}, which no longer exists. The SQL input is now a set of sources: USE_GENERATOR and USE_REVGEN run every trial, USE_INFILE randomly selects QUERIES_PER_INFILE lines from the input file, and USE_ALL_DISK_SQL collects QUERIES_PER_ALL_DISK_RUN lines from all SQL on disk every ALL_DISK_SQL_NEW_QUERIES_EVERY_X_TRIALS trials. The per-trial SQL lands in TRIAL_SQL_DIR, capped at PQUERY_MAX_SQL_LINES lines, and is always shuffled. ADV_FILTER_SQL=1 applies the ADV_FILTER_LIST removals, and the interleave settings are now INTERLEAVE, INTERLEAVE_SQL and INTERLEAVE_LINES"
    exit 1
  fi
done
RETIRED_VAR=
# Each of these must be 0 or 1: any other value makes the numeric tests further down fail silently,
# which would leave a source switched off without saying so
for SQL_TOGGLE in USE_GENERATOR USE_REVGEN USE_INFILE USE_ALL_DISK_SQL ADV_FILTER_SQL FILTER_SQL; do
  if ! [[ "${!SQL_TOGGLE}" =~ ^[01]$ ]]; then
    echoit "Assert: ${SQL_TOGGLE} must be 0 or 1 (current value: '${!SQL_TOGGLE}')"
    exit 1
  fi
done
SQL_TOGGLE=
if [ "${USE_GENERATOR}" -ne 1 ] && [ "${USE_REVGEN}" -ne 1 ] && [ "${USE_INFILE}" -ne 1 ] && [ "${USE_ALL_DISK_SQL}" -ne 1 ]; then
  echoit "Assert: no SQL source is active. Turn on at least one of USE_GENERATOR, USE_REVGEN, USE_INFILE or USE_ALL_DISK_SQL"
  exit 1
fi
if ! [[ "${PQUERY_MAX_SQL_LINES}" =~ ^[0-9]{1,10}$ ]] || [ "${PQUERY_MAX_SQL_LINES}" -lt 1 ]; then
  echoit "Assert: PQUERY_MAX_SQL_LINES must be a positive integer of at most 10 digits (current value: '${PQUERY_MAX_SQL_LINES}')"
  exit 1
fi
if ! [[ "${QUERIES_PER_ALL_DISK_RUN}" =~ ^[0-9]{1,10}$ ]] || [ "${QUERIES_PER_ALL_DISK_RUN}" -lt 1 ]; then
  echoit "Assert: QUERIES_PER_ALL_DISK_RUN must be a positive integer of at most 10 digits (current value: '${QUERIES_PER_ALL_DISK_RUN}')"
  exit 1
fi
if ! [[ "${QUERIES_PER_INFILE}" =~ ^[0-9]{1,10}$ ]]; then
  echoit "Assert: QUERIES_PER_INFILE must be an integer of at most 10 digits, 0 or higher, where 0 means the whole input file (current value: '${QUERIES_PER_INFILE}')"
  exit 1
fi
if ! [[ "${ALL_DISK_SQL_NEW_QUERIES_EVERY_X_TRIALS}" =~ ^[0-9]{1,10}$ ]] || [ "${ALL_DISK_SQL_NEW_QUERIES_EVERY_X_TRIALS}" -lt 1 ]; then
  echoit "Assert: ALL_DISK_SQL_NEW_QUERIES_EVERY_X_TRIALS must be a positive integer of at most 10 digits (current value: '${ALL_DISK_SQL_NEW_QUERIES_EVERY_X_TRIALS}')"
  exit 1
fi
if [ ! -z "${INTERLEAVE_LINES}" ] && { ! [[ "${INTERLEAVE_LINES}" =~ ^[0-9]{1,10}$ ]] || [ "${INTERLEAVE_LINES}" -lt 1 ]; }; then
  echoit "Assert: INTERLEAVE_LINES must be a positive integer of at most 10 digits (current value: '${INTERLEAVE_LINES}')"
  exit 1
fi

# When revgen is in use, its yacc grammar (REVGEN_YACC) must exist before we start: revgen walks it to
# derive SQL, and without it every per-trial revgen invocation would fail. Fail fast here instead.
if [ "${USE_REVGEN}" -eq 1 ]; then
  if [ ! -r "${REVGEN_YACC}" ]; then
    echoit "Assert: USE_REVGEN=1 but the yacc grammar REVGEN_YACC='${REVGEN_YACC}' is not readable. Point REVGEN_YACC at a valid sql_yacc.yy (the shipped grammar is ${SCRIPT_PWD}/yacc/13.1_sql_yacc.yy) or disable USE_REVGEN. Terminating."
    exit 1
  fi
  echoit "revgen grammar (REVGEN_YACC): ${REVGEN_YACC}"
fi

# Input file (INFILE) tarball preflight, for USE_INFILE=1: extract it here if it is a .tar.* archive
# (the tar may also need extracting on a fresh clone or for multi-threaded runs).
if [ "${USE_INFILE}" -eq 1 ]; then
  if [ ! -r ${INFILE} ]; then
    echo "Assert! \$INFILE (${INFILE}) cannot be read? Check file existence and privileges!"
    exit 1
  elif [[ "${INFILE}" == *".tar."* ]]; then
    echoit "The input file is a compressed tarball. This script will untar the file in the same location as the tarball. Please note this overwrites any existing files with the same names as those in the tarball, if any. If the sql input file needs patching (and is part of the github repo), please remember to update the tarball with the new file."
    STORECURPWD=${PWD}
    cd $(echo ${INFILE} | sed 's|/[^/]\+\.tar\..*|/|') || exit 1 # Change to the directory containing the input file
    tar -xf ${INFILE}
    cd ${STORECURPWD} || exit 1
    ORIGINAL_INFILE="${INFILE}"
    INFILE=$(echo ${INFILE} | sed 's|\.tar\..*||')
    if [ ! -r ${INFILE} ]; then
      echo "Assert! \$INFILE (${INFILE}) cannot be read after decompression (original input file: '${ORIGINAL_INFILE}?'"
      exit 1
    fi
    ORIGINAL_INFILE=
  fi
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
  NEWPORT=$(${RANDOM_BIN} 13001 65001)
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
        sleep 0.0$(${RANDOM_BIN} 10000 99999)  # Random microsleep of 10 to 100 ms to further avoid races
        continue  # Loop the check
      fi
    else
      NEWPORT=$(${RANDOM_BIN} 13001 65001)  # Try a new port
      DOUBLE_CHECK=0  # Reset the double check
      continue  # Recheck the new port
    fi
  done
}

# Diskspace OOS check function - ensures at least ${2:-200}MB is free on ${1:-${RUNDIR}}
# Usage: diskspace                 # Checks RUNDIR for >=200MB free
#        diskspace /some/dir       # Checks /some/dir for >=200MB free
#        diskspace /some/dir 500   # Checks /some/dir for >=500MB free
# Waits 10 minutes and re-checks in a loop until the minimum is available.
diskspace(){
  local CHECK_PATH="${1:-${RUNDIR}}"
  local MIN_MB="${2:-200}"
  local MIN_KB=$((MIN_MB * 1024))
  local FREE_KB TEST_PATH
  while :; do
    if [ -z "${CHECK_PATH}" ]; then break; fi  # Path not defined yet, assume disk space is available and test on next call of diskspace()
    if [ ! -d "${CHECK_PATH}" ]; then mkdir -p "${CHECK_PATH}" 2>/dev/null; fi
    # If the target path still does not exist (e.g. permission denied), probe the nearest existing parent instead
    TEST_PATH="${CHECK_PATH}"
    while [ -n "${TEST_PATH}" ] && [ "${TEST_PATH}" != "/" ] && [ ! -d "${TEST_PATH}" ]; do
      TEST_PATH="$(dirname "${TEST_PATH}")"
    done
    if [ -z "${TEST_PATH}" ] || [ ! -d "${TEST_PATH}" ]; then break; fi  # Cannot probe; assume ok to avoid stalling
    FREE_KB="$(df -k -P "${TEST_PATH}" 2>/dev/null | awk 'NR==2{print $4}')"
    if [ -z "${FREE_KB}" ] || ! [[ "${FREE_KB}" =~ ^[0-9]+$ ]]; then break; fi  # df failed or unparseable; assume ok to avoid stalling
    if [ "${FREE_KB}" -ge "${MIN_KB}" ]; then break; fi  # At least ${MIN_MB}MB free; all good
    echoit "Likely out of diskspace on ${CHECK_PATH} (only $((FREE_KB/1024))MB free, need at least ${MIN_MB}MB)... Pausing 10 minutes"
    sleep 600
    echoit "Slept 10 minutes, re-checking diskspace on ${CHECK_PATH}..."
  done
}

add_handy_scripts(){  # Add handy stack and gdb scripts per trial
  if [[ "${MDG}" -eq 1 ]]; then
    SAVE_HANDY_LOC="${RUNDIR}/${TRIAL}/node${j}"
    CORE_TO_ANALYZE="${GALERA_CORE_LOC}"
  else
    SAVE_HANDY_LOC="${RUNDIR}/${TRIAL}"
    CORE_TO_ANALYZE="./data*/*core*"
  fi
  ln -s "${SCRIPT_PWD}/stack.sh" ${SAVE_HANDY_LOC}/stack 2>/dev/null
  echo "echo 'Handy copy and paste script:'" > ${SAVE_HANDY_LOC}/gdb
  echo "echo '  set pagination off'" >> ${SAVE_HANDY_LOC}/gdb
  echo "echo '  set print pretty on'" >> ${SAVE_HANDY_LOC}/gdb
  echo "echo '  set print frame-arguments all'" >> ${SAVE_HANDY_LOC}/gdb
  echo "echo '  thread apply all backtrace full'" >> ${SAVE_HANDY_LOC}/gdb
  echo "echo 'OR simple one-thread backtrace instead of all threads (i.e. instead of last line):'" >> ${SAVE_HANDY_LOC}/gdb
  echo "echo '  bt'" >> ${SAVE_HANDY_LOC}/gdb
  echo "sleep 5" >> ${SAVE_HANDY_LOC}/gdb
  echo 'if [ -r ../mysqld/mariadbd ]; then' >> ${SAVE_HANDY_LOC}/gdb
  echo "  gdb -iex 'set debuginfod enabled off' ../mysqld/mariadbd ${CORE_TO_ANALYZE}" >> ${SAVE_HANDY_LOC}/gdb
  echo 'elif [ -r ../mysqld/mysqld ]; then' >> ${SAVE_HANDY_LOC}/gdb
  echo "  gdb -iex 'set debuginfod enabled off' ../mysqld/mysqld ${CORE_TO_ANALYZE}" >> ${SAVE_HANDY_LOC}/gdb
  echo 'elif [ -r ../../mysqld/mariadbd ]; then' >> ${SAVE_HANDY_LOC}/gdb
  echo "  gdb -iex 'set debuginfod enabled off' ../../mysqld/mariadbd ${CORE_TO_ANALYZE}" >> ${SAVE_HANDY_LOC}/gdb
  echo 'elif [ -r ../../mysqld/mysqld ]; then' >> ${SAVE_HANDY_LOC}/gdb
  echo "  gdb -iex 'set debuginfod enabled off' ../../mysqld/mysqld ${CORE_TO_ANALYZE}" >> ${SAVE_HANDY_LOC}/gdb
  echo 'else' >> ${SAVE_HANDY_LOC}/gdb
  echo '  echo "Assert: neither mariadbd nor mysqld were found in any usual locations (PWD: ${PWD})"' >> ${SAVE_HANDY_LOC}/gdb
  echo '  exit 1'  >> ${SAVE_HANDY_LOC}/gdb
  echo 'fi' >> ${SAVE_HANDY_LOC}/gdb
  chmod +x ${SAVE_HANDY_LOC}/gdb
  CORE_TO_ANALYZE=
  SAVE_HANDY_LOC=
}

# Find mysqld binary
if [ -r ${BASEDIR}/bin/mariadbd ]; then
  BIN=${BASEDIR}/bin/mariadbd
elif [ -r ${BASEDIR}/bin/mysqld ]; then
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
    echo "Assert: there is no (script readable) mysqld/mariadbd binary at ${BASEDIR}/bin ?"
    exit 1
  fi
fi

#Store mysqld/mariadbd version string
MYSQL_VERSION=$(${BIN} --version 2>&1 | grep -oe '[0-9]*\.[0-9][\.0-9]*' | head -n1)

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
      echoit "*** IMPORTANT WARNING ***: SKIP_JEMALLOC_FOR_PS was set to 1, and thus JEMALLOC will not be LD_PRELOAD'ed. However, the mysqld/mariadbd binary (${BIN}) reports itself as Percona Server. If you are going to test TokuDB, JEMALLOC should be LD_PRELOAD'ed. If not testing TokuDB, then this warning can be safely ignored."
    fi
  fi
fi

# Wait until the filesystem holding $1 has $2 KB free, then return. Reports on entry and every 5
# minutes after, so a long wait stays visible without filling the log.
wait_for_diskspace(){  # $1=target file or directory, $2=KB required
  local DS_DIR="${1}" DS_NEED="${2}" DS_WAITED=0 DS_FREE
  [ ! -d "${DS_DIR}" ] && DS_DIR="$(dirname ${DS_DIR})"
  DS_FREE="$(df -Pk ${DS_DIR} 2>/dev/null | tail -n1 | awk '{print $4}')"
  [ -z "${DS_FREE}" ] && return 0  # Cannot read the filesystem: leave the write to report its own failure
  while [ "${DS_FREE}" -lt "${DS_NEED}" ]; do
    if [ $(( DS_WAITED % 300 )) -eq 0 ]; then
      echoit "Waiting for disk space on ${DS_DIR}: ${DS_FREE} KB free, ${DS_NEED} KB needed. Free up space to continue (waited ${DS_WAITED}s so far)"
    fi
    sleep 10
    DS_WAITED=$(( DS_WAITED + 10 ))
    DS_FREE="$(df -Pk ${DS_DIR} 2>/dev/null | tail -n1 | awk '{print $4}')"
  done
  [ "${DS_WAITED}" -gt 0 ] && echoit "Disk space on ${DS_DIR} is sufficient again (${DS_FREE} KB free after waiting ${DS_WAITED}s), continuing"
  return 0
}

# Cap a SQL input file to PQUERY_MAX_SQL_LINES lines, pquery's own maximum. Lines are cut from the end of
# the file. While the sources still stand one after another, as generator, revgen, INFILE, all-disk, that
# means the all-disk SQL loses lines first, then the INFILE, then revgen, then the generator SQL, and any
# source past the cut is dropped whole. Once the file is shuffled the cut takes random lines instead.
cap_sql_lines(){  # $1=file to cap in place, $2=description for the log message
  local CAP_LINES="$(wc -l < ${1})"
  if [ "${CAP_LINES}" -gt "${PQUERY_MAX_SQL_LINES}" ]; then
    truncate -s "$(head -n ${PQUERY_MAX_SQL_LINES} ${1} | wc -c)" ${1}  # Truncated in place: a copy would briefly need double the space, and these files often sit in tmpfs
    echoit "Capped ${2} from ${CAP_LINES} to PQUERY_MAX_SQL_LINES=${PQUERY_MAX_SQL_LINES} lines"
  fi
}

# The lighter filter, filter.sql, holds regular expressions with .* in them, so one pass over a large mix of
# SQL costs tens of seconds on a single core. The file is split on line boundaries, the parts are filtered at
# the same time, and the parts are joined again in order, which brings a 150,000 line mix from about 40
# seconds to about 3. The greps run in the locale of the box, so the SQL is matched as text, not as bytes.
filter_sql_file(){  # $1=file, filtered in place. Sets FILTERED_LINES, and returns 1 when a part failed
  local FSF="${1}" FSF_JOBS FSF_PART FSF_PID FSF_RC FSF_FAIL=0 FSF_PIDS=()
  FILTERED_LINES="$(wc -l < ${FSF})"
  FSF_JOBS=$(nproc); [ "${FSF_JOBS}" -gt 24 ] && FSF_JOBS=24  # A part per core, up to 24. More parts still help a little, but a busy box needs its cores for the trials and the reducers
  rm -f ${FSF}.p_* ${FSF}.f_*
  if ! split -n l/${FSF_JOBS} -d "${FSF}" "${FSF}.p_"; then
    rm -f ${FSF}.p_*
    return 1
  fi
  for FSF_PART in ${FSF}.p_*; do
    grep --binary-files=text -hvif ${SCRIPT_PWD}/filter.sql "${FSF_PART}" > "${FSF}.f_${FSF_PART##*.p_}" &
    FSF_PIDS+=($!)
  done
  for FSF_PID in ${FSF_PIDS[@]}; do
    wait ${FSF_PID}; FSF_RC=$?
    [ ${FSF_RC} -gt 1 ] && FSF_FAIL=1  # 1 is a part with every line removed, which is a normal outcome
  done
  if [ ${FSF_FAIL} -eq 1 ]; then
    rm -f ${FSF}.p_* ${FSF}.f_*
    return 1
  fi
  cat ${FSF}.f_* > "${FSF}"
  rm -f ${FSF}.p_* ${FSF}.f_*
  FILTERED_LINES=$(( FILTERED_LINES - $(wc -l < ${FSF}) ))
  return 0
}

assemble_abort(){  # $1=message. Stops the run on an assert from the SQL assembly, leaving no SQL of this run behind
  echoit "Assert: ${1}"
  rm -f ${TRIAL_SQL_DIR}/${RANDOMD}_*
  exit 1
}

all_disk_sql_index(){  # Builds ALL_DISK_SQL_INDEX: every *.sql file on disk, one path per line, tagged with the set it belongs to
  # Two sets, tagged P and A, are indexed. Each collection uses one of them, so the two searches keep
  # giving the SQL mix they always did, at the cost of one walk per run instead of one per collection.
  local IDX_START="${EPOCHREALTIME}"
  echoit "USE_ALL_DISK_SQL=1: indexing all SQL files on the disk, into ${ALL_DISK_SQL_INDEX}. This is done once per run"
  { find ${HOME} /*/SQL /*/TESTCASES -maxdepth 3 -name '*.sql' -type f 2>/dev/null | grep --binary-files=text -hvi 'newbugs_dups' | sed 's|^|P\t|'
    find / -maxdepth 5 -name '*.sql' -type f 2>/dev/null | grep --binary-files=text -hviE '/test/TESTCASES|newbugs_dups' | sed 's|^|A\t|'
  } > ${ALL_DISK_SQL_INDEX}
  if [ ! -s "${ALL_DISK_SQL_INDEX}" ]; then
    assemble_abort "USE_ALL_DISK_SQL=1, yet no SQL file was found on the disk. The index (${ALL_DISK_SQL_INDEX}) is empty"
  fi
  echoit "USE_ALL_DISK_SQL=1: indexing took $(duration ${IDX_START})s. The index holds $(grep -c '^P' ${ALL_DISK_SQL_INDEX}) paths in the home/SQL/TESTCASES set and $(grep -c '^A' ${ALL_DISK_SQL_INDEX}) in the whole-disk set"
}

all_disk_sql_collect(){  # $1=output file, $2=lines to collect. Randomly samples SQL from the files in ALL_DISK_SQL_INDEX
  local OUTF="${1}"
  local WANT="${2}"
  local COLLECTED=0 SET_TAG FILE_LINES TAKE ADDED ADS_FILE
  if [ ! -s "${ALL_DISK_SQL_INDEX}" ]; then  # Without this the grep below would read stdin and the run would hang
    assemble_abort "the SQL file index (${ALL_DISK_SQL_INDEX}) is missing or empty. It is written once per run by all_disk_sql_index()"
  fi
  if [ $(${RANDOM_BIN} 1 20) -le 10 ]; then SET_TAG=P; else SET_TAG=A; fi  # Either set, 50/50
  if [ "$(grep -c "^${SET_TAG}	" ${ALL_DISK_SQL_INDEX})" -eq 0 ]; then  # A box may hold no SQL in one of the two sets
    [ "${SET_TAG}" == "P" ] && SET_TAG=A || SET_TAG=P
  fi
  > ${OUTF}
  while read -r ADS_FILE; do
    [ "${COLLECTED}" -ge "${WANT}" ] && break
    [ -r "${ADS_FILE}" ] || continue
    FILE_LINES="$(wc -l < "${ADS_FILE}" 2>/dev/null)"
    [ -z "${FILE_LINES}" ] && continue
    [ "${FILE_LINES}" -lt 1 ] && continue
    TAKE=$(( $(${RANDOM_BIN} ${FILE_LINES}) + 1 ))  # Random part of the file: 1 line up to all of them, each equally likely
    [ "${TAKE}" -gt "$(( WANT - COLLECTED ))" ] && TAKE=$(( WANT - COLLECTED ))  # Never ask for more than the collection still needs: on a multi-GB file, sampling millions of lines to keep tens of thousands costs minutes and gigabytes of memory
    ADDED="$(shuf --random-source=<(${RANDOM_BIN} --raw) -n ${TAKE} "${ADS_FILE}" | grep --binary-files=text -hivE "${ADV_FILTER_LIST}" | tee -a ${OUTF} | wc -l)"
    COLLECTED=$(( COLLECTED + ADDED ))
  done < <(grep "^${SET_TAG}	" ${ALL_DISK_SQL_INDEX} | cut -f2- | shuf --random-source=<(${RANDOM_BIN} --raw))
  ALL_DISK_SQL_LINES=${COLLECTED}  # The per-file cap keeps this at the budget or under it, so the pool needs no trim
}

# The clean-up applied to every source: drop the file name prefixes and the outcome markers that SQL
# harvested from an earlier run carries
TRIAL_SQL_CLEANUP_SED='s|/data/[^:]\+\.sql:||g;s|/test/[^:]\+\.sql:||g;s|;#NOERROR$|;|;s|;#NOERROR[#:].*$|;|;s|;#ERROR: .*$|;|;s|\r#NOERROR.*$|;|;'

emit_file(){  # One source file on stdout, always ending in a newline
  cat "${1}"
  # A file whose last line has no newline would run into the first line of the next source, making one
  # statement out of two. tail -c 1 gives that last byte, and $() drops it when it is a newline
  [ -n "$(tail -c 1 "${1}")" ] && echo
  return 0
}

emit_trial_sources(){  # Every active source's SQL on stdout, in the order the line cap cuts back from the end
  [ ${USE_GENERATOR} -eq 1 ] && emit_file "${GEN_OUTFILE}"
  [ ${USE_REVGEN} -eq 1 ] && emit_file "${REVGEN_OUTFILE}"
  if [ ${USE_INFILE} -eq 1 ]; then
    if [ "${QUERIES_PER_INFILE}" -gt 0 ]; then
      # Up to QUERIES_PER_INFILE lines, randomly selected from the whole file (xoshiro256++ entropy),
      # another set each trial. shuf ends every line it writes with a newline, so no end-of-file repair
      # is needed here
      shuf --random-source=<(${RANDOM_BIN} --raw) -n ${QUERIES_PER_INFILE} "${INFILE}"
    elif [ "${INFILE_LINES}" -le "${PQUERY_MAX_SQL_LINES}" ]; then
      emit_file "${INFILE}"
    else  # QUERIES_PER_INFILE=0 and larger than the cap: read a window at a random offset, so each trial sees other SQL
      tail -c +$(( $(${RANDOM_BIN} ${INFILE_WINDOW_MAX_OFFSET}) + 1 )) "${INFILE}" | tail -n +2  # tail -n +2 drops the part line the offset lands in
      [ -n "$(tail -c 1 "${INFILE}")" ] && echo  # The window can end at the end of the file, so the same applies
    fi
  fi
  [ ${USE_ALL_DISK_SQL} -eq 1 ] && emit_file "${ALL_DISK_SQL_POOL}"
  return 0
}

assemble_trial_sql(){  # Builds TRIAL_SQL: the one SQL file this trial gives to pquery
  local ASM_START="${EPOCHREALTIME}"
  local ASM_PREV="${TRIAL_SQL}" ASM_KB=0 ASM_LINES ADS_START ASM_DIR_WAITED=0
  while [ ! -d "${TRIAL_SQL_DIR}" ]; do  # tmpfs_clean.sh, or an operator, can remove it mid-run
    mkdir -p "${TRIAL_SQL_DIR}"
    [ -d "${TRIAL_SQL_DIR}" ] && break
    if [ $(( ASM_DIR_WAITED % 300 )) -eq 0 ]; then  # On entry, then every 5 minutes, so a long wait does not fill the log
      echoit "Warning: TRIAL_SQL_DIR (${TRIAL_SQL_DIR}) is missing and could not be recreated. Retrying every 5 seconds (waited ${ASM_DIR_WAITED}s so far)"
    fi
    sleep 5
    ASM_DIR_WAITED=$(( ASM_DIR_WAITED + 5 ))
  done
  TRIAL_SQL="${TRIAL_SQL_DIR}/${RANDOMD}_${TRIAL}.sql"
  # The previous trial is finished with its file, so free that space before writing the new one
  if [ ! -z "${ASM_PREV}" ] && [ "${ASM_PREV}" != "${TRIAL_SQL}" ]; then rm -f "${ASM_PREV}"; fi
  if [ ${USE_ALL_DISK_SQL} -eq 1 ]; then  # The one expensive source, so it keeps a cadence of its own
    if [ ${TRIAL} -eq 1 ] || [ $(( TRIAL % ALL_DISK_SQL_NEW_QUERIES_EVERY_X_TRIALS )) -eq 0 ] || [ ! -s "${ALL_DISK_SQL_POOL}" ]; then
      ADS_START="${EPOCHREALTIME}"
      echoit "Collecting SQL from all SQL available on any local disk..."
      all_disk_sql_collect "${ALL_DISK_SQL_POOL}" "${QUERIES_PER_ALL_DISK_RUN}"
      if [ "${ALL_DISK_SQL_LINES}" -eq 0 ]; then
        assemble_abort "collecting SQL from the disk index gave 0 lines. Check ${ALL_DISK_SQL_INDEX} and whether the files it lists can be read"
      fi
      echoit "Collected ${ALL_DISK_SQL_LINES} lines (${ALL_DISK_SQL_POOL}) in $(duration ${ADS_START})s"
      ALL_DISK_SQL_POOL_TRIAL=1  # How many trials this pool has served, so the re-use line can show where the cadence stands
    else
      ALL_DISK_SQL_POOL_TRIAL=$(( ALL_DISK_SQL_POOL_TRIAL + 1 ))
      echoit "Reusing all-disk SQL pool ${ALL_DISK_SQL_POOL} (${ALL_DISK_SQL_LINES} lines). Trial ${ALL_DISK_SQL_POOL_TRIAL}/${ALL_DISK_SQL_NEW_QUERIES_EVERY_X_TRIALS}."
    fi
  fi
  [ ${USE_GENERATOR} -eq 1 ] && ASM_KB=$(( ASM_KB + $(stat -c %s ${GEN_OUTFILE}) / 1024 ))
  [ ${USE_REVGEN} -eq 1 ] && ASM_KB=$(( ASM_KB + $(stat -c %s ${REVGEN_OUTFILE}) / 1024 ))
  [ ${USE_INFILE} -eq 1 ] && ASM_KB=$(( ASM_KB + INFILE_ASM_KB ))
  [ ${USE_ALL_DISK_SQL} -eq 1 ] && ASM_KB=$(( ASM_KB + $(stat -c %s ${ALL_DISK_SQL_POOL}) / 1024 ))
  wait_for_diskspace "${TRIAL_SQL_DIR}" "$(( ASM_KB + 1 ))"  # An upper bound: the line cap often makes the write smaller
  # Cut at the cap while writing, not afterwards: with a large input file, writing the whole
  # concatenation first would write gigabytes to then throw most of them away
  if [ ${ADV_FILTER_SQL} -eq 1 ]; then
    emit_trial_sources | sed "${TRIAL_SQL_CLEANUP_SED}" | grep --binary-files=text -hivE "${ADV_FILTER_LIST}" | head -n ${PQUERY_MAX_SQL_LINES} > "${TRIAL_SQL}"
  else
    emit_trial_sources | sed "${TRIAL_SQL_CLEANUP_SED}" | head -n ${PQUERY_MAX_SQL_LINES} > "${TRIAL_SQL}"
  fi
  ASM_LINES="$(wc -l < ${TRIAL_SQL})"
  if [ "${ASM_LINES}" -ge "${PQUERY_MAX_SQL_LINES}" ]; then
    echoit "The assembled SQL was cut at PQUERY_MAX_SQL_LINES=${PQUERY_MAX_SQL_LINES} lines. The cut takes from the end, so the last source in use loses lines first"
  fi
  if [ ${FILTER_SQL} -eq 1 ]; then  # One pass over the whole mix, so the sources are filtered together and not each on its own
    FILTER_DUR_START="${EPOCHREALTIME}"
    wait_for_diskspace "${TRIAL_SQL_DIR}" "$(( $(stat -c %s ${TRIAL_SQL}) / 1024 * 2 + 1 ))"  # The parts the filter splits the file into need room beside the file
    if ! filter_sql_file "${TRIAL_SQL}"; then
      assemble_abort "applying the filter ${SCRIPT_PWD}/filter.sql to ${TRIAL_SQL} failed. Check that the filter file can still be read, and the free space in ${TRIAL_SQL_DIR}"
    fi
    ASM_LINES="$(wc -l < ${TRIAL_SQL})"
    # The share of the assembled SQL the filter removes. A high share means much of it never runs
    FILTER_TOTAL=$(( ASM_LINES + FILTERED_LINES ))
    FILTER_SHARE=0  # In hundredths of a percent, so the line can carry two decimals
    if [ ${FILTER_TOTAL} -gt 0 ]; then FILTER_SHARE=$(( FILTERED_LINES * 10000 / FILTER_TOTAL )); fi
    if [ $(( FILTER_SHARE / 100 )) -ge 25 ]; then FILTER_STYLE=RED
    elif [ $(( FILTER_SHARE / 100 )) -ge 15 ]; then FILTER_STYLE=ORANGE
    else FILTER_STYLE=DIMGREEN; fi
    echoit "Applied filter ${SCRIPT_PWD}/filter.sql: ${FILTERED_LINES}/${FILTER_TOTAL} lines filtered ($(( FILTER_SHARE / 100 )).$(printf '%02d' $(( FILTER_SHARE % 100 )))%) in $(duration ${FILTER_DUR_START})s" "${FILTER_STYLE}"
    FILTER_DUR_START=; FILTER_TOTAL=; FILTER_SHARE=; FILTER_STYLE=
  fi
  if [ "${ASM_LINES}" -eq 0 ]; then
    assemble_abort "the SQL assembled for this trial (${TRIAL_SQL}) holds 0 lines. Check the sources in use, and any filter in use"
  fi
  # Shuffle the mix, so the SQL of each source is spread over the file instead of the sources standing one
  # after another. shuf reads all of its input before it writes, so the output file can be the input file
  if ! shuf --random-source=<(${RANDOM_BIN} --raw) -o "${TRIAL_SQL}" "${TRIAL_SQL}"; then
    assemble_abort "shuffling the assembled SQL (${TRIAL_SQL}) failed. Check the free memory and the free space in ${TRIAL_SQL_DIR}"
  fi
  if [ ! -z "${STORAGE_ENGINE_SWAP}" ]; then
    STORAGE_ENGINE_SWAP_DUR_START="${EPOCHREALTIME}"
    if [ -z "${STORAGE_ENGINE_SWAP_PERCENTAGE}" ]; then
      STORAGE_ENGINE_SWAP_PERCENTAGE=100
    fi
    if ! [[ "${STORAGE_ENGINE_SWAP_PERCENTAGE}" =~ ^[0-9]+$ ]] || [ "${STORAGE_ENGINE_SWAP_PERCENTAGE}" -lt 1 ] || [ "${STORAGE_ENGINE_SWAP_PERCENTAGE}" -gt 100 ]; then
      assemble_abort "STORAGE_ENGINE_SWAP_PERCENTAGE must be an integer in the range 1-100 (current value: '${STORAGE_ENGINE_SWAP_PERCENTAGE}')"
    fi
    SE_SWAP_SED="s|InnoDB|${STORAGE_ENGINE_SWAP}|gi;s|Aria|${STORAGE_ENGINE_SWAP}|gi;s|MyISAM|${STORAGE_ENGINE_SWAP}|gi;s|BLACKHOLE|${STORAGE_ENGINE_SWAP}|gi;s|RocksDB|${STORAGE_ENGINE_SWAP}|gi;s|RocksDBcluster|${STORAGE_ENGINE_SWAP}|gi;s|MRG_MyISAM|${STORAGE_ENGINE_SWAP}|gi;s|SEQUENCE|${STORAGE_ENGINE_SWAP}|gi;s|NDB|${STORAGE_ENGINE_SWAP}|gi;s|NDBCluster|${STORAGE_ENGINE_SWAP}|gi;s|CSV|${STORAGE_ENGINE_SWAP}|gi;s|TokuDB|${STORAGE_ENGINE_SWAP}|gi;s|MEMORY|${STORAGE_ENGINE_SWAP}|gi;s|ARCHIVE|${STORAGE_ENGINE_SWAP}|gi;s|CASSANDRA|${STORAGE_ENGINE_SWAP}|gi;s|CONNECT|${STORAGE_ENGINE_SWAP}|gi;s|EXAMPLE|${STORAGE_ENGINE_SWAP}|gi;s|FALCON|${STORAGE_ENGINE_SWAP}|gi;s|HEAP|${STORAGE_ENGINE_SWAP}|gi;s|${STORAGE_ENGINE_SWAP}cluster|${STORAGE_ENGINE_SWAP}|gi;s|MARIA|${STORAGE_ENGINE_SWAP}|gi;s|MEMORYCLUSTER|${STORAGE_ENGINE_SWAP}|gi;s|MERGE|${STORAGE_ENGINE_SWAP}|gi;s|FEDERATED|${STORAGE_ENGINE_SWAP}|gi;s|\$engine|${STORAGE_ENGINE_SWAP}|gi;s|NonExistentEngine|${STORAGE_ENGINE_SWAP}|gi;s|Spider|${STORAGE_ENGINE_SWAP}|gi;"
    if [ "${STORAGE_ENGINE_SWAP_PERCENTAGE}" -eq 100 ]; then
      sed -i "${SE_SWAP_SED}" ${TRIAL_SQL}
    else
      # Mark the lines to swap first, spread evenly over the file, then swap the engines in the
      # marked lines only and drop the marker again. Marking gives the exact percentage asked for,
      # where a fixed step (one line in every 100/percentage) only lands on a divisor of 100
      if ! awk -v pct=${STORAGE_ENGINE_SWAP_PERCENTAGE} '{if(int(NR*pct/100)>int((NR-1)*pct/100)){printf "\001%s\n",$0}else{print}}' ${TRIAL_SQL} > ${TRIAL_SQL}.temp; then
        assemble_abort "marking the lines for STORAGE_ENGINE_SWAP failed. Check the free space in ${TRIAL_SQL_DIR}"
      fi
      mv ${TRIAL_SQL}.temp ${TRIAL_SQL}
      sed -i "/^\x01/{${SE_SWAP_SED}};s|^\x01||" ${TRIAL_SQL}
    fi
    SE_SWAP_SED=
    echoit "STORAGE_ENGINE_SWAP: Swapping ${STORAGE_ENGINE_SWAP_PERCENTAGE}% of in-SQL storage engines to ${STORAGE_ENGINE_SWAP} took $(duration ${STORAGE_ENGINE_SWAP_DUR_START})s"
    STORAGE_ENGINE_SWAP_DUR_START=
  fi
  # Interleave post-storage-engine-swap to ensure not modifying CREATE TABLE ... ENGINE=... statements in interleave SQL
  if [ "${INTERLEAVE}" == "1" ]; then
    INTERLEAVE_DUR_START="${EPOCHREALTIME}"
    echoit "INTERLEAVE: Interleaving SQL in INTERLEAVE_SQL into the input file every ${INTERLEAVE_LINES}th line"
    mv ${TRIAL_SQL} ${TRIAL_SQL}.temp

    INTERLEAVE_SQL_TEMP_FILE="$(mktemp | tr -d '\n')"
    echo -e "${INTERLEAVE_SQL}" > ${INTERLEAVE_SQL_TEMP_FILE}
    awk -v sql_file=${INTERLEAVE_SQL_TEMP_FILE} "NR%${INTERLEAVE_LINES}==0{while(getline line<sql_file) print line;close(sql_file)}{print}" ${TRIAL_SQL}.temp > ${TRIAL_SQL}

    rm -f ${TRIAL_SQL}.temp ${INTERLEAVE_SQL_TEMP_FILE}
    INTERLEAVE_SQL_TEMP_FILE=
    INTERLEAVE_FIN_LINES="$(wc -l ${TRIAL_SQL} | awk '{print $1}')"
    if [ "${INTERLEAVE_FIN_LINES}" -eq 0 ]; then
      assemble_abort "INTERLEAVE interleaving failed: the resulting outfile, (${TRIAL_SQL}) contains 0 lines"
    fi
    echoit "INTERLEAVE: Interleaving into ${TRIAL_SQL} done ($(( INTERLEAVE_FIN_LINES - ASM_LINES )) lines added) in $(duration ${INTERLEAVE_DUR_START})s"
    INTERLEAVE_FIN_LINES=
    INTERLEAVE_DUR_START=
  fi
  # The following needs to be the last step in the process (except SWAP_ALL_TABLE_NAMES_TO_T1) to ensure that any INTERLEAVE sql is also swapped to table name t1
  if [ "${SWAP_CREATE_TABLE_NAMES_TO_T1}" != "0" ]; then
    SWAP_CREATE_TABLE_NAMES_TO_T1_START="${EPOCHREALTIME}"
    echoit "SWAP_CREATE_TABLE_NAMES_TO_T1 Active: changing all CREATE TABLE table names to t1"
    sed -i 's|CREATE TABLE\([^(]*\)\+(|CREATE TABLE \1 (|gi;s|[ \t][ \t]\+| |g;s|CREATE TABLE [^ ]\+ |CREATE TABLE t1 |gi' ${TRIAL_SQL}
    echoit "SWAP_CREATE_TABLE_NAMES_TO_T1: Swapping CREATE TABLE table names to t1 took $(duration ${SWAP_CREATE_TABLE_NAMES_TO_T1_START})s"
    SWAP_CREATE_TABLE_NAMES_TO_T1_START=
  fi
  # The following needs to be the last step in the process (ref above for reason)
  # Ref:  grep --binary-files=text -oi "CREATE TABLE [^ (]\+[ (]" main-ms-ps-md.sql | tr -d '`' | tr -d '(' | sed 's|[ ]*$||' | sed 's|create table|CREATE TABLE|i' | grep -v "TABLE IF" | sort -h | uniq -c |sort -n | tac | head -n20
  if [ "${SWAP_ALL_TABLE_NAMES_TO_T1}" != "0" ]; then
    SWAP_ALL_TABLE_NAMES_TO_T1_START="${EPOCHREALTIME}"
    echoit "SWAP_ALL_TABLE_NAMES_TO_T1 Active: changing all table names to t1"
    # Except for the provisions at the end of the list of changes, do not add the sed global 'g' option as otherwise some statements will become invalid due to repeated t1
    sed -i "s|\([ \.]\+\)t[0-9]\+\([\`', \t();]\+\)|\1t1\2|" ${TRIAL_SQL}
    sed -i "s|\([ \.]\+\)t[itm]\+\([\`', \t();]\+\)|\1t1\2|" ${TRIAL_SQL}
    sed -i "s|\([ \.]\+\)t\([\`', \t();]\+\)|\1t1\2|" ${TRIAL_SQL}
    sed -i "s|\([ \.]\+\)m[0-9]\+\([\`', \t();]\+\)|\1t1\2|" ${TRIAL_SQL}
    sed -i "s|\([ \.]\+\)articles\([\`', \t();]\+\)|\1t1\2|" ${TRIAL_SQL}
    sed -i "s|\([ \.]\+\)foo\([\`', \t();]\+\)|\1t1\2|" ${TRIAL_SQL}
    sed -i "s|\([ \.]\+\)bar\([\`', \t();]\+\)|\1t1\2|" ${TRIAL_SQL}
    sed -i "s|\([ \.]\+\)Ｔ[４７１]\+\([\`', \t();]\+\)|\1t1\2|" ${TRIAL_SQL}
    sed -i "s|\([ \.]\+\)db[0-9]\+.t[0-9]\+\([\`', \t();]\+\)|\1t1\2|" ${TRIAL_SQL}
    sed -i "s|\([ \.]\+\)child\([\`', \t();]\+\)|\1t1\2|" ${TRIAL_SQL}
    sed -i "s|\([ \.]\+\)parent\([\`', \t();]\+\)|\1t1\2|" ${TRIAL_SQL}
    sed -i "s|\([ \.]\+\)ｱｱｱ\([\`', \t();]\+\)|\1t1\2|" ${TRIAL_SQL}
    sed -i "s|\([ \.]\+\)龗龗龗\([\`', \t();]\+\)|\1t1\2|" ${TRIAL_SQL}
    sed -i "s|\([ \.]\+\)龖龖龖\([\`', \t();]\+\)|\1t1\2|" ${TRIAL_SQL}
    sed -i "s|\([ \.]\+\)testdb_wl5522.t1\([\`', \t();]\+\)|\1t1\2|" ${TRIAL_SQL}
    sed -i "s|\([ \.]\+\)tm[0-9]\+\([\`', \t();]\+\)|\1t1\2|" ${TRIAL_SQL}
    sed -i "s|\([ \.]\+\)src\([\`', \t();]\+\)|\1t1\2|" ${TRIAL_SQL}
    sed -i "s|\([ \.]\+\)federated.t1\([\`', \t();]\+\)|\1t1\2|" ${TRIAL_SQL}
    sed -i "s|\([ \.]\+\)variant\([\`', \t();]\+\)|\1t1\2|" ${TRIAL_SQL}
    sed -i "s|\([ \.]\+\)RocksDB.t1\([\`', \t();]\+\)|\1t1\2|" ${TRIAL_SQL}
    sed -i "s|\([ \.]\+\)ndb\$test\([\`', \t();]\+\)|\1t1\2|" ${TRIAL_SQL}
    sed -i "s|\([ \.]\+\)test_wl5522.t1\([\`', \t();]\+\)|\1t1\2|" ${TRIAL_SQL}
    sed -i "s|\([ \.]\+\)test_ps_sample_pages\([\`', \t();]\+\)|\1t1\2|" ${TRIAL_SQL}
    sed -i "s|\([ \.]\+\)t1_will_crash\([\`', \t();]\+\)|\1t1\2|" ${TRIAL_SQL}
    sed -i "s|\([ \.]\+\)d[0-9]\+.t[0-9]\+\([\`', \t();]\+\)|\1t1\2|" ${TRIAL_SQL}
    sed -i "s|\([ \.]\+\)db\([\`', \t();]\+\)|\1t1\2|" ${TRIAL_SQL}
    sed -i "s|t1[ \t]\+TO[ \t]\+t1|t1 TO t2|gi" ${TRIAL_SQL}  # RENAME TABLE provision
    sed -i "s|t1[ \t]\+LIKE[ \t]\+t1|t2 LIKE t1|gi" ${TRIAL_SQL}  # CREATE TABLE...LIKE provision
    sed -i "s|t1[ \t]\+RENAME TO[ \t]\+t1|t1 RENAME TO t2|gi" ${TRIAL_SQL}  # ALTER TABLE provision
    sed -i "s|t1[ \t]*,[ \t]*t1|t1|gi" ${TRIAL_SQL}  # SELECT, DROP TABLE, etc. provision
    sed -i "s|([ \t]*t1[ \t]*,[ \t]*t[0-9]\+[ \t]*)|(t2,t3)|gi;s|([ \t]*t1[ \t]*,[ \t]*t[0-9]\+[ \t]*,[ \t]*t[0-9]\+[ \t]*)|(t2,t3)|gi" ${TRIAL_SQL}  # CREATE TABLE...UNION provision
    # A few other minor provisions can be made: CREATE TABLE...SELECT, [LEFT etc.] JOIN (w/o aliases), etc.
    echoit "ALL_NAMES_SWAP: Swapping all table names to t1 took $(duration ${SWAP_ALL_TABLE_NAMES_TO_T1_START})s"
    SWAP_ALL_TABLE_NAMES_TO_T1_START=
  fi
  cap_sql_lines "${TRIAL_SQL}" "the assembled SQL"  # Last: the interleave and the swaps run above and can add lines
  TRIAL_SQL_LINES="$(wc -l < ${TRIAL_SQL})"
  PQUERY_INFILE_LINES="${TRIAL_SQL_LINES}"  # The lines in the file pquery reads, for the input against executed ratio after the trial ran. A multi-threaded or query correctness trial hands pquery a smaller file, and sets this again
  echoit "Input SQL: ${TRIAL_SQL} (${TRIAL_SQL_LINES} lines) built in $(duration ${ASM_START})s"
}

# Main startup
if [ ${QUERY_DURATION_TESTING} -eq 1 ]; then
  echoit "MODE: Query Duration Testing"
  if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 ]; then
    echoit "QUERY_CORRECTNESS_TESTING and QUERY_DURATION_TESTING cannot be both active at the same time due to parsing limitations. This is the case. Please disable one of them."
    exit 1
  fi
elif [[ "${PXB_CRASH_RUN}" -eq 1 ]]; then
  echoit "MODE: Percona Xtrabackup crash test run"
  if [[ ! -d ${PXB_BASEDIR} ]]; then
    echoit "Assert: $PXB_BASEDIR does not exist. Terminating!"
    exit 1
  fi
elif [ "${CRASH_RECOVERY_TESTING}" -eq 1 ]; then
  echoit "MODE: Crash Recovery Testing"
  if [[ ${REPLICATION} -eq 0 ]]; then
    echoit "MODE: Crash Recovery Testing"
  else
    echoit "MODE: Crash Recovery Testing as part of replication testing"
  fi
elif [ "${QUERY_CORRECTNESS_TESTING}" -eq 1 ]; then
  echoit "MODE: Query Correctness Testing"
elif [ "${MARIADB_BINLOG_RECOVERY_TESTING}" -eq 1 ]; then
  echoit "MODE: mariadb-binlog Recovery Testing"
  echoit "Note: BINLOG_RECOVERY_ERROR markers can capture 'expected' replay errors (master failed on a statement, the error is encoded in the binlog, replay re-fires it). --force --binary-mode (set by the framework) suppresses most. BINLOG_CHECKSUM_DIFF markers indicate the binlog replay produced a different DB state than the original - these are the more likely real bugs. Review each saved trial individually."
  if [ "${REPLICATION}" == "1" ]; then
    echoit "Assert: mariadb-binlog recovery testing is not compatible with replication testing (REPLICATION=1}, yet; feel free to implement it"
    exit 1
  fi
  if [ "${RR_TRACING}" == "1" ]; then
    echoit "Assert: mariadb-binlog recovery testing is not compatible with RR tracing (RR_TRACING=1), yet; feel free to implement it"
    exit 1
  fi
  if [ "${VALGRIND_RUN}" == "1" ]; then
    echoit "Assert: mariadb-binlog recovery testing is not compatible with Valgrind testing (VALGRIND_RUN=1), yet; feel free to implement it"
    exit 1
  fi
  if [ "${QUERY_CORRECTNESS_TESTING}" == "1" ]; then
    echoit "Assert: mariadb-binlog recovery testing is not meant to be used in combination with query correctness testing (QUERY_CORRECTNESS_TESTING=1), please disable either, or both"
    exit 1
  fi
  if [ "${ADD_RANDOM_OPTIONS}" == "1" ]; then
    echoit "Assert: mariadb-binlog recovery testing is not compatible with adding random options (ADD_RANDOM_OPTIONS=1), yet; feel free to implement it"
    exit 1
  fi
  if [[ "${MYEXTRA^^}" != *"LOG_BIN"* ]]; then
    echoit "Assert: mariadb-binlog recovery testing is active (MARIADB_BINLOG_RECOVERY_TESTING=1), yet 'log_bin' is not part of the MYEXTRA options"
    exit 1
  fi
  if [[ "${MYEXTRA^^}" != *"=ROW"* && "${MYEXTRA^^}" != *"=STATEMENT"* && "${MYEXTRA^^}" != *"=MIXED"* ]]; then
    echoit "Assert: mariadb-binlog recovery testing is active (MARIADB_BINLOG_RECOVERY_TESTING=1), yet '=ROW' nor '=STATEMENT' nor '=MIXED' is part of the MYEXTRA options"
    exit 1
  fi
elif [ "${QUERY_CORRECTNESS_TESTING}" -ne 1 ]; then
  if [ "${REPLICATION}" == "1" ]; then
    MODEPREFIX='MODE: Replication testing | SUB'
  fi
  if [ "${VALGRIND_RUN}" == "1" ]; then
    if [ "${THREADS}" -eq 1 ]; then
      echoit "${MODEPREFIX}MODE: Single threaded Valgrind pquery testing"
    else
      echoit "${MODEPREFIX}MODE: Multi threaded Valgrind pquery testing"
    fi
  else
    if [ "${THREADS}" -eq 1 ]; then
      echoit "${MODEPREFIX}MODE: Single threaded pquery testing"
    else
      echoit "${MODEPREFIX}MODE: Multi threaded pquery testing"
    fi
  fi
fi
SRC_DESC=""
[ "${USE_GENERATOR}" -eq 1 ] && SRC_DESC="generator (${QUERIES_PER_GENERATOR_RUN} queries per trial)"
[ "${USE_REVGEN}" -eq 1 ] && SRC_DESC="${SRC_DESC:+${SRC_DESC} + }revgen (${QUERIES_PER_REVGEN_RUN} queries per trial)"
[ "${USE_INFILE}" -eq 1 ] && SRC_DESC="${SRC_DESC:+${SRC_DESC} + }INFILE ${INFILE}"
[ "${USE_ALL_DISK_SQL}" -eq 1 ] && SRC_DESC="${SRC_DESC:+${SRC_DESC} + }all SQL on disk (${QUERIES_PER_ALL_DISK_RUN} lines, new every ${ALL_DISK_SQL_NEW_QUERIES_EVERY_X_TRIALS} trials)"
echoit "Sources: ${SRC_DESC}. Each source contributes lines to one file per trial, and its share is its line count. That file is shuffled"
echoit "PQUERY_MAX_SQL_LINES: ${PQUERY_MAX_SQL_LINES} (the per-trial SQL is cut back to this many lines, from the end, so the last source in use loses lines first)"
echoit "Per-trial SQL: ${TRIAL_SQL_DIR}/${RANDOMD}_<trial>.sql"
SRC_DESC=
if [ ${ADV_FILTER_SQL} -eq 1 ]; then
  echoit "ADV_FILTER_SQL Active: any SQL line matching ADV_FILTER_LIST is removed from the per-trial SQL"
fi
if [ ${FILTER_SQL} -eq 1 ]; then
  echoit "FILTER_SQL Active: any SQL line matching a line in ${SCRIPT_PWD}/filter.sql is removed from the per-trial SQL, in one pass over all the sources together"
fi
if [ ! -z "${STORAGE_ENGINE_SWAP}" ]; then
  echoit "STORAGE_ENGINE_SWAP Active: changing storage engine references to ${STORAGE_ENGINE_SWAP} in ${STORAGE_ENGINE_SWAP_PERCENTAGE:-100}% of the per-trial SQL lines"
fi
if [ "${PRELOAD}" == "1" ]; then
  echoit "PRELOAD SQL Active: (${PRELOAD_SQL} will be preloaded for all trials, and prepended to trial SQL traces"
else
  echoit "PRELOAD SQL Active: NO"
fi
if [ "${ENABLE_ENCRYPTION}" -eq 1 ]; then
  echo "ENABLE_ENCRYPTION Active: YES, MYENCRYPTION: '${MYENCRYPTION}' (using the file-key-management plugin)"
else
  echo "ENABLE_ENCRYPTION Active: NO"
fi
if [ "$(whoami)" == "root" ]; then
  MYEXTRA="--user=root ${MYEXTRA}"
  echo "As the user running this script is root, adding '--user=root' to MYEXTRA"
fi
if [[ "${MDG_CLUSTER_RUN}" -eq 1 && "${MDG}" -eq 0 ]]; then
  echoit "As MDG_CLUSTER_RUN=1, this script is auto-assuming this is a MDG run and will set MDG=1"
  MDG=1
fi
if [[ "${GRP_RPL_CLUSTER_RUN}" -eq 1 && "${GRP_RPL}" -eq 0 ]]; then
  echoit "As GRP_RPL_CLUSTER_RUN=1, this script is auto-assuming this is a Group Replication run and will set GRP_RPL=1"
  GRP_RPL=1
fi
if [ "${MDG_CLUSTER_RUN}" == "1" ]; then
  if [ "${QUERIES_PER_THREAD}" -lt 2147483647 ]; then # Starting up a cluster takes more time, so don't rotate too quickly
    echoit "Note: As this is a MDG_CLUSTER_RUN=1 run, and QUERIES_PER_THREAD was set to only ${QUERIES_PER_THREAD}, this script is setting the queries per thread to the required minimum of 2147483647 for this run"
    QUERIES_PER_THREAD=2147483647 # Max int
  fi
  if [ ${PQUERY_RUN_TIMEOUT} -lt 120 ]; then # Starting up a cluster takes more time, so don't rotate too quickly
    echoit "Note: As this is a MDG=1 run, and PQUERY_RUN_TIMEOUT was set to only ${PQUERY_RUN_TIMEOUT}, this script is setting the timeout to the required minimum of 120 for this run"
    PQUERY_RUN_TIMEOUT=120
  fi
  ADD_RANDOM_OPTIONS=0
  ADD_RANDOM_TOKUDB_OPTIONS=0
  ADD_RANDOM_ROCKSDB_OPTIONS=0
  GRP_RPL=0
  GRP_RPL_CLUSTER_RUN=0
fi
if [ "${GRP_RPL}" == "1" ]; then
  if [ ${QUERIES_PER_THREAD} -lt 2147483647 ]; then # Starting up a cluster takes more time, so don't rotate too quickly
    echoit "Note: As this is a GRP_RPL=1 run, and QUERIES_PER_THREAD was set to only ${QUERIES_PER_THREAD}, this script is setting the queries per thread to the required minimum of 2147483647 for this run"
    QUERIES_PER_THREAD=2147483647 # Max int
  fi
  if [ ${PQUERY_RUN_TIMEOUT} -lt 120 ]; then # Starting up a cluster takes more time, so don't rotate too quickly
    echoit "Note: As this is a GRP_RPL=1 run, and PQUERY_RUN_TIMEOUT was set to only ${PQUERY_RUN_TIMEOUT}, this script is setting the timeout to the required minimum of 120 for this run"
    PQUERY_RUN_TIMEOUT=120
  fi
  ADD_RANDOM_TOKUDB_OPTIONS=0
  ADD_RANDOM_ROCKSDB_OPTIONS=0
  MDG=0
  MDG_CLUSTER_RUN=0
fi

if [[ ${REPLICATION} -eq 1 ]]; then
  if [ "${CRASH_RECOVERY_TESTING}" -eq 1 ]; then
    echoit "Note: As this is a Replication crash recovery testing run, setting the THREADS to 100 and PQUERY_RUN_TIMEOUT to at least 60 (or as configured larger) for this run"
    THREADS=100
  else
    echoit "Note: As this is a Replication testing run, setting PQUERY_RUN_TIMEOUT to a minimum 60 (or as configured larger) for this run"
  fi
  if [ -z "${PQUERY_RUN_TIMEOUT}" ]; then
    PQUERY_RUN_TIMEOUT=60
  fi
  if [ "${PQUERY_RUN_TIMEOUT}" -lt 60 ]; then
    PQUERY_RUN_TIMEOUT=60
  fi
fi
if [ ${THREADS} -gt 1 ]; then
  # We may want to drop this to 20 seconds required?
  if [ ${PQUERY_RUN_TIMEOUT} -lt 30 ]; then
    echoit "Note: As this is a multi-threaded run, and PQUERY_RUN_TIMEOUT was set to only ${PQUERY_RUN_TIMEOUT}, this script is setting the timeout to the required minimum of 30 for this run"
    PQUERY_RUN_TIMEOUT=30
  fi
  if [ ${QUERY_DURATION_TESTING} -eq 1 ]; then
    echoit "Note: As this is a QUERY_DURATION_TESTING=1 run, and THREADS was set to ${THREADS}, this script is setting the number of threads to the required setting of 1 thread for this run"
    THREADS=1
  fi
  if [ -z "${MULTI_THREADED_TESTC_LINES}" ]; then
    echoit "Assert: MULTI_THREADED_TESTC_LINES is not set, yet the number of threads is greater than 1. Please setMULTI_THREADED_TESTC_LINES (recommended to be at least 100-200K)"
    exit 1
  fi
  if [ ${PQUERY_MAX_SQL_LINES} -lt ${MULTI_THREADED_TESTC_LINES} ]; then
    echoit "Assert: PQUERY_MAX_SQL_LINES < MULTI_THREADED_TESTC_LINES (${PQUERY_MAX_SQL_LINES}<${MULTI_THREADED_TESTC_LINES}). The per-trial SQL is capped to PQUERY_MAX_SQL_LINES lines, so a larger chunk can never be taken from it. Lower MULTI_THREADED_TESTC_LINES, or raise PQUERY_MAX_SQL_LINES."
    exit 1
  fi
  if [ "${USE_ALL_DISK_SQL}" -eq 1 ] && [ "${USE_GENERATOR}" -ne 1 ] && [ "${USE_REVGEN}" -ne 1 ] && [ "${USE_INFILE}" -ne 1 ] && [ ${QUERIES_PER_ALL_DISK_RUN} -lt ${MULTI_THREADED_TESTC_LINES} ]; then
    echoit "Assert: QUERIES_PER_ALL_DISK_RUN < MULTI_THREADED_TESTC_LINES (${QUERIES_PER_ALL_DISK_RUN}<${MULTI_THREADED_TESTC_LINES}), and the all-disk SQL is the only source. Set QUERIES_PER_ALL_DISK_RUN to a number equal to or larger than MULTI_THREADED_TESTC_LINES. Adding a reasonable margin (i.e. 'larger than') is recommended."
    exit 1
  fi
fi
if [ ${CRASH_RECOVERY_TESTING} -eq 1 ]; then
  if [ ${QUERY_DURATION_TESTING} -eq 1 ]; then
    echoit "CRASH_RECOVERY_TESTING and QUERY_DURATION_TESTING cannot be both active at the same time due to parsing limitations. This is the case. Please disable one of them."
    exit 1
  fi
  if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 ]; then
    echoit "CRASH_RECOVERY_TESTING and QUERY_CORRECTNESS_TESTING cannot be both active at the same time due to parsing limitations. This is the case. Please disable one of them."
    exit 1
  fi
  #if [ ${THREADS} -lt 50 ]; then
  #  echoit "Note: As this is a CRASH_RECOVERY_TESTING=1 run, and THREADS was set to only ${THREADS}, this script is setting the number of threads to the required minimum of 50 for this run"
  #  THREADS=50
  #fi
  #if [ ${PQUERY_RUN_TIMEOUT} -lt 30 ]; then
  #  echoit "Note: As this is a CRASH_RECOVERY_TESTING=1 run, and PQUERY_RUN_TIMEOUT was set to only ${PQUERY_RUN_TIMEOUT}, this script is setting the timeout to the required minimum of 30 for this run"
  #  PQUERY_RUN_TIMEOUT=30
  #fi
  if [ -z "${CRASH_RECOVERY_KILL_BEFORE_END_SEC}" ]; then
    echoit "Assert: CRASH_RECOVERY_KILL_BEFORE_END_SEC is empty while CRASH_RECOVERY_TESTING=1: cannot continue"
    exit 1
  elif [ "$[ ${CRASH_RECOVERY_KILL_BEFORE_END_SEC} + 5 ]" -gt "${PQUERY_RUN_TIMEOUT}" ]; then
    echoit "Note: as CRASH_RECOVERY_KILL_BEFORE_END_SEC + 5 > PQUERY_RUN_TIMEOUT, PQUERY_RUN_TIMEOUT will be increased to CRASH_RECOVERY_KILL_BEFORE_END_SEC + 5 (original CRASH_RECOVERY_KILL_BEFORE_END_SEC: ${CRASH_RECOVERY_KILL_BEFORE_END_SEC}, and original PQUERY_RUN_TIMEOUT: ${PQUERY_RUN_TIMEOUT}"
    PQUERY_RUN_TIMEOUT=$[ ${CRASH_RECOVERY_KILL_BEFORE_END_SEC} + 5 ]
  fi
fi
if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 -a ${THREADS} -ne 1 ]; then
  echoit "Note: As this is a QUERY_CORRECTNESS_TESTING=1 run, and THREADS was set to ${THREADS}, this script is setting the number of threads to the required setting of 1 thread for this run"
  THREADS=1
fi
if [ ${USE_GENERATOR} -eq 1 -o ${USE_REVGEN} -eq 1 ] && [ ${STORE_COPY_OF_INFILE} -eq 1 ]; then
  echoit "Note: as the SQL Generator and/or revgen will be used instead of a fixed input file (a fresh input file is produced per trial), STORE_COPY_OF_INFILE has automatically been set to 0."
  STORE_COPY_OF_INFILE=0
fi
if [ "${VALGRIND_RUN}" == "1" ]; then
  echoit "Note: As this is a VALGRIND_RUN=1 run, this script is increasing MYSQLD_START_TIMEOUT (${MYSQLD_START_TIMEOUT}) by 240 seconds because Valgrind is very slow in starting up mysqld/mariadbd"
  MYSQLD_START_TIMEOUT=$((${MYSQLD_START_TIMEOUT} + 240))
  if [ ${MYSQLD_START_TIMEOUT} -lt 300 ]; then
    echoit "Note: As this is a VALGRIND_RUN=1 run, and MYSQLD_START_TIMEOUT was set to only ${MYSQLD_START_TIMEOUT}), this script is setting the timeout to the required minimum of 300 for this run"
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
  if [ ${USE_GENERATOR} -eq 1 -o ${USE_REVGEN} -eq 1 ]; then
    KILL_PIDS2=$(ps -ef | grep -E 'generator|revgen' | grep -v "grep" | awk '{print $2}' | tr '\n' ' ')
  fi
  KILL_PIDS="${KILL_PIDS1} ${KILL_PIDS2}"
  if [ "${KILL_PIDS}" != "" ]; then
    echoit "Terminating the following PID's: ${KILL_PIDS}"
    kill -9 ${KILL_PIDS} > /dev/null 2>&1
  fi
  if [ -d ${RUNDIR}/${TRIAL}/ ]; then
    echoit "Done. Moving the trial $0 was currently working on to workdir as ${WORKDIR}/${TRIAL}/..."
    while read -r MV_OUTPUT; do echoit "Trial move: ${MV_OUTPUT}" ORANGE; done < <(mv ${RUNDIR}/${TRIAL}/ ${WORKDIR}/ 2>&1)
  fi
  if [ $USE_GENERATOR -eq 1 -o $USE_REVGEN -eq 1 ]; then
    echoit "Attempting to cleanup generator/revgen temporary files..."
    rm -f ${SCRIPT_PWD}/generatorcpp/out${RANDOMD}*.sql ${SCRIPT_PWD}/generatorcpp/out${RANDOMD}.sql.part* ${SCRIPT_PWD}/revgen/outrev${RANDOMD}*.sql ${SCRIPT_PWD}/revgen/outrev${RANDOMD}.sql.part*
  fi
  echoit "Attempting to cleanup the per-trial SQL of this run..."
  rm -f ${TRIAL_SQL_DIR}/${RANDOMD}_*  # The glob covers the per-trial SQL, the all-disk pool, and any part file a transform was writing
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

savetrial() {  # Only call this if we definitely want to save a trial
  if [ "${TRIAL_SAVED}" == "1" ]; then
    echoit "Warning: savetrial() was called but TRIAL_SAVED was already 1. Ensure this trial has been actually saved as we don't attempt to save it again now"
    return 1
  fi
  if [ ! -d "${RUNDIR}/${TRIAL}" ]; then
    echoit "Warning: savetrial() was called, however the trial rundir (${RUNDIR}/${TRIAL}) was already removed, likely by removetrial() or similar"  # TODO: needs occurences to debug further, likely 100% cosmetic; likely removetrial() was called before a later savetrial(), requiring some extra coverage code in the place it happened
    return 1
  fi
  if [ ! -z "$(ls ${RUNDIR}/${TRIAL}/*/*core* 2>/dev/null)" ]; then  # ./data/*core* and ./node*/*core* compatible
    add_handy_scripts
  fi
  if [ "${PRELOAD}" == "1" -a ${ISSTARTED} -eq 1 ]; then  # It only makes sense to save the preload in case the server was ever started (and besides, the preload trace won't exist unless the server was started correctly), otherwise we will get incorrect messages here saying 'preload did not exist in savetrial()' which is correct, but not applicable
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
    PQUERY_DEFAULT_FILE=
  fi
  # If there are *SAN bugs, delete any known ones from the top of the error log(s)
  if [ "${SAN_KNOWN_BUGS_DROPPED_FROM_ERROR_LOG_FLAG}" != "1" ]; then
    if grep --binary-files=text -qiE "=ERROR:|runtime error:|AddressSanitizer:|ThreadSanitizer:|LeakSanitizer:|MemorySanitizer:" ${RUNDIR}/${TRIAL}/log/*.err ${RUNDIR}/${TRIAL}/node*/node*.err 2>/dev/null; then
      SAN_KNOWN_BUGS_DROPPED_FROM_ERROR_LOG_FLAG=1
      echoit "Dropping any known *SAN bugs from the top of the error log for trial ${TRIAL}, if any"  # Note that reducer.sh matches this behavior when a TOP_SAN_ISSUES_REMOVED flag file is present for the trial, and drop_one_or_more_san_from_log.sh will create this flag when a pquery-run.sh based trial (like here) was found, and only writes this flag file if it has removed top level known issue(s)/bug(s)
      CUR_PWD_TMP="${PWD}"
      cd "${RUNDIR}/${TRIAL}"
      ${SCRIPT_PWD}/drop_one_or_more_san_from_log.sh  # Do not add any options to this script call as that will cause the top SAN issue to be deleted, irrespective of whetter an issue is known or not
      cd "${CUR_PWD_TMP}"
      CUR_PWD_TMP=
    fi
  fi
  if grep --binary-files=text -qiE "=ERROR:|runtime error:|AddressSanitizer:|ThreadSanitizer:|LeakSanitizer:|MemorySanitizer:" ${RUNDIR}/${TRIAL}/log/*.err ${RUNDIR}/${TRIAL}/node*/node*.err 2>/dev/null; then
    # As we are already post-'known SAN* bug filtering', and *SAN issues remain (as the grep shows), this trial needs to always be saved; it cannot be a known issue as all known issues are already removed by drop_one_or_more_san_from_log.sh
    if [ "$(echo "${TEXT}" | grep --binary-files=text -o 'no core.*empty output' | grep --binary-files=text -o 'no core' | head -n1)" == "no core" ]; then
      echo "Debug Assert: a *SAN text string was found in the error log at ${RUNDIR}/${TRIAL}/log/*.err yet TEXT ('${TEXT}') contains 'no core.*empty output'. Possibly master vs slave issue. Feel free to improve code in this area."  # TODO
    fi
    cd ${RUNDIR}/${TRIAL} || exit 1
    # TODO: Add Galera+SAN configuration (this code was copied from elsewhere but seems to require updating for ${j}?)
    #if [[ "${MDG}" -eq 1 ]]; then
    #  export GALERA_ERROR_LOGS=${RUNDIR}/${TRIAL}/node${j}/node${j}.err
    #  TEXT="$(${SCRIPT_PWD}/new_text_string.sh)" # Note this will auto-call san_text_string.sh or fallback_text_string.sh if required
    #  echo "${TEXT}" | grep -v '^[ \t]*$' > ${RUNDIR}/${TRIAL}/node${j}/MYBUG
    #  export GALERA_ERROR_LOGS=""
    #else
      echoit "SAN Bug found: $(${SCRIPT_PWD}/new_text_string.sh)" 
    #fi
    cd - >/dev/null || exit 1
    NEWBUGS=$[ ${NEWBUGS} + 1 ]
    if [ -r ${RUNDIR}/${TRIAL}/TOP_SAN_ISSUES_REMOVED ]; then
      echoit "[${NEWBUGS}] *** NEW SAN BUG *** (as detected by dropping all known SAN bugs from the top of the error log, if any)"
    else
      echoit "[${NEWBUGS}] *** NEW SAN BUG *** (not found in ${SCRIPT_PWD}/known_bugs.strings, or found but marked as already fixed)"
    fi
  fi
  echoit "Saving Trial: Moving rundir from ${RUNDIR}/${TRIAL} to ${WORKDIR}/${TRIAL}"
  # A rundir in tmpfs and a workdir on disk make this a copy and unlink, so a temporary file the server
  # removes while the move runs is reported here. Routed through echoit to keep one stamped line per event
  while read -r MV_OUTPUT; do echoit "Trial move: ${MV_OUTPUT}" ORANGE; done < <(mv ${RUNDIR}/${TRIAL}/ ${WORKDIR}/ 2>&1)
  chmod -R +rX ${WORKDIR}/${TRIAL}/
  if [ "$PMM_CLEAN_TRIAL" == "1" ]; then
    echoit "Removing mysql instance (pq${RANDOMD}-${TRIAL}) from pmm-admin"
    sudo pmm-admin remove mysql pq${RANDOMD}-${TRIAL} > /dev/null
  fi
  SAVED=$(($SAVED + 1))
  return 0
}

removetrial() {
  if [ "${TRIAL_SAVED}" == "1" ]; then
    echoit "Warning: removetrial() was called but TRIAL_SAVED was already 1. This should not happen"
    return 1
  fi
  echoit "Removing trial rundir ${RUNDIR}/${TRIAL}"
  if [ "${RUNDIR}" != "" -a "${TRIAL}" != "" -a -d ${RUNDIR}/${TRIAL}/ ]; then # Protection against dangerous rm's
    rm -Rf ${RUNDIR:?}/${TRIAL:?}/
  fi
  if [ "$PMM_CLEAN_TRIAL" == "1" ]; then
    echoit "Removing mysql instance (pq${RANDOMD}-${TRIAL}) from pmm-admin"
    sudo pmm-admin remove mysql pq${RANDOMD}-${TRIAL} > /dev/null
  fi
  return 0
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
  mkdir -p ${WORKDIR}/${TRIAL}
  chmod -R +rX ${WORKDIR}/${TRIAL}/
  cp ${RUNDIR}/${TRIAL}/*.sql ${WORKDIR}/${TRIAL}/
  rm -Rf ${RUNDIR}/${TRIAL}
  sync
  sleep 0.2
  if [ -d ${RUNDIR}/${TRIAL} ]; then
    echoit "Assert: tried to remove ${RUNDIR}/${TRIAL}, but it looks like removal failed. Check what is holding lock? (lsof tool may help)."
    echoit "As this is not necessarily a fatal error (there is likely enough space on ${RUNDIR} to continue working), pquery-run.sh will NOT terminate."
    echoit "However, this looks like a shortcoming in pquery-run.sh (likely in the mysqld/mariadbd termination code) which needs debugging and fixing. Please do."
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
  # If there are *SAN bugs, delete any known ones from the top of the error log(s)
  if [ "${SAN_KNOWN_BUGS_DROPPED_FROM_ERROR_LOG_FLAG}" != "1" ]; then
    if grep --binary-files=text -qiE "=ERROR:|runtime error:|AddressSanitizer:|ThreadSanitizer:|LeakSanitizer:|MemorySanitizer:" ${RUNDIR}/${TRIAL}/log/*.err ${RUNDIR}/${TRIAL}/node*/node*.err 2>/dev/null; then
      SAN_KNOWN_BUGS_DROPPED_FROM_ERROR_LOG_FLAG=1
      echoit "Dropping any known *SAN bugs from the top of the error log for trial ${TRIAL}, if any"  # Note that reducer.sh matches this behavior when a TOP_SAN_ISSUES_REMOVED flag file is present for the trial, and drop_one_or_more_san_from_log.sh will create this flag when a pquery-run.sh based trial (like here) was found, and only writes this flag file if it has removed top level known issue(s)/bug(s)
      # We are already in ${RUNDIR}/${TRIAL} directory (ref above), so no need to change to it
      ${SCRIPT_PWD}/drop_one_or_more_san_from_log.sh  # Do not add any options to this script call as that will cause the top SAN issue to be deleted, irrespective of whetter an issue is known or not
    fi
  fi
  if [[ "${MDG}" -eq 1 ]]; then
    export GALERA_ERROR_LOGS=${RUNDIR}/${TRIAL}/node${j}/node${j}.err
    TEXT="$(${SCRIPT_PWD}/new_text_string.sh)" # Note this will auto-call san_text_string.sh or fallback_text_string.sh if required
    echo "${TEXT}" | grep -v '^[ \t]*$' > ${RUNDIR}/${TRIAL}/node${j}/MYBUG
    export GALERA_ERROR_LOGS=""
  else
    TEXT="$(${SCRIPT_PWD}/new_text_string.sh)"  # Note this will auto-call san_text_string.sh or fallback_text_string.sh if required
    echo "${TEXT}" | grep -v '^[ \t]*$' > ${RUNDIR}/${TRIAL}/MYBUG
  fi
  cd - >/dev/null || exit 1
  if [[ "${MDG}" -eq 1 ]]; then
    if grep -qi "No .* found" ${RUNDIR}/${TRIAL}/node${j}/MYBUG; then
      if [ ! -z "$(ls ${RUNDIR}/${TRIAL}/node${j}/*core* 2>/dev/null)" ]; then
        echoit "Assert: we found a coredump at $(ls ${RUNDIR}/${TRIAL}/node${j}/*core* 2>/dev/null), yet ${SCRIPT_PWD}/new_text_string.sh produced this output: ${TEXT}"
        exit 1
      fi
    fi
  else
    if grep -qi "No .* found" ${RUNDIR}/${TRIAL}/MYBUG; then
      if [ ! -z "$(ls ${RUNDIR}/${TRIAL}/*/*core* 2>/dev/null)" ]; then
        echoit "Assert: we found a coredump at $(ls ${RUNDIR}/${TRIAL}/*/*core* 2>/dev/null), yet ${SCRIPT_PWD}/new_text_string.sh produced this output: ${TEXT}"
        exit 1
      fi
    fi
  fi
  echoit "Bug found (as per new_text_string.sh): ${TEXT}"
  TRIAL_TO_SAVE=1
  if grep --binary-files=text -qiE "=ERROR:|runtime error:|AddressSanitizer:|ThreadSanitizer:|LeakSanitizer:|MemorySanitizer:" ${RUNDIR}/${TRIAL}/log/*.err ${RUNDIR}/${TRIAL}/node*/node*.err 2>/dev/null; then
    # As we are already post-'known SAN* bug filtering', and *SAN issues remain (as the grep shows), this trial needs to always be saved; it cannot be a known issue as all known issues are already removed by drop_one_or_more_san_from_log.sh
    # As such, ELIMINATE_KNOWN_BUGS filtering is also not required in this case, and should not be called  # TODO: ',and should not ...': Defensive or required?
    TRIAL_TO_SAVE=1  # Defensive, leave
    if [ "$(echo "${TEXT}" | grep --binary-files=text -o 'no core.*empty output' | grep --binary-files=text -o 'no core' | head -n1)" == "no core" ]; then
      echo "Debug Assert: a *SAN text string was found in the error log at ${RUNDIR}/${TRIAL}/log/*.err yet TEXT ('${TEXT}') contains 'no core.*empty output'. Possibly master vs slave issue. Feel free to improve code in this area."  # TODO
    fi
  else
    if [ "${ELIMINATE_KNOWN_BUGS}" == "1" -a -r ${SCRIPT_PWD}/known_bugs.strings ]; then # "1": String check hack to ensure backwards compatibility with older pquery-run.conf files
      IS_KNOWN_BUG=""
      FINDBUG="$(set +H; grep -Fi --binary-files=text "${TEXT}" ${SCRIPT_PWD}/known_bugs.strings 2>/dev/null | grep --binary-files=text -v '^[ \t]*#')"
      if [ ! -z "${FINDBUG}" ]; then
        IS_KNOWN_BUG=1
      fi
      HAS_ERROR_LOG_SCAN_ISSUE=""
      if [ -r ${RUNDIR}/${TRIAL}/ERROR_LOG_SCAN_ISSUE ] || [ ! -z "$(ls ${RUNDIR}/${TRIAL}/node*/ERROR_LOG_SCAN_ISSUE 2>/dev/null)" ]; then
        HAS_ERROR_LOG_SCAN_ISSUE=1
      fi
      if [ "${IS_KNOWN_BUG}" = "1" ] && [ "${HAS_ERROR_LOG_SCAN_ISSUE}" != "1" ]; then  # known/filtered bug seen, and no unfiltered error log bug present: delete
        echoit "This is an already known and logged, non-fixed bug: $(echo "${FINDBUG}" | tr -s ' ')"  # The known bug lists are column aligned, so the run of spaces is squeezed to keep the ticket on screen
        ALREADY_KNOWN=$[ ${ALREADY_KNOWN} + 1]
        # The share of all classified crashes that were already known. A high share means the run keeps
        # re-finding the same open bugs, so the known bug lists need pruning or the input needs changing
        DUP_TOTAL=$(( ALREADY_KNOWN + NEWBUGS ))
        DUP_SHARE=$(( ALREADY_KNOWN * 100 / DUP_TOTAL ))
        if [ ${DUP_TOTAL} -lt 10 ]; then DUP_STYLE=DIM  # Too few classified crashes for the share to carry a colour
        elif [ ${DUP_SHARE} -ge 90 ]; then DUP_STYLE=RED
        elif [ ${DUP_SHARE} -ge 75 ]; then DUP_STYLE=ORANGE
        else DUP_STYLE=DIMGREEN; fi
        echoit "Deleting trial as ELIMINATE_KNOWN_BUGS=1, bug was already logged and is still open (${ALREADY_KNOWN} known/${DUP_TOTAL} found = ${DUP_SHARE}% dups)" "${DUP_STYLE}"
        DUP_TOTAL=; DUP_SHARE=; DUP_STYLE=
        TRIAL_TO_SAVE=0
      elif [ "${IS_KNOWN_BUG}" = "1" ] && [ "${HAS_ERROR_LOG_SCAN_ISSUE}" = "1" ]; then  # known UniqueID, but an unfiltered error log bug was flagged: keep the trial so the error log bug gets reduced
        echoit "new_text_string.sh produced a KNOWN UniqueID, but ERROR_LOG_SCAN_ISSUE is present: keeping trial for the unfiltered error log bug"
      else
        NEWBUGS=$[ ${NEWBUGS} + 1 ]
        echoit "[${NEWBUGS}] *** NEW BUG *** (not found in ${SCRIPT_PWD}/known_bugs.strings, or found but marked as already fixed)"
      fi
      FINDBUG=
      IS_KNOWN_BUG=
      HAS_ERROR_LOG_SCAN_ISSUE=
    fi
  fi
}

if [[ "${MDG}" -eq 1 ]]; then
  # Creating default my.cnf file
  SUSER=root
  SPASS=
  rm -rf ${BASEDIR}/my.cnf
  echo "[mysqld]" > ${BASEDIR}/my.cnf
  echo "basedir=${BASEDIR}" >> ${BASEDIR}/my.cnf
  echo "innodb_file_per_table" >> ${BASEDIR}/my.cnf
  echo "innodb_autoinc_lock_mode=2" >> ${BASEDIR}/my.cnf
  echo "wsrep-provider=${BASEDIR}/lib/libgalera_smm.so" >> ${BASEDIR}/my.cnf
  if [ "${MDG_SST_METHOD}" -eq 1 ] ; then
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
    if [ -z "${1}" ]; then
      echo 'Assert: $1 was empty on call of mdg_startup_chk()'
      exit 1
    fi
    ERROR_LOG=$1
    if grep -qi "Can.t create.write to file" ${ERROR_LOG}; then
      echoit "Assert! Likely an incorrect --init-file option was specified (check if the specified file actually exists)"  # Also see https://jira.mariadb.org/browse/MDEV-27232
      echoit "Terminating run as there is no point in continuing; all trials will fail with this error."
      removetrial
      exit 1
    elif grep -qi "ERROR. Aborting" ${ERROR_LOG}; then
      if grep -qi "TCP.IP port.*Address already in use" ${ERROR_LOG}; then
        echoit "Assert! The text '[ERROR] Aborting' was found in the error log due to a IP port conflict (the port was already in use)"
        removetrial
      else
        if [ "${MDG_ADD_RANDOM_OPTIONS}" -eq 0 ]; then # Halt for MDG_ADD_RANDOM_OPTIONS=0 runs which have 'ERROR. Aborting' in the error log, as they should not produce errors like these, given that the MDG_MYEXTRA and WSREP_PROVIDER_OPT lists are/should be high-quality/non-faulty
          echoit "Assert! '[ERROR] Aborting' was found in the error log. This is likely an issue with one of the \$MDG_MYEXTRA (${MDG_MYEXTRA}) startup or \$WSREP_PROVIDER_OPT ($WSREP_PROVIDER_OPT) configuration options. Saving trial for further analysis, and dumping error log here for quick analysis. Please check the output against these variables settings. The respective files for these options (${MDG_WSREP_OPTIONS_INFILE} and ${MDG_WSREP_PROVIDER_OPTIONS_INFILE}) may require editing."
          grep "ERROR" -B5 -A3 ${ERROR_LOG} | tee -a /${WORKDIR}/pquery-run.log
          if [ "${MDG_IGNORE_ALL_OPTION_ISSUES}" -eq 1 ]; then
            echoit "MDG_IGNORE_ALL_OPTION_ISSUES=1, so irrespective of the assert given, pquery-run.sh will continue running. Please check your option files!"
          else
            if grep -qiE "error 28|out of disk space" ${ERROR_LOG}; then  # Likely OOS on /dev/shm
              echoit "Noticed a likely OOS on ${RUNDIR} or in /tmp or root (/). Removing trial to maximize space, and pausing 0.5 hour before trying again (reducer's may be running and consuming space)"
              removetrial
              sleep 1800
              echoit "Slept 0.5h, resuming pquery-run.sh run..."
            else
              savetrial
              echoit "Remember to cleanup/delete the rundir:  rm -Rf ${RUNDIR}"
              if [ "${MARIADB_BINLOG_RECOVERY_TESTING}" -ne 1 ]; then
                exit 1  # Ref [*A] above
              fi
            fi
          fi
        else # Do not halt for MDG_ADD_RANDOM_OPTIONS=1 runs, they are likely to produce errors like these as MDG_MYEXTRA was randomly changed
          echoit "'[ERROR] Aborting' was found in the error log. This is likely an issue with one of the \$MDG_MYEXTRA (${MDG_MYEXTRA}) startup options. As \$MDG_ADD_RANDOM_OPTIONS=1, this is likely to be encountered given the random addition of mysqld/mariadbd options. Not saving trial. If you see this error for every trial however, set \$MDG_ADD_RANDOM_OPTIONS=0 & try running pquery-run.sh again. If it still fails, it is likely that your base \$MYEXTRA (${MYEXTRA}) or \$ENCRYPTION_OPTIONS (${ENCRYPTION_OPTIONS}) setting is faulty."
          grep "ERROR" -B5 -A3 ${ERROR_LOG} 2>/dev/null | tee -a /${WORKDIR}/pquery-run.log  # 2>/dev/null: do not report error when the above "Noticed a likely OOS on ... Slept 0.5h" took place
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
      if [[ "${X}" -eq "$((MDG_START_TIMEOUT - 1))" ]]; then
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
        $VALGRIND_CMD ${BIN} --defaults-file=${DATADIR}/n${j}.cnf $STARTUP_OPTION $MYEXTRA_KEYRING $MYEXTRA $MDG_MYEXTRA --wsrep-new-cluster > ${ERR_FILE} 2>&1 &
      else
        if [ "$IS_STARTUP" == "startup" ]; then
          ${BIN} --defaults-file=${DATADIR}/n${j}.cnf $STARTUP_OPTION $MYEXTRA_KEYRING $MYEXTRA $MDG_MYEXTRA --wsrep-new-cluster > ${ERR_FILE} 2>&1 &
        else
          export _RR_TRACE_DIR="${RUNDIR}/${TRIAL}/rr"
          mkdir -p "${_RR_TRACE_DIR}"
          sudo chmod -R 777 "${_RR_TRACE_DIR}"
          /usr/bin/rr record --chaos ${BIN} --defaults-file=${DATADIR}/n${j}.cnf $STARTUP_OPTION $MYEXTRA_KEYRING $MYEXTRA $MDG_MYEXTRA --wsrep-new-cluster > ${ERR_FILE} 2>&1 &
        fi
      fi
      mdg_startup_status ${j}
    else
      get_error_socket_file ${j}
      $VALGRIND_CMD ${BIN} --defaults-file=${DATADIR}/n${j}.cnf \
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
        echo "$VALGRIND_CMD ${BIN} --defaults-file=${WORKDIR}/${TRIAL}/n${j}.cnf $STARTUP_OPTION $MYEXTRA_KEYRING $MYEXTRA $MDG_MYEXTRA  --wsrep-new-cluster > ${RUNDIR}/${TRIAL}/node${j}/node${j}.err 2>&1 &" >> ${RUNDIR}/${TRIAL}/start_mdg_recovery
        echo "startup_check $node/node${j}_socket.sock" >> ${RUNDIR}/${TRIAL}/start_mdg_recovery
      fi
      echo "$VALGRIND_CMD ${BIN} --defaults-file=${WORKDIR}/${TRIAL}/n${j}.cnf $STARTUP_OPTION $MYEXTRA_KEYRING $MYEXTRA $MDG_MYEXTRA > ${RUNDIR}/${TRIAL}/node${j}/node${j}.err  2>&1 &" >> ${RUNDIR}/${TRIAL}/start_mdg_recovery
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
  RPORT=$(${RANDOM_BIN} 10 30)
  RBASE="$((RPORT * 1000))"
  RBASE1="$((RBASE + 1))"
  RBASE2="$((RBASE + 2))"
  RBASE3="$((RBASE + 3))"
  LADDR1="$ADDR:$((RBASE + 101))"
  LADDR2="$ADDR:$((RBASE + 102))"
  LADDR3="$ADDR:$((RBASE + 103))"

  SUSER=root
  SPASS=

  MID="${BIN} --no-defaults --initialize-insecure --basedir=${BASEDIR}"
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
    if [ -z "${1}" ]; then
      echo 'Assert: $1 was empty on call of gr_startup_chk()'
      exit 1
    fi
    ERROR_LOG=$1
    if grep -qi "Can.t create.write to file" ${ERROR_LOG}; then
      echoit "Assert! Likely an incorrect --init-file option was specified (check if the specified file actually exists)"  # Also see https://jira.mariadb.org/browse/MDEV-27232
      echoit "Terminating run as there is no point in continuing; all trials will fail with this error."
      removetrial
      exit 1
    elif grep -qi "ERROR. Aborting" ${ERROR_LOG}; then
      if grep -qi "TCP.IP port.*Address already in use" ${ERROR_LOG}; then
        echoit "Assert! The text '[ERROR] Aborting' was found in the error log due to a IP port conflict (the port was already in use)"
        removetrial
      else
        echoit "Assert! '[ERROR] Aborting' was found in the error log. This is likely an issue with one of the \$MYEXTRA (${MYEXTRA}) startup options. Saving trial for further analysis, and dumping error log here for quick analysis. Please check the output against these variables settings."
        grep "ERROR" -B5 -A3 ${ERROR_LOG} | tee -a /${WORKDIR}/pquery-run.log
        if grep -qiE "error 28|out of disk space" ${ERROR_LOG}; then  # Likely OOS on /dev/shm
          echoit "Noticed a likely OOS on ${RUNDIR} or in /tmp or root (/). Removing trial to maximize space, and pausing 0.5 hour before trying again (reducer's may be running and consuming space)"
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

  ${BIN} --no-defaults \
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

  ${BIN} --no-defaults \
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

  ${BIN} --no-defaults \
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

pquery_test(){
  TRIAL_SAVED=0
  TRIAL=$((${TRIAL} + 1))
  # Reset PIDs of any child processes this trial may (re-)launch. Without this,
  # a previous trial's PQPID/PQPID2/MPID/SLAVE_MPID/MPID2 could be re-targeted
  # by this trial's kill / kill -0 / SIGTERM logic if the kernel happens to
  # reassign that PID to an unrelated process between trials. Each launch
  # site below overwrites these via `=$!`; only paths that skip a launch (e.g.
  # server-start failure for the secondary engine) would otherwise inherit a
  # stale PID from the prior trial.
  PQPID= PQPID2= MPID= SLAVE_MPID= MPID2=
  SOCKET=${RUNDIR}/${TRIAL}/socket.sock
  SAN_KNOWN_BUGS_DROPPED_FROM_ERROR_LOG_FLAG=0
  echoit "====== TRIAL #${TRIAL} ======"
  echoit "Ensuring there are no relevant servers running..."
  KILLPID=$(ps -ef | grep "${RUNDIR}" | grep -v grep | awk '{print $2}' | tr '\n' ' ')
  (
    sleep 0.2
    kill -9 $KILLPID > /dev/null 2>&1
    for P in $KILLPID; do
      for X in $(seq 1 4); do kill -0 ${P} 2>/dev/null || break; sleep 1; done  # bounded kill-confirm; replaces dead `timeout … wait` (see end-of-script poll comment)
    done
  ) &
  # Foonly idiom: bare `wait $PID` in the main shell starts blocking BEFORE the
  # backgrounded subshell's `sleep 0.2` + kill -9 fires. When the PID dies, our
  # wait consumes the exit status, so bash's deferred SIGCHLD handler has
  # nothing left to report - suppressing the otherwise-annoying 'Killed' line.
  # 2>/dev/null swallows the rare "not a child of this shell" message that
  # bash prints if a captured PID was inherited from a defunct previous trial.
  # A short kill -0 fallback poll handles those non-child PIDs (wait returns
  # 127 immediately for them so the budget is otherwise unspent).
  # Thank you to user 'Foonly' @ forums.whirlpool.net.au
  for P in $KILLPID; do wait ${P} 2>/dev/null; done
  for P in $KILLPID; do
    for X in $(seq 1 5); do kill -0 ${P} 2>/dev/null || break; sleep 1; done
  done
  echoit "Clearing rundir..."
  rm -Rf ${RUNDIR}/[0-9A-Za-ln-z]* # m* is avoided to leave ./mysqld or ./mariadbd in place
  if [ ${USE_GENERATOR} -eq 1 ]; then
    SAVEDIR=${PWD}
    cd ${SCRIPT_PWD}/generatorcpp/ || exit 1
    echoit "Generating new SQL inputfile using the SQL Generator..."
    if [ "${RANDOMD}" == "" ]; then
      echoit "Assert: RANDOMD is empty. This should not happen. Terminating."
      exit 1
    fi
    # Retry up to 5 times with a 10s pause to ride out a concurrent rebuild
    # of generatorcpp/generator. build.sh writes to generator.tmp and atomically
    # renames into place, but the window between rm-old-tmp and rename can
    # still trip a -x check if a rebuild started just before us.
    for GEN_TRY in 1 2 3 4 5; do
      if [ -x ./generator ]; then break; fi
      echoit "Note: ${SCRIPT_PWD}/generatorcpp/generator is missing or not executable (attempt ${GEN_TRY}/5); pausing 10s and retrying..."
      sleep 10
    done
    if [ ! -x ./generator ]; then
      echoit "Assert: ${SCRIPT_PWD}/generatorcpp/generator is missing or not executable after 5 retries. Run generatorcpp/build.sh first."
      exit 1
    fi
    for GEN_RUN_TRY in 1 2 3; do
      ./generator --threads ${GENERATION_THREADS} ${GENERATORCPP_OPTIONS:-} --output out${RANDOMD}.sql ${QUERIES_PER_GENERATOR_RUN} > /dev/null
      if [ -r out${RANDOMD}.sql ]; then break; fi
      echoit "Note: out${RANDOMD}.sql not present in ${PWD} after generator execution (attempt ${GEN_RUN_TRY}/3); pausing 30s and retrying..."
      sleep 30
    done
    if [ ! -r out${RANDOMD}.sql ]; then
      echoit "Assert: out${RANDOMD}.sql not present in ${PWD} after generator execution (3 retries)"
      exit 1
    fi
    if [[ "${MYEXTRA^^}" != *"ROCKSDB"* ]]; then # If this is not a RocksDB run, exclude RocksDB SE
      sed -i "s|RocksDB|InnoDB|" out${RANDOMD}.sql
    fi
    if [[ "${MYEXTRA^^}" != *"HA_TOKUDB"* ]]; then # If this is not a TokuDB enabled run, exclude TokuDB SE
      sed -i "s|TokuDB|InnoDB|" out${RANDOMD}.sql
    fi
    GEN_OUTFILE=${PWD}/out${RANDOMD}.sql
    cd ${SAVEDIR} || exit 1
  fi
  if [ ${USE_REVGEN} -eq 1 ]; then
    SAVEDIR=${PWD}
    cd ${SCRIPT_PWD}/revgen/ || exit 1
    echoit "Generating new SQL inputfile using revgen (reverse grammar generator)..."
    if [ "${RANDOMD}" == "" ]; then
      echoit "Assert: RANDOMD is empty. This should not happen. Terminating."
      exit 1
    fi
    for REV_TRY in 1 2 3 4 5; do
      if [ -x ./revgen ]; then break; fi
      echoit "Note: ${SCRIPT_PWD}/revgen/revgen is missing or not executable (attempt ${REV_TRY}/5); pausing 10s and retrying..."
      sleep 10
    done
    if [ ! -x ./revgen ]; then
      echoit "Assert: ${SCRIPT_PWD}/revgen/revgen is missing or not executable after 5 retries. Run revgen/build.sh first."
      exit 1
    fi
    # With REVGEN_VALIDATE_SOCKET pointed at a running server, revgen PREPARE-tests
    # each statement and drops the ones the server cannot parse. It has to be a
    # server of its own: the trial's server does not exist yet at this point, and
    # PREPARE of generated SQL reaches crashing code paths, so this must not be a
    # server whose death matters. Skipped silently when the socket is absent.
    REV_VALIDATE=
    if [ -n "${REVGEN_VALIDATE_SOCKET}" ] && [ -S "${REVGEN_VALIDATE_SOCKET}" ]; then
      REV_VALIDATE="--validate-sql --socket ${REVGEN_VALIDATE_SOCKET}"
    fi
    for REV_RUN_TRY in 1 2 3 4 5; do
      ./revgen --threads ${GENERATION_THREADS} --yacc "${REVGEN_YACC}" ${REVGEN_OPTIONS:-} ${REV_VALIDATE} --output outrev${RANDOMD}.sql --queries ${QUERIES_PER_REVGEN_RUN} > /dev/null
      if [ -r outrev${RANDOMD}.sql ] && [ $(wc -l < outrev${RANDOMD}.sql) -ge 10 ]; then break; fi
      echoit "Note: outrev${RANDOMD}.sql not present in ${PWD}, or it has fewer than 10 lines, after revgen execution (attempt ${REV_RUN_TRY}/5); pausing 10s and retrying..."
      sleep 10
    done
    if [ ! -r outrev${RANDOMD}.sql ] || [ $(wc -l < outrev${RANDOMD}.sql) -lt 10 ]; then
      echoit "Assert: outrev${RANDOMD}.sql not present in ${PWD}, or it has fewer than 10 lines, after revgen execution (5 attempts)"
      exit 1
    fi
    if [[ "${MYEXTRA^^}" != *"ROCKSDB"* ]]; then # If this is not a RocksDB run, exclude RocksDB SE
      sed -i "s|RocksDB|InnoDB|" outrev${RANDOMD}.sql
    fi
    if [[ "${MYEXTRA^^}" != *"HA_TOKUDB"* ]]; then # If this is not a TokuDB enabled run, exclude TokuDB SE
      sed -i "s|TokuDB|InnoDB|" outrev${RANDOMD}.sql
    fi
    REVGEN_OUTFILE=${PWD}/outrev${RANDOMD}.sql
    cd ${SAVEDIR} || exit 1
  fi
  assemble_trial_sql  # Builds TRIAL_SQL from every active source, before the server for this trial exists
  echoit "Generating new trial workdir ${RUNDIR}/${TRIAL}..."
  ISSTARTED=0
  diskspace
  if [[ "${MDG}" -eq 0 && "${GRP_RPL}" -eq 0 ]]; then  # Standard non-Galera/non-Group-Replication run
    if check_for_version $MYSQL_VERSION "8.0.0"; then
      mkdir -p ${RUNDIR}/${TRIAL}/data ${RUNDIR}/${TRIAL}/tmp ${RUNDIR}/${TRIAL}/log # Cannot create /data/test, /data/mysql in 8.0
    else
      mkdir -p ${RUNDIR}/${TRIAL}/data/test ${RUNDIR}/${TRIAL}/data/mysql ${RUNDIR}/${TRIAL}/tmp ${RUNDIR}/${TRIAL}/log
    fi
    echo 'SELECT 1;' > ${RUNDIR}/${TRIAL}/startup_failure_thread-0.sql  # Add fake file enabling pquery-prep-red.sh/reducer.sh to be used with/for mysqld/mariadbd startup issues
    diskspace
    # Setup encryption files for use with file_key_management if ENABLE_ENCRYPTION is enabled
    ENCRYPTION_OPTIONS=''
    if [[ "${ENABLE_ENCRYPTION}" -eq 1 ]]; then
      # Generate a 256-bit (32-byte) key for use with file_key_management_filekey
      echo "$(echo -n '1;' ; openssl rand -hex 32)" > ${RUNDIR}/${TRIAL}/key.key
      # Generate an plain-text hex password to encrypt the key.key file with
      openssl rand -hex 128 > ${RUNDIR}/${TRIAL}/key.pass
      if check_for_version $MYSQL_VERSION "12.0.1"; then  # https://jira.mariadb.org/browse/MDEV-34712 SHA2 support was implemented in 12.0.1
        # Encrypt the file_key key.key with the password provided in key.pass using SHA2/pbkdf2/iter-11k
        openssl enc -aes-256-cbc -md sha256 -pbkdf2 -iter 11000 -pass file:${RUNDIR}/${TRIAL}/key.pass -in ${RUNDIR}/${TRIAL}/key.key -out ${RUNDIR}/${TRIAL}/key.enc  
        # Set matching mariadbd options, adding MYENCRYPTION as configured in .conf file (the actual to-be-encrypted items)
        ENCRYPTION_OPTIONS="--plugin_load_add=file_key_management --file-key-management=FORCE_PLUS_PERMANENT --file-key-management-filekey=FILE:${RUNDIR}/${TRIAL}/key.pass --file-key-management-filename=${RUNDIR}/${TRIAL}/key.enc --file-key-management-encryption-algorithm=AES_CBC --file_key_management_use_pbkdf2=11000 --file_key_management_digest=sha256 ${MYENCRYPTION}"
      else
        # Encrypt the file_key key.key with the password provided in key.pass using SHA1
        # In-run "*** WARNING : deprecated key derivation used. Using -iter or -pbkdf2 would be better." warnings are normal and apparently cannot be supressed
        openssl enc -aes-256-cbc -md sha1 -pass file:${RUNDIR}/${TRIAL}/key.pass -in ${RUNDIR}/${TRIAL}/key.key -out ${RUNDIR}/${TRIAL}/key.enc >/dev/null 2>&1
        # Set matching mariadbd options, adding MYENCRYPTION as configured in .conf file (the actual to-be-encrypted items)
        ENCRYPTION_OPTIONS="--plugin_load_add=file_key_management --file-key-management=FORCE_PLUS_PERMANENT --file-key-management-filekey=FILE:${RUNDIR}/${TRIAL}/key.pass --file-key-management-filename=${RUNDIR}/${TRIAL}/key.enc --file-key-management-encryption-algorithm=AES_CBC ${MYENCRYPTION}"
      fi
      # Remove the unencrypted key: customarily done, though we can leave it for testing review purposes
      #rm -f ${RUNDIR}/${TRIAL}/key.key
    fi
    if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 ]; then
      echoit "Copying datadir from template for Primary mysqld/mariadbd..."
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
      while [ "${EXIT_CODE_CP}" -ne 0 ]; do  # Loop till no error is observed (caters for OOS issues)
        cp -R ${WORKDIR}/$((${TRIAL} - 1))/data/* ${RUNDIR}/${TRIAL}/data 2>&1
        EXIT_CODE_CP=$?
        if [ "${EXIT_CODE_CP}" -ne 0 ]; then diskspace; sleep 10; fi
      done
    else
      EXIT_CODE_CP=1
      while [ "${EXIT_CODE_CP}" -ne 0 ]; do  # Loop till no error is observed (caters for OOS issues)
        cp -R ${WORKDIR}/data.template/* ${RUNDIR}/${TRIAL}/data 2>&1
        EXIT_CODE_CP=$?
        if [ "${EXIT_CODE_CP}" -ne 0 ]; then diskspace; sleep 10; fi
      done
    fi
    if [[ ${REPLICATION} -eq 1 ]]; then
      mkdir -p ${RUNDIR}/${TRIAL}/tmp_slave
      cp -r ${RUNDIR}/${TRIAL}/data ${RUNDIR}/${TRIAL}/data_slave
      SLAVE_SOCKET=${RUNDIR}/${TRIAL}/slave_socket.sock
    fi
    MYEXTRA_SAVE_IT=${MYEXTRA}
    if [ ${ADD_RANDOM_OPTIONS} -eq 1 ]; then # Add random mysqld/mariadbd --options to MYEXTRA
      OPTIONS_TO_ADD=
      NR_OF_OPTIONS_TO_ADD=$(${RANDOM_BIN} 1 ${MAX_NR_OF_RND_OPTS_TO_ADD})
      for X in $(seq 1 ${NR_OF_OPTIONS_TO_ADD}); do
        OPTION_TO_ADD="$(shuf --random-source=<(${RANDOM_BIN} --raw) ${OPTIONS_INFILE} | head -n1)"
        if [ "$(echo ${OPTION_TO_ADD} | sed 's| ||g;s|.*query.alloc.block.size=1125899906842624.*||')" != "" ]; then # http://bugs.mysql.com/bug.php?id=78238
          OPTIONS_TO_ADD="${OPTIONS_TO_ADD} ${OPTION_TO_ADD}"
        fi
      done
      echoit "ADD_RANDOM_OPTIONS=1: adding mysqld/mariadbd option(s) ${OPTIONS_TO_ADD} to this run's MYEXTRA..."
      MYEXTRA="${MYEXTRA} ${OPTIONS_TO_ADD}"
      if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 ]; then
        MYEXTRA2="${MYEXTRA2} ${OPTIONS_TO_ADD}"
      fi
    fi
    if [ ${ADD_RANDOM_TOKUDB_OPTIONS} -eq 1 ]; then # Add random tokudb --options to MYEXTRA
      OPTIONS_TO_ADD=
      NR_OF_OPTIONS_TO_ADD=$(${RANDOM_BIN} 1 ${MAX_NR_OF_RND_OPTS_TO_ADD})
      for X in $(seq 1 ${NR_OF_OPTIONS_TO_ADD}); do
        OPTION_TO_ADD=
        OPTION_TO_ADD="$(shuf --random-source=<(${RANDOM_BIN} --raw) ${TOKUDB_OPTIONS_INFILE} | head -n1)"
        OPTIONS_TO_ADD="${OPTIONS_TO_ADD} ${OPTION_TO_ADD}"
      done
      echoit "ADD_RANDOM_TOKUDB_OPTIONS=1: adding TokuDB mysqld/mariadbd option(s) ${OPTIONS_TO_ADD} to this run's MYEXTRA..."
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
      NR_OF_OPTIONS_TO_ADD=$(${RANDOM_BIN} 1 ${MAX_NR_OF_RND_OPTS_TO_ADD})
      for X in $(seq 1 ${NR_OF_OPTIONS_TO_ADD}); do
        OPTION_TO_ADD="$(shuf --random-source=<(${RANDOM_BIN} --raw) ${ROCKSDB_OPTIONS_INFILE} | head -n1)"
        OPTIONS_TO_ADD="${OPTIONS_TO_ADD} ${OPTION_TO_ADD}"
      done
      echoit "ADD_RANDOM_ROCKSDB_OPTIONS=1: adding RocksDB mysqld/mariadbd option(s) ${OPTIONS_TO_ADD} to this run's MYEXTRA..."
      MYEXTRA="${MYEXTRA} ${OPTIONS_TO_ADD}"
      if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 ]; then
        MYEXTRA2="${MYEXTRA2} ${OPTIONS_TO_ADD}"
      fi
    fi
    echo "${MYEXTRA}" | if grep -qi "innodb[_-]log[_-]checksum[_-]algorithm"; then
      # Ensure that mysqld/mariadbd server startup will not fail due to a mismatched checksum algo between the original MID and the changed MYEXTRA options
      rm ${RUNDIR}/${TRIAL}/data/ib_log*
    fi
    init_empty_port
    PORT=${NEWPORT}
    NEWPORT=
    if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 ]; then
      echoit "Starting Primary mysqld/mariadbd. Error log: ${RUNDIR}/${TRIAL}/log/master.err"
    else
      if [[ ${REPLICATION} -eq 1 ]]; then
        echoit "Starting master mysqld/mariadbd. Error log: ${RUNDIR}/${TRIAL}/log/master.err"
      else
        echoit "Starting mysqld/mariadbd. Error log: ${RUNDIR}/${TRIAL}/log/master.err"
      fi
    fi
    if [ "${RR_TRACING}" == "0" ]; then
      if [ "${VALGRIND_RUN}" == "0" ]; then  ## Standard run
        if [ "${ROTATE_BINLOG_FORMAT}" == "1" ]; then  # Rotate binlog format if set to do so
          MASTER_EXTRA=$(echo "${MASTER_EXTRA}" | sed -e '/format=ROW/{s|format=ROW|format=STATEMENT|;t end}' \
                                                      -e '/format=STATEMENT/{s|format=STATEMENT|format=MIXED|;t end}' \
                                                      -e '/format=MIXED/{s|format=MIXED|format=ROW|}' \
                                                      -e ':end')
        fi
        CMD="${BIN} ${MYSAFE} ${MYEXTRA} ${ENCRYPTION_OPTIONS} ${REPL_EXTRA} ${MASTER_EXTRA} --basedir=${BASEDIR} --datadir=${RUNDIR}/${TRIAL}/data --tmpdir=${RUNDIR}/${TRIAL}/tmp --core-file --port=$PORT --pid_file=${RUNDIR}/${TRIAL}/pid.pid --socket=${SOCKET} --log-output=none --log-error=${RUNDIR}/${TRIAL}/log/master.err"
      else  ## Valgrind run
        CMD="${VALGRIND_CMD} ${BIN} ${MYSAFE} ${MYEXTRA} ${ENCRYPTION_OPTIONS} ${REPL_EXTRA} ${MASTER_EXTRA} --basedir=${BASEDIR} --datadir=${RUNDIR}/${TRIAL}/data --tmpdir=${RUNDIR}/${TRIAL}/tmp --core-file --port=$PORT --pid_file=${RUNDIR}/${TRIAL}/pid.pid --socket=${SOCKET} --log-output=none --log-error=${RUNDIR}/${TRIAL}/log/master.err"
      fi
    else  ## rr tracing run  # TODO: add slave startup in something like rr_slave if replication is used (below)
      export _RR_TRACE_DIR="${RUNDIR}/${TRIAL}/rr"
      mkdir -p "${_RR_TRACE_DIR}"
      sudo chmod -R 777 "${_RR_TRACE_DIR}"
      CMD="/usr/bin/rr record --chaos ${BIN} ${MYSAFE} ${MYEXTRA} ${ENCRYPTION_OPTIONS} ${REPL_EXTRA} ${MASTER_EXTRA} --basedir=${BASEDIR} --datadir=${RUNDIR}/${TRIAL}/data --tmpdir=${RUNDIR}/${TRIAL}/tmp --core-file --loose-innodb-flush-method=fsync --port=$PORT --pid_file=${RUNDIR}/${TRIAL}/pid.pid --socket=${SOCKET} --log-output=none --log-error=${RUNDIR}/${TRIAL}/log/master.err"
    fi
    if [ -r "${HOME}/stack" ]; then
      ln -sf ${HOME}/stack ${RUNDIR}/${TRIAL}/stack  # Handy ./stack shorthand (automatically copied later to WORKDIR if trial is saved). -f handles pre-existing broken/stale symlinks (trial-dir reuse, savetrial path race).
    fi
    diskspace
    $CMD >> ${RUNDIR}/${TRIAL}/log/master.err 2>&1 &
    MPID="$!"
    if [[ ${REPLICATION} -eq 1 ]]; then
      echoit "Starting slave mysqld/mariadbd. Error log: ${RUNDIR}/${TRIAL}/log/slave.err"
      init_empty_port
      touch ${RUNDIR}/${TRIAL}/REPLICATION_ACTIVE
      REPL_PORT=${NEWPORT}
      NEWPORT=
      if [ "${VALGRIND_RUN}" == "0" ]; then  ## Standard run
        SLAVE_STARTUP="${BIN} ${MYSAFE} ${MYEXTRA} ${ENCRYPTION_OPTIONS} ${REPL_EXTRA} ${SLAVE_EXTRA} --basedir=${BASEDIR} --datadir=${RUNDIR}/${TRIAL}/data_slave --tmpdir=${RUNDIR}/${TRIAL}/tmp_slave --core-file --port=$REPL_PORT --pid_file=${RUNDIR}/${TRIAL}/slave_pid.pid --server_id=101 --socket=${SLAVE_SOCKET} --log-output=none --log-error=${RUNDIR}/${TRIAL}/log/slave.err"
      else  ## Valgrind run
        SLAVE_STARTUP="${VALGRIND_CMD} ${BIN} ${MYSAFE} ${MYEXTRA} ${ENCRYPTION_OPTIONS} ${REPL_EXTRA} ${SLAVE_EXTRA} --basedir=${BASEDIR} --datadir=${RUNDIR}/${TRIAL}/data_slave --tmpdir=${RUNDIR}/${TRIAL}/tmp_slave --core-file --port=$REPL_PORT --pid_file=${RUNDIR}/${TRIAL}/slave_pid.pid --server_id=101 --socket=${SLAVE_SOCKET} --log-output=none --log-error=${RUNDIR}/${TRIAL}/log/slave.err"
      fi
      $SLAVE_STARTUP >> ${RUNDIR}/${TRIAL}/log/slave.err 2>&1 &
      SLAVE_MPID="$!"
      SLAVE_STARTUP=
    fi
    if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 ]; then
      echoit "Starting Secondary mysqld/mariadbd. Error log: ${RUNDIR}/${TRIAL}/log2/master.err"
      diskspace
      if check_for_version $MYSQL_VERSION "8.0.0"; then
        mkdir -p ${RUNDIR}/${TRIAL}/data2 ${RUNDIR}/${TRIAL}/tmp2 ${RUNDIR}/${TRIAL}/log2 # Cannot create /data/test, /data/mysql in 8.0
      else
        mkdir -p ${RUNDIR}/${TRIAL}/data2/test ${RUNDIR}/${TRIAL}/data2/mysql ${RUNDIR}/${TRIAL}/tmp2 ${RUNDIR}/${TRIAL}/log2
      fi
      echoit "Copying datadir from template for Secondary mysqld/mariadbd..."
      cp -R ${WORKDIR}/data.template/* ${RUNDIR}/${TRIAL}/data2 2>&1
      PORT2=$(($PORT + 1))
      if [ "${VALGRIND_RUN}" == "0" ]; then
        CMD2="${BIN} ${MYSAFE} ${MYEXTRA2} --basedir=${BASEDIR} --datadir=${RUNDIR}/${TRIAL}/data2 --tmpdir=${RUNDIR}/${TRIAL}/tmp2 --core-file --port=$PORT2 --pid_file=${RUNDIR}/${TRIAL}/pid2.pid --socket=${RUNDIR}/${TRIAL}/socket2.sock --log-output=none --log-error=${RUNDIR}/${TRIAL}/log2/master.err"
      else
        CMD2="${VALGRIND_CMD} ${BIN} ${MYSAFE} ${MYEXTRA2} --basedir=${BASEDIR} --datadir=${RUNDIR}/${TRIAL}/data2 --tmpdir=${RUNDIR}/${TRIAL}/tmp2 --core-file --port=$PORT2 --pid_file=${RUNDIR}/${TRIAL}/pid2.pid --socket=${RUNDIR}/${TRIAL}/socket2.sock --log-output=none --log-error=${RUNDIR}/${TRIAL}/log2/master.err"
      fi
      diskspace
      $CMD2 >> ${RUNDIR}/${TRIAL}/log2/master.err 2>&1 &
      MPID2="$!"
      sleep 1
    fi
    diskspace
    echo "This script recreates the /dev/shm dirs for the trial and copies the current (crashed/ended state) data state to it." > ${RUNDIR}/${TRIAL}/start_dev_shm
    echo "This script can be considered safe to run as many times as needed, but remember to kill the running mysqld/mariadbd each time." >> ${RUNDIR}/${TRIAL}/start_dev_shm
    echo "echo '=== Setting up directories...'" >> ${RUNDIR}/${TRIAL}/start_dev_shm
    echo "rm -Rf ${RUNDIR}/${TRIAL}" >> ${RUNDIR}/${TRIAL}/start_dev_shm
    echo "mkdir -p ${RUNDIR}/${TRIAL}/data ${RUNDIR}/${TRIAL}/tmp ${RUNDIR}/${TRIAL}/log" >> ${RUNDIR}/${TRIAL}/start_dev_shm
    echo "cp -R ./data/* ${RUNDIR}/${TRIAL}/data  # Copy the servers current (crashed/ended state) data directory" >> ${RUNDIR}/${TRIAL}/start_dev_shm
    echo "#echo '=== Data dir init (only use when doing option startup testing)...'" >> ${RUNDIR}/${TRIAL}/start_dev_shm
    echo "#${BIN} --no-defaults --initialize-insecure --basedir=${BASEDIR} --datadir=${RUNDIR}/${TRIAL}/data --tmpdir=${RUNDIR}/${TRIAL}/tmp --core-file --port=$PORT --pid_file=${RUNDIR}/${TRIAL}/pid.pid --socket=${SOCKET} --log-output=none --log-error=${RUNDIR}/${TRIAL}/log/master.err" | sed 's|[ \t]\+| |g' >> ${RUNDIR}/${TRIAL}/start_dev_shm
    echo "echo '=== Starting mysqld/mariadbd...'" >> ${RUNDIR}/${TRIAL}/start_dev_shm
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
    MDCLB="$(echo "${BIN}" | sed 's|/mysqld|/mariadb|;s|/mariadbd|/mariadb|')"  # Second sed: as BIN may have already been mariadbd
    if [ -r "${MDCLB}" ]; then CLBIN="${MDCLB}"; else MDCLB=; fi  # mariadb client
    echo "${CLBIN} -A --force --socket=${SOCKET} -uroot --binary-mode test" > ${RUNDIR}/${TRIAL}/cl_dev_shm
    chmod +x ${RUNDIR}/${TRIAL}/cl_dev_shm
    cat ${RUNDIR}/${TRIAL}/cl_dev_shm | sed 's|/dev/shm|/data|' > ${RUNDIR}/${TRIAL}/cl
    chmod +x ${RUNDIR}/${TRIAL}/cl
    if [ ! -z "${MDCLB}" ]; then CLBIN="${CLBIN}-"; fi  # mariadb-admin
    echo "${CLBIN}admin --socket=$(echo "${SOCKET}" | sed "s|/dev/shm|/data|") -uroot shutdown" > ${RUNDIR}/${TRIAL}/stop
    echo "${CLBIN}admin --socket=${SOCKET} -uroot shutdown" > ${RUNDIR}/${TRIAL}/stop_dev_shm
    chmod +x ${RUNDIR}/${TRIAL}/stop ${RUNDIR}/${TRIAL}/stop_dev_shm
    echo "grep -o 'port=[0-9]\\+' start | sed 's|port=||' | xargs -I{} echo \"ps -ef | grep '{}'\" | xargs -I{} bash -c \"{}\" | grep \"\${PWD}\" | awk '{print \$2}' | xargs kill -9" > ${RUNDIR}/${TRIAL}/kill
    chmod +x ${RUNDIR}/${TRIAL}/kill
    if [ -r "${MDCLB}" ]; then CLBIN="${MDCLB}"; fi  # mariadb client (reset like above after '-' change)
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
    if [ ! -z "${MDCLB}" ]; then CLBIN="${CLBIN}-"; fi  # mariadb-check
    MCCMD="set +H; ${CLBIN}check --socket=${SOCKET} -uroot -Acfe 2>&1 | grep --binary-files=text -v ' OK$' | sed 's|^test|DBREPLDUMMY1|g' | tr '\\n' ' ' | sed 's|DBREPLDUMMY1|\\ntest|g' | grep  --binary-files=text -v \"The storage engine for the table doesn't support check\" | grep -v '^[ \\t]*$' | sed \"s|^|\${PWD}:|;s|[ ]\\+| |g;s| : |: |g\""
    CLBIN=
    MDCLB=
    echo "${MCCMD}" | sed 's|/dev/shm|/data|' > ${RUNDIR}/${TRIAL}/mysqlcheck_test
    echo "${MCCMD}" | sed 's|/dev/shm|/data|;s|\-\-check |--check-upgrade |' > ${RUNDIR}/${TRIAL}/mysqlcheck_upg_test
    MCCMD=
    chmod +x ${RUNDIR}/${TRIAL}/mysqlcheck_*
    echo "# Recovery testing script." > ${RUNDIR}/${TRIAL}/start_recovery
    echo "# This script creates an all-privileges recovery@'%' user; ref recovery-user.sql in the wordir (no the trial dir))" >> ${RUNDIR}/${TRIAL}/start_recovery
    echo "# It then brings up the server for a crash recovery test." >> ${RUNDIR}/${TRIAL}/start_recovery
    echo "BASEDIR=$BASEDIR" >> ${RUNDIR}/${TRIAL}/start_recovery
    echo "if [ ! -r ${WORKDIR}/${TRIAL}/log/master.original.err ]; then" >> ${RUNDIR}/${TRIAL}/start_recovery
    echo "  cp ${WORKDIR}/${TRIAL}/log/master.err ${WORKDIR}/${TRIAL}/log/master.original.err" >> ${RUNDIR}/${TRIAL}/start_recovery
    echo "fi" >> ${RUNDIR}/${TRIAL}/start_recovery
    echo "if [ ! -d ./data.original ]; then" >> ${RUNDIR}/${TRIAL}/start_recovery
    echo "  cp -r ./data ./data.original" >> ${RUNDIR}/${TRIAL}/start_recovery
    echo "fi" >> ${RUNDIR}/${TRIAL}/start_recovery
    echo "if [ ! -d ./tmp.original ]; then" >> ${RUNDIR}/${TRIAL}/start_recovery
    echo "  cp -r ./tmp ./tmp.original" >> ${RUNDIR}/${TRIAL}/start_recovery
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
      echo "${MYSAFE} ${MYEXTRA} ${ENCRYPTION_OPTIONS}" > ${RUNDIR}/${TRIAL}/MYEXTRA.left # When changing this, also search for/edit other '\.left' and '\.right' occurrences in this file
      echo "${MYSAFE} ${MYEXTRA2} ${ENCRYPTION_OPTIONS}" > ${RUNDIR}/${TRIAL}/MYEXTRA.right
    else
      echo "${MYSAFE} ${MYEXTRA} ${ENCRYPTION_OPTIONS}" > ${RUNDIR}/${TRIAL}/MYEXTRA
      if [ "${REPLICATION}" -eq 1 ]; then
        if [ ! -z "${REPL_EXTRA}" ]; then
          echo "${REPL_EXTRA}" > ${RUNDIR}/${TRIAL}/REPL_EXTRA
        fi
        if [ ! -z "${MASTER_EXTRA}" ]; then
          echo "${MASTER_EXTRA}" > ${RUNDIR}/${TRIAL}/MASTER_EXTRA
        fi
        if [ ! -z "${SLAVE_EXTRA}" ]; then
          echo "${SLAVE_EXTRA}" > ${RUNDIR}/${TRIAL}/SLAVE_EXTRA
        fi
      fi
    fi
    echo "${MYINIT}" > ${RUNDIR}/${TRIAL}/MYINIT
    if [ "${VALGRIND_RUN}" == "1" ]; then
      touch ${RUNDIR}/${TRIAL}/VALGRIND
    fi
    # Restore orignal MYEXTRA for the next trial (MYEXTRA is no longer needed anywhere else. If this changes in the future, relocate this to below the changed code)
    MYEXTRA=${MYEXTRA_SAVE_IT}
    # Give up to x (start timeout) seconds for mysqld/mariadbd to start, but check intelligently for known startup issues like "Error while setting value" for options
    if [ "${VALGRIND_RUN}" == "0" ]; then
      echoit "Waiting for mysqld/mariadbd (pid: ${MPID}) to fully start..."
      if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 ]; then
        echoit "Waiting for mysqld/mariadbd (pid: ${MPID2}) to fully start..."
      fi
    else
      echoit "Waiting for mysqld/mariadbd (pid: ${MPID}) to fully start (note this is slow for Valgrind runs, and can easily take 35-90 seconds even on an high end server)..."
      if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 ]; then
        echoit "Waiting for mysqld/mariadbd (pid: ${MPID2}) to fully start (note this is slow for Valgrind runs, and can easily take 35-90 seconds even on an high end server)..."
      fi
    fi
    FAILEDSTARTABORT=0
    START_WAIT="${EPOCHREALTIME}"  # For the startup time on the server started line below
    for X in $(seq 0 ${MYSQLD_START_TIMEOUT}); do
      sleep 1
      if ${BASEDIR}/bin/mysqladmin -uroot -S${SOCKET} ping > /dev/null 2>&1; then
        if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 ]; then
          if ${BASEDIR}/bin/mysqladmin -uroot -S${RUNDIR}/${TRIAL}/socket2.sock ping > /dev/null 2>&1; then
            break
          fi
        else
          if [[ ${REPLICATION} -eq 1 ]]; then
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
      if [ ${REPLICATION} -eq 1 ]; then
        if [ -z "${SLAVE_MPID}" ]; then
          echoit "Assert! \$SLAVE_MPID empty. Slave is not running. Terminating!"
          exit 1
        fi
      fi
      if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 ]; then
        if [ "${MPID2}" == "" ]; then
          echoit "Assert! ${MPID2} empty. Terminating!"
          exit 1
        fi
      fi
      if grep -qi "Can.t create.write to file" ${RUNDIR}/${TRIAL}/log/*.err; then
        echoit "Assert! Likely an incorrect --init-file option was specified (check if the specified file actually exists)"  # Also see https://jira.mariadb.org/browse/MDEV-27232
        echoit "Terminating run as there is no point in continuing; all trials will fail with this error."
        removetrial
        exit 1
      elif grep -qi "ERROR. Aborting" ${RUNDIR}/${TRIAL}/log/*.err; then
        if grep -qi "TCP.IP port.*Address already in use" ${RUNDIR}/${TRIAL}/log/*.err; then
          echoit "Assert! The text '[ERROR] Aborting' was found in the error log due to a IP port conflict (the port was already in use)"
          removetrial
        else
          if [ ${ADD_RANDOM_OPTIONS} -eq 0 ]; then # Halt for ADD_RANDOM_OPTIONS=0 runs, they should not produce errors like these, as MYEXTRA should be high-quality/non-faulty
            if grep -qi "Can't initialize timers" ${RUNDIR}/${TRIAL}/log/*.err; then
              echoit "Error! '[ERROR] Aborting' was found in the error log, due to a 'Can't initialize timers' issue, ref https://jira.mariadb.org/browse/MDEV-22286, currently being researched. The run should be able to continue normally. Not saving trial."
              removetrial
            else
              echoit "Assert! '[ERROR] Aborting' was found in the error log. This is likely an issue with one of the \$MYEXTRA (or \$MYSAFE or \$ENCRYPTION_OPTIONS) startup parameters. Saving trial for further analysis, and dumping error log here for quick analysis. Please check the output against the \$MYEXTRA (or \$MYSAFE if it was modified) settings. You may also want to try setting \$MYEXTRA=\"${MYEXTRA}\" directly in start (as created by startup.sh using your base directory)."
              grep "ERROR" ${RUNDIR}/${TRIAL}/log/*.err | tee -a /${WORKDIR}/pquery-run.log
              if grep -qiE "error 28|out of disk space" ${RUNDIR}/${TRIAL}/log/*.err; then  # Likely OOS on /dev/shm
                echoit "Noticed a likely OOS on ${RUNDIR} or in /tmp or root (/). Removing trial to maximize space, and pausing 0.5 hour before trying again (reducer's may be running and consuming space)"
                removetrial
                sleep 1800
                echoit "Slept 0.5h, resuming pquery-run.sh run..."
              else
                savetrial
                echoit "Remember to cleanup/delete the rundir:  rm -Rf ${RUNDIR}"
                if [ "${MARIADB_BINLOG_RECOVERY_TESTING}" -ne 1 ]; then
                  exit 1  # Ref [*A] above
                fi
              fi
            fi
          else # Do not halt for ADD_RANDOM_OPTIONS=1 runs, they are likely to produce errors like these as MYEXTRA was randomly changed
            echoit "'[ERROR] Aborting' was found in the error log. This is likely an issue with one of the MYEXTRA, MYSAFE or ENCRYPTION_OPTIONS startup parameters. As ADD_RANDOM_OPTIONS=1, this is likely to be encountered. Not saving trial. If you see this error for every trial however, set \$ADD_RANDOM_OPTIONS=0 & try running pquery-run.sh again. If it still fails, your base \$MYEXTRA, \$MYSAFE or \$ENCRYPTION_OPTIONS settings may be faulty."
            grep "ERROR" ${RUNDIR}/${TRIAL}/log/*.err | tee -a /${WORKDIR}/pquery-run.log
            FAILEDSTARTABORT=1
            break
          fi
        fi
      fi
      if [ "${REPLICATION}" -eq 1 ]; then
        if grep -qi "Can.t create.write to file" ${RUNDIR}/${TRIAL}/log/*.err; then
          echoit "Assert! Likely an incorrect --init-file option was specified (check if the specified file actually exists)"  # Also see https://jira.mariadb.org/browse/MDEV-27232
          echoit "Terminating run as there is no point in continuing; all trials will fail with this error."
          removetrial
          exit 1
        elif grep -qi "ERROR. Aborting" ${RUNDIR}/${TRIAL}/log/slave.err; then
          echoit "Assert! The text '[ERROR] Aborting' was found in the slave error log"
          removetrial
        fi
      fi
      if [ $(ls -l ${RUNDIR}/${TRIAL}/*/*core* 2>/dev/null | wc -l) -ge 1 ]; then break; fi # Break the wait-for-server-started loop if a core file is found. Handling of core is done below.
    done
    # Check if mysqld/mariadbd is alive and if so, set ISSTARTED=1 so pquery will run
    if ${BASEDIR}/bin/mysqladmin -uroot -S${SOCKET} ping > /dev/null 2>&1; then
      ISSTARTED=1
      START_DUR="$(duration ${START_WAIT})"
      if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 ]; then
        echoit "Primary server started (${START_DUR}s) Client: $(echo ${BIN} | sed 's|/mysqld|/mysql|;s|/mariadbd|/mariadb|') -uroot -S${SOCKET}" "$(duration_style ${START_DUR})"
        if ${BASEDIR}/bin/mysqladmin -uroot -S${RUNDIR}/${TRIAL}/socket2.sock ping > /dev/null 2>&1; then
          echoit "Secondary server started ok. Client: $(echo ${BIN} | sed 's|/mysqld|/mysql|;s|/mariadbd|/mariadb|') -uroot -S${SOCKET}"
          ${BASEDIR}/bin/mysql -uroot -S${RUNDIR}/${TRIAL}/socket2.sock -e "CREATE DATABASE IF NOT EXISTS test;" > /dev/null 2>&1
        fi
      else
        echoit "Server started (${START_DUR}s) Client: $(echo ${BIN} | sed 's|/mysqld|/mysql|;s|/mariadbd|/mariadb|') -uroot -S${SOCKET}" "$(duration_style ${START_DUR})"
        ${BASEDIR}/bin/mysql -uroot -S${SOCKET} -e "CREATE DATABASE IF NOT EXISTS test;" > /dev/null 2>&1
      fi
      if [[ ${REPLICATION} -eq 1 ]]; then
        ${BASEDIR}/bin/mysql -uroot -S${SOCKET} -e "DELETE FROM mysql.user WHERE user='';" 2>/dev/null
        ${BASEDIR}/bin/mysql -uroot -S${SOCKET} -e "GRANT REPLICATION SLAVE ON *.* TO 'repl_user'@'%' IDENTIFIED BY 'repl_pass'; FLUSH PRIVILEGES;" 2>/dev/null
        ${BASEDIR}/bin/mysql -uroot -S${SLAVE_SOCKET} -e "CHANGE MASTER TO MASTER_HOST='127.0.0.1', MASTER_PORT=$PORT, MASTER_USER='repl_user', MASTER_PASSWORD='repl_pass', MASTER_USE_GTID=slave_pos ; START SLAVE;" 2>/dev/null
      fi
      if [ "$PMM" == "1" ]; then
        echoit "Adding Orchestrator user for MySQL replication topology management.."
        printf "[client]\nuser=root\nsocket=${SOCKET}\n" |
          ${BASEDIR}/bin/mysql --defaults-file=/dev/stdin -e "GRANT SUPER, PROCESS, REPLICATION SLAVE, RELOAD ON *.* TO 'orc_client_user'@'%' IDENTIFIED BY 'orc_client_password'" 2>/dev/null
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
    # === MDG Options Stage 1: Add random mysqld/mariadbd options to MDG_MYEXTRA
    if [ "${MDG_ADD_RANDOM_OPTIONS}" -eq 1 ]; then
      OPTIONS_TO_ADD=
      NR_OF_OPTIONS_TO_ADD=$(${RANDOM_BIN} 1 ${MDG_MAX_NR_OF_RND_OPTS_TO_ADD})
      for X in $(seq 1 ${NR_OF_OPTIONS_TO_ADD}); do
        OPTION_TO_ADD="$(shuf --random-source=<(${RANDOM_BIN} --raw) ${MDG_OPTIONS_INFILE} | head -n1)"
        if [ "$(echo ${OPTION_TO_ADD} | sed 's| ||g;s|.*query.alloc.block.size=1125899906842624.*||')" != "" ]; then # http://bugs.mysql.com/bug.php?id=78238
          OPTIONS_TO_ADD="${OPTIONS_TO_ADD} ${OPTION_TO_ADD}"
        fi
      done
      echoit "MDG_ADD_RANDOM_OPTIONS=1: adding mysqld/mariadbd option(s) ${OPTIONS_TO_ADD} to this run's MDG_MYEXTRA..."
      MDG_MYEXTRA="${OPTIONS_TO_ADD}"
      if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 ]; then
        MYEXTRA2="${MYEXTRA2} ${OPTIONS_TO_ADD}"
      fi
    fi
    # === MDG Options Stage 2: Add random wsrep mysqld/mariadbd options to MDG_MYEXTRA
    if [ "${MDG_WSREP_ADD_RANDOM_WSREP_MYSQLD_OPTIONS}" -eq 1 ]; then
      OPTIONS_TO_ADD=
      NR_OF_OPTIONS_TO_ADD=$(${RANDOM_BIN} 1 ${MDG_WSREP_MAX_NR_OF_RND_OPTS_TO_ADD})
      for X in $(seq 1 ${NR_OF_OPTIONS_TO_ADD}); do
        OPTION_TO_ADD="$(shuf --random-source=<(${RANDOM_BIN} --raw) ${MDG_WSREP_OPTIONS_INFILE} | head -n1)"
        OPTIONS_TO_ADD="${OPTIONS_TO_ADD} ${OPTION_TO_ADD}"
      done
      echoit "MDG_WSREP_ADD_RANDOM_WSREP_MYSQLD_OPTIONS=1: adding wsrep provider mysqld/mariadbd option(s) ${OPTIONS_TO_ADD} to this run's MDG_MYEXTRA..."
      MDG_MYEXTRA="${MDG_MYEXTRA} ${OPTIONS_TO_ADD}"
    fi
    # === MDG Options Stage 3: Add random wsrep (Galera) configuration options
    if [ "${MDG_WSREP_PROVIDER_ADD_RANDOM_WSREP_PROVIDER_CONFIG_OPTIONS}" -eq 1 ]; then
      OPTIONS_TO_ADD=
      NR_OF_OPTIONS_TO_ADD=$(${RANDOM_BIN} 1 ${MDG_WSREP_PROVIDER_MAX_NR_OF_RND_OPTS_TO_ADD})
      for X in $(seq 1 ${NR_OF_OPTIONS_TO_ADD}); do
        OPTION_TO_ADD="$(shuf --random-source=<(${RANDOM_BIN} --raw) ${MDG_WSREP_PROVIDER_OPTIONS_INFILE} | head -n1)"
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
        echoit "Node #${i}: $(echo ${BIN} | sed 's|/mysqld|/mysql|;s|/mariadbd|/mariadb|') -uroot -S${RUNDIR}/${TRIAL}/node${i}/node${i}_socket.sock"
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
      echoit "Node #1: $(echo ${BIN} | sed 's|/mysqld|/mysql|;s|/mariadbd|/mariadb|') -uroot -S${SOCKET1}"
      echoit "Node #2: $(echo ${BIN} | sed 's|/mysqld|/mysql|;s|/mariadbd|/mariadb|') -uroot -S${SOCKET2}"
      echoit "Node #3: $(echo ${BIN} | sed 's|/mysqld|/mysql|;s|/mariadbd|/mariadb|') -uroot -S${SOCKET3}"
    fi
  fi

  if [ ${ISSTARTED} -eq 1 ]; then
    rm -f ${RUNDIR}/${TRIAL}/startup_failure_thread-0.sql # Remove the earlier created fake (SELECT 1; only) file present for startup issues (server is started OK now)
    if [ ${THREADS} -eq 1 ]; then                       # Single-threaded run (1 client only)
      if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 ]; then   # Single-threaded query correctness run using a chunk from INFILE against two servers to then compare outcomes
        echoit "Taking ${QC_NR_OF_STATEMENTS_PER_TRIAL} lines randomly from the SQL of this trial as testcase for this query correctness trial..."
        # Make sure that the code below generates exactly 3 lines (DROP/CREATE/USE) -OR- change the "head -n3" and "sed '1,3d'" (both below) to match any updates made
        echo 'DROP DATABASE test;' > ${RUNDIR}/${TRIAL}/${TRIAL}.sql
        if [ "$(echo ${QC_PRI_ENGINE} | tr [:upper:] [:lower:])" == "rocksdb" -o "$(echo ${QC_SEC_ENGINE} | tr [:upper:] [:lower:])" == "rocksdb" ]; then
          case "$(${RANDOM_BIN} 1 4)" in
            1) echo 'CREATE DATABASE test DEFAULT CHARACTER SET="Binary" DEFAULT COLLATE="Binary";' >> ${RUNDIR}/${TRIAL}/${TRIAL}.sql ;;
            2) echo 'CREATE DATABASE test DEFAULT CHARACTER SET="utf8" DEFAULT COLLATE="utf8_bin";' >> ${RUNDIR}/${TRIAL}/${TRIAL}.sql ;;
            3) echo 'CREATE DATABASE test DEFAULT CHARACTER SET="latin1" DEFAULT COLLATE="latin1_bin";' >> ${RUNDIR}/${TRIAL}/${TRIAL}.sql ;;
            4) echo 'CREATE DATABASE test DEFAULT CHARACTER SET="utf8mb4" DEFAULT COLLATE="utf8mb4_bin";' >> ${RUNDIR}/${TRIAL}/${TRIAL}.sql ;;
          esac
        else
          echo 'CREATE DATABASE test;' >> ${RUNDIR}/${TRIAL}/${TRIAL}.sql
        fi
        echo 'USE test;' >> ${RUNDIR}/${TRIAL}/${TRIAL}.sql
        shuf --random-source=<(${RANDOM_BIN} --raw) ${TRIAL_SQL} | head -n${QC_NR_OF_STATEMENTS_PER_TRIAL} >> ${RUNDIR}/${TRIAL}/${TRIAL}.sql
        awk -v seed=$(${RANDOM_BIN} 1 2147483647) 'BEGIN{srand(seed);} {ORS="#@"int(999999999*rand())"\n"} {print $0}' ${RUNDIR}/${TRIAL}/${TRIAL}.sql > ${RUNDIR}/${TRIAL}/${TRIAL}.new
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
        SQL_FILE_1="${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_PRI_ENGINE}"
        SQL_FILE_2="${RUNDIR}/${TRIAL}/${TRIAL}.sql.${QC_SEC_ENGINE}"
        PQUERY_INFILE_LINES="$(wc -l < ${SQL_FILE_1})"  # pquery reads this per-engine file, not the whole trial SQL
        if [[ "${MDG}" -eq 0 && ${GRP_RPL} -eq 0 ]]; then
          echoit "Starting Primary pquery run for engine ${QC_PRI_ENGINE} (log stored in ${RUNDIR}/${TRIAL}/pquery1.log)..."
          if [ ${QUERY_CORRECTNESS_MODE} -ne 2 ]; then
            ${PQUERY_BIN} --infile=${SQL_FILE_1} --threads=${THREADS} --queries-per-thread=${QUERIES_PER_THREAD} --logdir=${RUNDIR}/${TRIAL} --log-all-queries --log-failed-queries --no-shuffle --log-query-statistics --user=root --socket=${SOCKET} > ${RUNDIR}/${TRIAL}/pquery1.log 2>&1
            PQPID="$!"
            sleep 2.5  # It takes SAN builds, for example, about 2 seconds to finish an 'LSAN detected' error log entry
            mv ${RUNDIR}/${TRIAL}/pquery_thread-0.sql ${RUNDIR}/${TRIAL}/pquery_thread-0.${QC_PRI_ENGINE}.sql 2>&1 | tee -a /${WORKDIR}/pquery-run.log
            mv ${RUNDIR}/${TRIAL}/pquery_thread-0.out ${RUNDIR}/${TRIAL}/pquery_thread-0.${QC_PRI_ENGINE}.out 2>&1 | tee -a /${WORKDIR}/pquery-run.log
          else
            ${PQUERY_BIN} --infile=${SQL_FILE_1} --threads=${THREADS} --queries-per-thread=${QUERIES_PER_THREAD} --logdir=${RUNDIR}/${TRIAL} --log-all-queries --log-failed-queries --no-shuffle --log-query-statistics --log-client-output --user=root --log-query-number --socket=${SOCKET} > ${RUNDIR}/${TRIAL}/pquery1.log 2>&1
            PQPID="$!"
            sleep 2.5  # It takes SAN builds, for example, about 2 seconds to finish an 'LSAN detected' error log entry
            mv ${RUNDIR}/${TRIAL}/default.node.tld_thread-0.sql ${RUNDIR}/${TRIAL}/pquery_thread-0.${QC_PRI_ENGINE}.sql 2>&1 | tee -a /${WORKDIR}/pquery-run.log
            mv ${RUNDIR}/${TRIAL}/default.node.tld_thread-0.out ${RUNDIR}/${TRIAL}/pquery_thread-0.${QC_PRI_ENGINE}.out 2>&1 | tee -a /${WORKDIR}/pquery-run.log
          fi
          echoit "Starting Secondary pquery run for engine ${QC_SEC_ENGINE} (log stored in ${RUNDIR}/${TRIAL}/pquery2.log)..."
          if [ ${QUERY_CORRECTNESS_MODE} -ne 2 ]; then
            ${PQUERY_BIN} --infile=${SQL_FILE_2} --threads=${THREADS} --queries-per-thread=${QUERIES_PER_THREAD} --logdir=${RUNDIR}/${TRIAL} --log-all-queries --log-failed-queries --no-shuffle --log-query-statistics --user=root --socket=${RUNDIR}/${TRIAL}/socket2.sock > ${RUNDIR}/${TRIAL}/pquery2.log 2>&1
            PQPID2="$!"
            sleep 2.5  # It takes SAN builds, for example, about 2 seconds to finish an 'LSAN detected' error log entry
            mv ${RUNDIR}/${TRIAL}/pquery_thread-0.sql ${RUNDIR}/${TRIAL}/pquery_thread-0.${QC_SEC_ENGINE}.sql 2>&1 | tee -a /${WORKDIR}/pquery-run.log
            mv ${RUNDIR}/${TRIAL}/pquery_thread-0.out ${RUNDIR}/${TRIAL}/pquery_thread-0.${QC_SEC_ENGINE}.out 2>&1 | tee -a /${WORKDIR}/pquery-run.log
            grep -o "CHANGED: [0-9]\+" ${RUNDIR}/${TRIAL}/pquery_thread-0.${QC_PRI_ENGINE}.sql > ${RUNDIR}/${TRIAL}/${QC_PRI_ENGINE}.result
            grep -o "CHANGED: [0-9]\+" ${RUNDIR}/${TRIAL}/pquery_thread-0.${QC_SEC_ENGINE}.sql > ${RUNDIR}/${TRIAL}/${QC_SEC_ENGINE}.result
          else
            ${PQUERY_BIN} --infile=${SQL_FILE_2} --threads=${THREADS} --queries-per-thread=${QUERIES_PER_THREAD} --logdir=${RUNDIR}/${TRIAL} --log-all-queries --log-failed-queries --no-shuffle --log-query-statistics --log-client-output --user=root --log-query-number --socket=${RUNDIR}/${TRIAL}/socket2.sock > ${RUNDIR}/${TRIAL}/pquery2.log 2>&1
            PQPID2="$!"
            sleep 2.5  # It takes SAN builds, for example, about 2 seconds to finish an 'LSAN detected' error log entry
            mv ${RUNDIR}/${TRIAL}/default.node.tld_thread-0.sql ${RUNDIR}/${TRIAL}/pquery_thread-0.${QC_SEC_ENGINE}.sql 2>&1 | tee -a /${WORKDIR}/pquery-run.log
            mv ${RUNDIR}/${TRIAL}/default.node.tld_thread-0.out ${RUNDIR}/${TRIAL}/pquery_thread-0.${QC_SEC_ENGINE}.out 2>&1 | tee -a /${WORKDIR}/pquery-run.log
            diff ${RUNDIR}/${TRIAL}/pquery_thread-0.${QC_PRI_ENGINE}.out ${RUNDIR}/${TRIAL}/pquery_thread-0.${QC_SEC_ENGINE}.out > ${RUNDIR}/${TRIAL}/diff.result
            echo "${QC_PRI_ENGINE}" > ${RUNDIR}/${TRIAL}/diff.left # When changing this, also search for/edit other '\.left' and '\.right' occurrences in this file
            echo "${QC_SEC_ENGINE}" > ${RUNDIR}/${TRIAL}/diff.right
          fi
        else
          ## TODO: Add QUERY_CORRECTNESS_MODE checks (as seen above) to the code below also. FTM, the code below only does "changed rows" comparison
          echoit "Starting Primary pquery run for engine ${QC_PRI_ENGINE} (log stored in ${RUNDIR}/${TRIAL}/pquery1.log)..."
          ${PQUERY_BIN} --infile=${SQL_FILE_1} --threads=${THREADS} --queries-per-thread=${QUERIES_PER_THREAD} --logdir=${RUNDIR}/${TRIAL} --log-all-queries --log-failed-queries --no-shuffle --log-query-statistics --user=root --socket=${SOCKET1} > ${RUNDIR}/${TRIAL}/pquery1.log 2>&1
          PQPID="$!"
          sleep 2.5  # It takes SAN builds, for example, about 2 seconds to finish an 'LSAN detected' error log entry
          mv ${RUNDIR}/${TRIAL}/pquery_thread-0.sql ${RUNDIR}/${TRIAL}/pquery_thread-0.${QC_PRI_ENGINE}.sql 2>&1 | tee -a /${WORKDIR}/pquery-run.log
          grep -o "CHANGED: [0-9]\+" ${RUNDIR}/${TRIAL}/pquery_thread-0.${QC_PRI_ENGINE}.sql > ${RUNDIR}/${TRIAL}/${QC_PRI_ENGINE}.result
          echoit "Starting Secondary pquery run for engine ${QC_SEC_ENGINE} (log stored in ${RUNDIR}/${TRIAL}/pquery2.log)..."
          ${PQUERY_BIN} --infile=${SQL_FILE_2} --threads=${THREADS} --queries-per-thread=${QUERIES_PER_THREAD} --logdir=${RUNDIR}/${TRIAL} --log-all-queries --log-failed-queries --no-shuffle --log-query-statistics --user=root --socket=${SOCKET2} > ${RUNDIR}/${TRIAL}/pquery2.log 2>&1
          PQPID2="$!"
          sleep 2.5  # It takes SAN builds, for example, about 2 seconds to finish an 'LSAN detected' error log entry
          mv ${RUNDIR}/${TRIAL}/pquery_thread-0.sql ${RUNDIR}/${TRIAL}/pquery_thread-0.${QC_SEC_ENGINE}.sql 2>&1 | tee -a /${WORKDIR}/pquery-run.log
          grep -o "CHANGED: [0-9]\+" ${RUNDIR}/${TRIAL}/pquery_thread-0.${QC_SEC_ENGINE}.sql > ${RUNDIR}/${TRIAL}/${QC_SEC_ENGINE}.result
        fi
      else # Not a query correctness testing run
        if [ ${QUERY_DURATION_TESTING} -eq 1 ]; then # Query duration testing run
          if [[ "${MDG}" -eq 0 && "${GRP_RPL}" -eq 0 ]]; then
            echoit "Starting pquery (log stored in ${RUNDIR}/${TRIAL}/pquery.log)..."
            ${PQUERY_BIN} --infile=${TRIAL_SQL} --database=test --threads=${THREADS} --queries-per-thread=${QUERIES_PER_THREAD} --logdir=${RUNDIR}/${TRIAL} --log-all-queries --log-failed-queries --log-query-duration --user=root --socket=${SOCKET} > ${RUNDIR}/${TRIAL}/pquery.log 2>&1 &
            PQPID="$!"
            sleep 2.5  # It takes SAN builds, for example, about 2 seconds to finish an 'LSAN detected' error log entry
          else
            if [[ "${MDG_CLUSTER_RUN}" -eq 1 ]]; then
              cat ${MDG_CLUSTER_CONFIG} |
                sed "s|\/tmp|${RUNDIR}\/${TRIAL}|" |
                sed "s|\/home\/$(whoami)\/mariadb-qa|${SCRIPT_PWD}|" \
                  > ${RUNDIR}/${TRIAL}/pquery-cluster.cfg
              echoit "Starting pquery (log stored in ${RUNDIR}/${TRIAL}/pquery.log)..."
              ${PQUERY_BIN} --config-file=${RUNDIR}/${TRIAL}/pquery-cluster.cfg > ${RUNDIR}/${TRIAL}/pquery.log 2>&1 &
              PQPID="$!"
            elif [[ ${GRP_RPL_CLUSTER_RUN} -eq 1 ]]; then
              cat ${GRP_RPL_CLUSTER_CONFIG} |
                sed "s|\/tmp|${RUNDIR}\/${TRIAL}|" |
                sed "s|\/home\/$(whoami)\/mariadb-qa|${SCRIPT_PWD}|" \
                  > ${RUNDIR}/${TRIAL}/pquery-cluster.cfg
              echoit "Starting pquery (log stored in ${RUNDIR}/${TRIAL}/pquery.log)..."
              ${PQUERY_BIN} --config-file=${RUNDIR}/${TRIAL}/pquery-cluster.cfg > ${RUNDIR}/${TRIAL}/pquery.log 2>&1 &
              PQPID="$!"
            else  # Query duration testing run
              echoit "Starting pquery (log stored in ${RUNDIR}/${TRIAL}/pquery.log)..."
              ${PQUERY_BIN} --infile=${TRIAL_SQL} --database=test --threads=${THREADS} --queries-per-thread=${QUERIES_PER_THREAD} --logdir=${RUNDIR}/${TRIAL} --log-all-queries --log-failed-queries --log-query-duration --user=root --socket=${SOCKET1} > ${RUNDIR}/${TRIAL}/pquery.log 2>&1 &
              PQPID="$!"
            fi
          fi
        else # Standard pquery run / Not a query duration testing run
          if [[ "${MDG}" -eq 0 && "${GRP_RPL}" -eq 0 ]]; then
            # Preload SQL if the PRELOAD feature is enabled (this SQL will be prepended to the trial's SQL later)
            if [ "${PRELOAD}" == "1" -a ! -z "${PRELOAD_SQL}" ]; then
              echoit "PRELOAD=1: Pre-loading SQL in ${PRELOAD_SQL} using pquery"
              mkdir -p ${RUNDIR}/${TRIAL}/preload
              ${PQUERY_BIN} --infile=${PRELOAD_SQL} --database=test --threads=1 --queries-per-thread=99999999 --logdir=${RUNDIR}/${TRIAL}/preload --log-all-queries --log-failed-queries --no-shuffle --user=root --socket=${SOCKET} > ${RUNDIR}/${TRIAL}/preload/pquery_preload_sql.log 2>&1  # Do not start in background like other PQUERY_BIN calls in this script. Here we just want the preload to finish before executing other statements. Also, when started in the background without waiting for it results in 0 byte default.node.tld_thread-0.sql on some reason (unimportant as no background should be used, or when background is used, the process should be waited upon)
            fi
            # Standard/default (non-GRP-RPL non-Galera non-Query-duration-testing) pquery run
            echoit "Starting pquery (log stored in ${RUNDIR}/${TRIAL}/pquery.log)..."
            ${PQUERY_BIN} --infile=${TRIAL_SQL} --database=test --threads=${THREADS} --queries-per-thread=${QUERIES_PER_THREAD} --logdir=${RUNDIR}/${TRIAL} --log-all-queries --log-failed-queries --user=root --socket=${SOCKET} > ${RUNDIR}/${TRIAL}/pquery.log 2>&1 &
            PQPID="$!"
          else
            # Preload SQL if the PRELOAD feature is enabled (this SQL will be prepended to the trial's SQL later)
            if [ "${PRELOAD}" == "1" -a ! -z "${PRELOAD_SQL}" ]; then
              echoit "PRELOAD=1: Pre-loading SQL in ${PRELOAD_SQL} using pquery"
              mkdir -p ${RUNDIR}/${TRIAL}/preload
              ${PQUERY_BIN} --infile=${PRELOAD_SQL} --database=test --threads=1 --queries-per-thread=99999999 --logdir=${RUNDIR}/${TRIAL}/preload --log-all-queries --log-failed-queries --no-shuffle --user=root --socket=${SOCKET1} > ${RUNDIR}/${TRIAL}/preload/pquery_preload_sql.log 2>&1  # Do not start in background... (ref similar comment elsewhere in this script)
            fi
            if [[ "${MDG_CLUSTER_RUN}" -eq 1 ]]; then
              for i in $(seq 1 ${NR_OF_NODES}); do
                cat << EOF >> ${RUNDIR}/${TRIAL}/pquery-cluster.cfg
[node${i}.md.galera]
database = test
address = localhost
infile = ${TRIAL_SQL}
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
              echoit "Starting pquery (log stored in ${RUNDIR}/${TRIAL}/pquery.log)..."
              echoit "${PQUERY_BIN} --config-file=${RUNDIR}/${TRIAL}/pquery-cluster.cfg"
              ${PQUERY_BIN} --config-file=${RUNDIR}/${TRIAL}/pquery-cluster.cfg > ${RUNDIR}/${TRIAL}/pquery.log 2>&1 &
              PQPID="$!"
            elif [[ ${GRP_RPL_CLUSTER_RUN} -eq 1 ]]; then
              cat ${GRP_RPL_CLUSTER_CONFIG} |
                sed "s|\/tmp|${RUNDIR}\/${TRIAL}|" |
                sed "s|\/home\/$(whoami)\/mariadb-qa|${SCRIPT_PWD}|" \
                  > ${RUNDIR}/${TRIAL}/pquery-cluster.cfg
              echoit "Starting pquery (log stored in ${RUNDIR}/${TRIAL}/pquery.log)..."
              ${PQUERY_BIN} --config-file=${RUNDIR}/${TRIAL}/pquery-cluster.cfg > ${RUNDIR}/${TRIAL}/pquery.log 2>&1 &
              PQPID="$!"
            else
              echoit "Starting pquery (log stored in ${RUNDIR}/${TRIAL}/pquery.log)..."
              ${PQUERY_BIN} --infile=${TRIAL_SQL} --database=test --threads=${THREADS} --queries-per-thread=${QUERIES_PER_THREAD} --logdir=${RUNDIR}/${TRIAL} --log-all-queries --log-failed-queries --user=root --socket=${SOCKET1} > ${RUNDIR}/${TRIAL}/pquery.log 2>&1 &
              PQPID="$!"
              #${PQUERY_BIN} --infile=${INFILE} --database=test --threads=${THREADS} --queries-per-thread=${QUERIES_PER_THREAD} --logdir=${RUNDIR}/${TRIAL} --log-all-queries --log-failed-queries --log-query-duration --user=root --socket=${SOCKET1} > ${RUNDIR}/${TRIAL}/pquery.log 2>&1 &
              #PQPID="$!"
              #echoit "Assert: GRP_RPL_CLUSTER_RUN=${GRP_RPL_CLUSTER_RUN} and MDG_CLUSTER_RUN=${MDG_CLUSTER_RUN}"
              #exit 1
            fi
          fi
        fi
      fi
    else
      # Multi-threaded run using a chunk of this trial's SQL (${THREADS} clients)
      if [ ${PQUERY3} -eq 1 ]; then
        PQUERY_INFILE_LINES=  # pquery3 builds its own SQL from the metadata, so there is no input file to compare the executed count against
        if [ "${TRIAL}" == "1" ]; then
          echoit "Creating metadata randomly using random seed ${SEED} ..."
        else
          echoit "Loading metadata from ${WORKDIR}/step_$((${TRIAL} - 1)).dll ..."
        fi
        if [[ "${MDG}" -eq 0 && "${GRP_RPL}" -eq 0 ]]; then
          CMD="${PQUERY_BIN} --database=test --threads=${THREADS} --queries-per-thread=${QUERIES_PER_THREAD} --logdir=${RUNDIR}/${TRIAL} --user=root --socket=${SOCKET} --seed ${SEED} --step ${TRIAL} --metadata-path ${WORKDIR}/ --seconds ${PQUERY_RUN_TIMEOUT} ${DYNAMIC_QUERY_PARAMETER}"
        elif [ "${MDG_CLUSTER_RUN}" -eq 1 ]; then
          cat ${MDG_CLUSTER_CONFIG} |
              sed "s|\/tmp|${RUNDIR}\/${TRIAL}|" \
                > ${RUNDIR}/${TRIAL}/pquery3-cluster-mdg.cfg
          CMD="${PQUERY_BIN} --database=test --config-file=${RUNDIR}/${TRIAL}/pquery3-cluster-mdg.cfg --queries-per-thread=${QUERIES_PER_THREAD} --seed ${SEED} --step ${TRIAL} --metadata-path ${WORKDIR}/ --seconds ${PQUERY_RUN_TIMEOUT} ${DYNAMIC_QUERY_PARAMETER}"
        else
          CMD="${PQUERY_BIN} --database=test --threads=${THREADS} --queries-per-thread=${QUERIES_PER_THREAD} --logdir=${RUNDIR}/${TRIAL}/node1/ --user=root --socket=${SOCKET1} --seed ${SEED} --step ${TRIAL} --metadata-path ${WORKDIR}/ --seconds ${PQUERY_RUN_TIMEOUT} ${DYNAMIC_QUERY_PARAMETER}"
        fi
        echoit "$CMD"
        diskspace
        echoit "Starting pquery (log stored in ${RUNDIR}/${TRIAL}/pquery.log)..."
        $CMD >> ${RUNDIR}/${TRIAL}/pquery.log 2>&1 &
        PQPID="$!"
      else  # PQUERY3!=1
        echoit "Taking ${MULTI_THREADED_TESTC_LINES} lines randomly from the SQL of this trial as testcase for this multi-threaded trial"
        shuf --random-source=<(${RANDOM_BIN} --raw) ${TRIAL_SQL} | head -n${MULTI_THREADED_TESTC_LINES} > ${RUNDIR}/${TRIAL}/${TRIAL}.sql
        PQUERY_INFILE_LINES="$(wc -l < ${RUNDIR}/${TRIAL}/${TRIAL}.sql)"  # pquery reads this chunk, not the whole trial SQL
        SQL_FILE="${RUNDIR}/${TRIAL}/${TRIAL}.sql"  # In contrast with single threaded runs, we want to save the input SQL file as it may be easier to reproduce from the original multi-threaded input SQL (which can be reduced and/or replayed in various ways including the multi* scripts as generated by startup.sh in BASEDIR's) than from the queries logged by pquery (per thread), though neither is a given. Reducer.sh will handle various scenario's as well depending on how it is setup per-reduction.
        if [[ "${MDG}" -eq 0 && "${GRP_RPL}" -eq 0 ]]; then
          echoit "Starting pquery (log stored in ${RUNDIR}/${TRIAL}/pquery.log)..."
          ${PQUERY_BIN} --infile=${SQL_FILE} --database=test --threads=${THREADS} --queries-per-thread=${QUERIES_PER_THREAD} --logdir=${RUNDIR}/${TRIAL} --log-all-queries --log-failed-queries --user=root --socket=${SOCKET} > ${RUNDIR}/${TRIAL}/pquery.log 2>&1 &
          PQPID="$!"
        else
          if [[ "${MDG_CLUSTER_RUN}" -eq 1 ]]; then
            cat ${MDG_CLUSTER_CONFIG} |
               sed "s|\/tmp|${RUNDIR}\/${TRIAL}|" |
               sed "s|\/home\/$(whoami)\/mariadb-qa|${SCRIPT_PWD}|" \
                 > ${RUNDIR}/${TRIAL}/pquery-cluster.cfg
            echoit "Starting pquery (log stored in ${RUNDIR}/${TRIAL}/pquery.log)..."
            ${PQUERY_BIN} --config-file=${RUNDIR}/${TRIAL}/pquery-cluster.cfg > ${RUNDIR}/${TRIAL}/pquery.log 2>&1 &
            PQPID="$!"
          else
            echoit "Starting pquery (log stored in ${RUNDIR}/${TRIAL}/pquery.log)..."
            ${PQUERY_BIN} --infile=${SQL_FILE} --database=test --threads=${THREADS} --queries-per-thread=${QUERIES_PER_THREAD} --logdir=${RUNDIR}/${TRIAL} --log-all-queries --log-failed-queries --user=root --socket=${SOCKET1} > ${RUNDIR}/${TRIAL}/pquery.log 2>&1 &
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
        if ! kill -0 ${PQPID} 2>/dev/null; then # pquery ended. kill -0 is an O(1) PID-exists probe; avoids ps -ef scan which stalls multi-seconds under high process count / high load
          break
        fi
        if [ ${CRASH_RECOVERY_TESTING} -eq 1 ]; then
          if [[ ${REPLICATION} -eq 1 ]]; then
            # Shutdown/kill servers for replication crash recovery testing before finishing pquery run
            if [ "${X}" -ge ${REPLICATION_SHUTDOWN_OR_KILL_TIMEOUT} ]; then
              if [[ ${REPLICATION_SHUTDOWN_OR_KILL} -eq 1 ]]; then
                # kill servers for replication crash recovery testing
                kill -9 ${MPID} > /dev/null 2>&1
                kill -9 ${SLAVE_MPID} > /dev/null 2>&1
                wait ${MPID}
                wait ${SLAVE_MPID}
              else
                # shutdown servers for replication crash recovery testing
                timeout --signal=9 35s ${BASEDIR}/bin/mysqladmin -uroot -S${SOCKET} shutdown > /dev/null 2>&1
                timeout --signal=9 35s ${BASEDIR}/bin/mysqladmin -uroot -S${SLAVE_SOCKET} shutdown > /dev/null 2>&1
              fi
              echoit "Killed for crash recovery testing (REPL)"
              echoit "Executing sync & 2 second sleep, this may take a while on busy servers"
              sync; sleep 2
              CRASH_CHECK=1
              break
            fi
          else
            if [ "${X}" -ge "$[ ${PQUERY_RUN_TIMEOUT} - ${CRASH_RECOVERY_KILL_BEFORE_END_SEC} ]" ]; then
              if [ "${MDG}" -eq 1 ]; then
                ps -ef | grep -e 'node1_socket\|node2_socket\|node3_socket' | grep -v grep | grep $RANDOMD | awk '{print $2}' | xargs kill -9 > /dev/null 2>&1
              else
                kill -9 ${MPID} > /dev/null 2>&1
                wait ${MPID}
              fi
              echoit "Killed for crash recovery testing"
              echoit "Executing sync & 2 second sleep, this may take a while on busy servers"
              sync; sleep 2
              CRASH_CHECK=1
              break
            fi
          fi
        fi
        # Initiate Percona Xtrabackup
        if [[ ${PXB_CRASH_RUN} -eq 1 ]]; then
          if [[ "${X}" -ge $PXB_INITIALIZE_BACKUP_SEC ]]; then
            $PXB_BASEDIR/bin/xtrabackup --user=root --password='' --backup --target-dir=${RUNDIR}/${TRIAL}/xb_full -S${SOCKET} --datadir=${RUNDIR}/${TRIAL}/data --lock-ddl > ${RUNDIR}/${TRIAL}/backup.log 2>&1
            $PXB_BASEDIR/bin/xtrabackup --prepare --target_dir=${RUNDIR}/${TRIAL}/xb_full --lock-ddl > ${RUNDIR}/${TRIAL}/prepare_backup.log 2>&1
            echoit "Backup completed"
            PXB_CHECK=1
            break
          fi
        fi
        if [ "${X}" -ge ${PQUERY_RUN_TIMEOUT} ]; then
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
    if [[ "${MDG}" -eq 0 && "${GRP_RPL}" -eq 0 ]]; then
      if [ "${QUERY_CORRECTNESS_TESTING}" -eq 1 ]; then
        echoit "Either the Primary server (PID: ${MPID} | Socket: ${SOCKET}), or the Secondary server (PID: ${MPID2} | Socket: ${RUNDIR}/${TRIAL}/socket2.sock) failed to start after ${MYSQLD_START_TIMEOUT} seconds. Will issue extra kill -9 to ensure it's gone..."
        (
          sleep 0.2
          kill -9 ${MPID2} > /dev/null 2>&1
          for X in $(seq 1 4); do kill -0 ${MPID2} 2>/dev/null || break; sleep 1; done  # see comment at the corresponding poll at end of this script for why this replaces `timeout … wait`
        ) &
        # Foonly idiom in main shell - bare wait consumes the SIGKILL exit so
        # bash never prints 'Killed' for MPID2. See KILLPID site for full notes.
        wait ${MPID2} 2>/dev/null
        for X in $(seq 1 5); do kill -0 ${MPID2} 2>/dev/null || break; sleep 1; done    # fallback if MPID2 wasn't reaped by wait (shouldn't happen - MPID2 is a direct child)
      else
        echoit "Server (PID: ${MPID} | Socket: ${SOCKET}) failed to start after ${MYSQLD_START_TIMEOUT} seconds. Will issue extra kill -9 to ensure it's gone..."
      fi
      (
        sleep 0.2
        kill -9 ${MPID} > /dev/null 2>&1
        for X in $(seq 1 4); do kill -0 ${MPID} 2>/dev/null || break; sleep 1; done  # see comment at the corresponding poll at end of this script for why this replaces `timeout … wait`
      ) &
      # Foonly idiom in main shell - bare wait consumes the SIGKILL exit so
      # bash never prints 'Killed' for MPID. See KILLPID site for full notes.
      wait ${MPID} 2>/dev/null
      for X in $(seq 1 5); do kill -0 ${MPID} 2>/dev/null || break; sleep 1; done    # fallback if MPID wasn't reaped by wait (shouldn't happen - MPID is a direct child)
      sleep 2
      sync
    elif [[ "${MDG}" -eq 1 ]]; then
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
  sleep 2 # Delay to ensure core was written completely (if any)
  # It takes SAN builds about 2 seconds to finish an 'LSAN detected' error log entry AFTER shutdown
  if [[ "${BASEDIR}" == *"SAN"* || "${BASEDIR}" == *"san"* || "${BASEDIR}" == *"San"* ]]; then
    sleep 3  # Correct. Must be >= 2.5
  else  # Rergular build
    sleep 1  # Finish core write etc (TBD if correct)
  fi
  # Process results
  # NOTE**: Do not kill PQPID here/before shutdown. The reason is that pquery may still be writing queries it's executing to the log. The only way to halt pquery correctly is by actually shutting down the server which will auto-terminate pquery due to 250 consecutive queries failing. If 250 queries failed and ${PQUERY_RUN_TIMEOUT}s timeout was reached, and if there is no core/Valgrind issue and there is no output of mariadb-qa/text_string.sh either (in case core dumps are not configured correctly, and thus no core file is generated, text_string.sh will still produce output in case the server crashed based on the information in the error log), then we do not need to save this trial (as it is a standard occurrence for this to happen). If however we saw 250 queries failed before the timeout was complete, then there may be another problem and the trial should be saved.
  # First check if we have a significant/major error. The scan + cleanup is centralised in error_log_scan.sh and is shared with pquery-prep-red.sh / pquery-del-trial.sh / pquery-results.sh.
  ERROR_LOG_SCAN=
  if [[ "${MDG}" -eq 1 ]]; then
    if [ -z "${MDG_NODE}" ]; then
      ERROR_LOG_SCAN="${RUNDIR}/${TRIAL}/node*.err"
    else
      ERROR_LOG_SCAN="${RUNDIR}/${TRIAL}/node${MDG_NODE}.err"
    fi
  else
    ERROR_LOG_SCAN=
    if [ -r ${RUNDIR}/${TRIAL}/log/master.err ]; then
      ERROR_LOG_SCAN="${RUNDIR}/${TRIAL}/log/master.err"
    fi
    if [ -r ${RUNDIR}/${TRIAL}/log/slave.err ]; then
      ERROR_LOG_SCAN="${ERROR_LOG_SCAN} ${RUNDIR}/${TRIAL}/log/slave.err"
    fi
  fi
  if [ ! -z "${ERROR_LOG_SCAN}" ] && ${SCRIPT_PWD}/error_log_scan.sh check ${ERROR_LOG_SCAN}; then  # error_log_scan.sh: unified REGEX_ERRORS_* scanner; see that script for the regex config & cleanup pipeline
    touch ${RUNDIR}/${TRIAL}/ERROR_LOG_SCAN_ISSUE  # Mark trial as containing an error log issue. pquery-prep-red.sh uses this (plus a known-bug check on the MYBUG UniqueID) to decide whether to override reducer TEXT with the cleaned error log bug from error_log_scan.sh.
    echoit "Error log bug found: \"$(${SCRIPT_PWD}/error_log_scan.sh top ${ERROR_LOG_SCAN} 2>/dev/null)\""
    savetrial
    TRIAL_SAVED=1
  fi
  ERROR_LOG_SCAN=
  # Now continue with main processing
  if [[ "${MDG}" -eq 0 && "${GRP_RPL}" -eq 0 ]]; then
    if [ "${VALGRIND_RUN}" == "1" ]; then # For Valgrind, we want the full Valgrind output in the error log, hence we need a proper/clean (and slow...) shutdown
      # Note that even if mysqladmin is killed with the 'timeout --signal=9', it will not affect the actual state of mysqld/mariadbd, all that was terminated was mysqladmin.
      # Thus, mysqld/mariadbd would (presumably) have received a shutdown signal (even if the timeout was 2 seconds it likely would have)
      timeout --signal=9 35s ${BASEDIR}/bin/mysqladmin -uroot -S${SOCKET} shutdown > /dev/null 2>&1 # Proper/clean shutdown attempt (up to 35 sec wait), necessary to get full Valgrind output in error log + see NOTE** above
      if [ $? -eq 137 ]; then
        if [ "${MARIADB_BINLOG_RECOVERY_TESTING}" -eq 1 ]; then
          echoit "mysqld/mariadbd failed to shutdown within 35 seconds for this trial. In regular runs this trial would be saved as a SHUTDOWN_TIMEOUT_ISSUE. However, as MariaDB binlog recovery testing is active (MARIADB_BINLOG_RECOVERY_TESTING=1), this trial is not saved here and instead kept for binlog recovery & table checksum compare instead. Initate a regular run to capture SHUTDOWN issues."
        elif [ -n "$(ls ${RUNDIR}/${TRIAL}/*/*core* 2>/dev/null)" ]; then
          echoit "mysqld/mariadbd did not shut down within 35 seconds AND a coredump is present: crash during shutdown (saved for Valgrind analysis)"
          # Note we are not checking for RR tracing here, as it is unlikely that Valgrind tracing + RR tracing is used at the same time
          savetrial
          TRIAL_SAVED=1
        else
          echoit "mysqld/mariadbd failed to shutdown within 35 seconds for this trial, saving it (pquery-results.sh will show these trials seperately)..."
          touch ${RUNDIR}/${TRIAL}/SHUTDOWN_TIMEOUT_ISSUE
          # Note we are not checking for RR tracing here, as it is unlikely that Valgrind tracing + RR tracing is used at the same time
          savetrial
          TRIAL_SAVED=1
        fi
      fi
      VALGRIND_SUMMARY_FOUND=0
      for X in $(# Wait for full Valgrind output in error log
        seq 0 600
      ); do
        sleep 1
        if [ ! -r ${RUNDIR}/${TRIAL}/log/master.err ]; then
          echoit "Assert: ${RUNDIR}/${TRIAL}/log/master.err not found during a Valgrind run. Please check. Trying to continue, but something is wrong already..."
          break
        elif egrep -qi "==[0-9]+== ERROR SUMMARY: [0-9]+ error" ${RUNDIR}/${TRIAL}/log/*.err; then # Summary found, Valgrind is done
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
        sleep 2 # <^ Make sure mysqld/mariadbd is gone
        echoit "Odd mysqld/mariadbd hang detected (binary did not terminate even after 600 seconds), saving this trial... "
        if [ ${TRIAL_SAVED} -eq 0 ]; then
          savetrial
          TRIAL_SAVED=1
        fi
      fi
    else
      if [ ${QUERY_CORRECTNESS_TESTING} -ne 1 ]; then
        # This shutdown in the main shutdown done for every standard/default options pquery trial
        TO_EXIT_CODE=
        SD_WAIT="${EPOCHREALTIME}"  # For the shutdown time reported below
        SD_LIMIT=35  # The shutdown window, which sets the bands the time is judged against
        if [ "${RR_TRACING}" == "1" ]; then
          SD_LIMIT=240
          timeout --signal=9 240s ${BASEDIR}/bin/mysqladmin -uroot -S${SOCKET} shutdown > /dev/null 2>&1 # Proper/clean shutdown attempt (up to 240 sec wait for rr) + see NOTE** above
          TO_EXIT_CODE=$?
        else
          timeout --signal=9 35s ${BASEDIR}/bin/mysqladmin -uroot -S${SOCKET} shutdown > /dev/null 2>&1 # Proper/clean shutdown attempt (up to 35 sec wait) + see NOTE** above
          TO_EXIT_CODE=$?
        fi
        if [ ${TO_EXIT_CODE} -ne 137 ]; then  # A timeout is reported by the paths below, so report the time only when the server did shut down
          SD_DUR="$(duration ${SD_WAIT})"
          echoit "Server shut down in ${SD_DUR}s" "$(duration_style ${SD_DUR} ${SD_LIMIT})"
          SD_DUR=
        fi
        SD_WAIT=; SD_LIMIT=
        if [ ${TO_EXIT_CODE} -eq 137 ]; then
          # 137 = mysqladmin was SIGKILLed at the shutdown timeout, i.e. shutdown did not complete.
          # This is a genuine shutdown hang ONLY when no coredump was produced. A crash during
          # shutdown (e.g. a thread-teardown SIGSEGV) also stalls shutdown but leaves a core. Wait
          # briefly for any in-progress core, then, if one is present, leave the trial for the main
          # detection block below (handle_bugs + ELIMINATE_KNOWN_BUGS) to classify - rather than
          # saving it blindly as a SHUTDOWN_TIMEOUT_ISSUE, which skips crash classification/filtering.
          for _CW in 1 2 3 4 5; do
            [ -n "$(ls ${RUNDIR}/${TRIAL}/*/*core* 2>/dev/null)" ] && break
            kill -0 ${MPID} 2>/dev/null || { sleep 1; break; }
            sleep 1
          done
          SHUTDOWN_CORE_PRESENT=0
          [ -n "$(ls ${RUNDIR}/${TRIAL}/*/*core* 2>/dev/null)" ] && SHUTDOWN_CORE_PRESENT=1
          if [ ${SHUTDOWN_CORE_PRESENT} -eq 0 ]; then
            if [ ${ISSTARTED} -eq 1 ]; then  # Only display a failed shutdown message if the server was correctly started to being with. We still try and do the shutdown above, "just in case" the server came up with a large delay
              if [ "${MARIADB_BINLOG_RECOVERY_TESTING}" -eq 1 ]; then
                echoit "mysqld/mariadbd failed to shutdown within 35 seconds for this trial. In regular runs this trial would be saved as a SHUTDOWN_TIMEOUT_ISSUE. However, as MariaDB binlog recovery testing is active (MARIADB_BINLOG_RECOVERY_TESTING=1), this trial is not saved here and instead kept for binlog recovery & table checksum compare instead. Initate a regular run to capture SHUTDOWN issues."
              else
                echoit "mysqld/mariadbd failed to shutdown within 35 seconds for this trial, saving it (pquery-results.sh will show these trials seperately)..."
                touch ${RUNDIR}/${TRIAL}/SHUTDOWN_TIMEOUT_ISSUE
              fi
            fi
          else
            echoit "mysqld/mariadbd did not shut down within 90 seconds AND a coredump is present: treating this as a crash (classified below), not a shutdown timeout"
          fi
          if [ "${RR_TRACING}" == "1" ]; then
            # If the rr trace is saved at this point, it would be marked as incomplete (./incomplete in mysqld-0/mariadbd-0)
            # To avoid this, we need to SIGABRT (kill -6) the tracee (mysqld/mariadbd) so that the rr trace can finish correctly
            echoit "RR Tracing is active, sending SIGABRT to tracee mysqld/mariadbd and providing time for RR trace to finish correctly"
            echo -n "$(cat ${RUNDIR}/${TRIAL}/pid.pid | xargs -I{} kill -6 {})"  # Hack, which works well
            sleep 3  # Default wait to allow RR to finish
            MAX_RR_WAIT=60; CUR_RR_WAIT=3;
            while [ -r ${RUNDIR}/${TRIAL}/rr/mysqld-0/incomplete -o -r ${RUNDIR}/${TRIAL}/rr/mariadbd-0/incomplete ]; do
              sleep 1
              CUR_RR_WAIT=$[ ${CUR_RR_WAIT} + 1 ]
              if [ ${CUR_RR_WAIT} -gt ${MAX_RR_WAIT} ]; then
                echoit "pquery-run waited ${CUR_RR_WAIT} seconds for the RR trace to finish correctly, but it did not complete within this time: terminating this trial, but the trace is highly likely to be incomplete"
                break
              fi
            done
            if [ ${CUR_RR_WAIT} -le ${MAX_RR_WAIT} ]; then
              echoit "RR completed successfully and the trace was saved in the rr/mysqld-0 or rr/mariadbd-0 directory inside the trial directory"
            fi
          fi
          if [ ${SHUTDOWN_CORE_PRESENT} -eq 0 ]; then  # genuine shutdown hang: save it here. A crash (core present) falls through to the main detection block for classification + filtering
            sleep 1
            savetrial
            TRIAL_SAVED=1
          fi
          SHUTDOWN_CORE_PRESENT=
        fi
        TO_EXIT_CODE=
        if [[ ${REPLICATION} -eq 1 ]]; then
          timeout --signal=9 35s ${BASEDIR}/bin/mysqladmin -uroot -S${SLAVE_SOCKET} shutdown > /dev/null 2>&1 # Proper/clean shutdown attempt (up to 35 sec wait), necessary to get full Valgrind output in error log + see NOTE** above
          if [ $? -eq 137 ]; then
            # Same hang-vs-crash rule as the master path above: a core present means the slave crashed during
            # shutdown; leave it for the main detection block to classify rather than saving as a shutdown timeout.
            for _CW in 1 2 3 4 5; do
              [ -n "$(ls ${RUNDIR}/${TRIAL}/*/*core* 2>/dev/null)" ] && break
              kill -0 ${SLAVE_MPID} 2>/dev/null || { sleep 1; break; }
              sleep 1
            done
            SHUTDOWN_CORE_PRESENT=0
            [ -n "$(ls ${RUNDIR}/${TRIAL}/*/*core* 2>/dev/null)" ] && SHUTDOWN_CORE_PRESENT=1
            if [ ${SHUTDOWN_CORE_PRESENT} -eq 0 ]; then
              if [ "${MARIADB_BINLOG_RECOVERY_TESTING}" -eq 1 ]; then
                echoit "mysqld/mariadbd failed to shutdown within 35 seconds for this trial. In regular runs this trial would be saved as a SHUTDOWN_TIMEOUT_ISSUE. However, as MariaDB binlog recovery testing is active (MARIADB_BINLOG_RECOVERY_TESTING=1), this trial is not saved here and instead kept for binlog recovery & table checksum compare instead. Initate a regular run to capture SHUTDOWN issues."
              else
                echoit "mysqld/mariadbd failed to shutdown within 35 seconds for this trial, saving it (pquery-results.sh will show these trials seperately)..."
                touch ${RUNDIR}/${TRIAL}/SHUTDOWN_TIMEOUT_ISSUE
              fi
            else
              echoit "slave mysqld/mariadbd did not shut down within 35 seconds AND a coredump is present: treating this as a crash (classified below), not a shutdown timeout"
            fi
            if [ "${RR_TRACING}" == "1" ]; then
              # If the rr trace is saved at this point, it would be marked as incomplete (./incomplete in mysqld-0 or mariadbd-0)
              # To avoid this, we need to SIGABRT (kill -6) the tracee (mysqld/mariadbd) so that the rr trace can finish correctly
              echoit "RR Tracing is active, sending SIGABRT to tracee mysqld/mariadbd and providing time for RR trace to finish correctly"
              kill -6 ${SLAVE_MPID}
              kill -6 $(ps -o ppid= -p ${SLAVE_MPID})  # Kill the PPID, which is more succesful than killing the PID of the server
              sleep 3  # Default wait to allow RR to finish
              MAX_RR_WAIT=60; CUR_RR_WAIT=3;
              while [ -r ${RUNDIR}/${TRIAL}/rr/mysqld-0/incomplete -o -r ${RUNDIR}/${TRIAL}/rr/mariadbd-0/incomplete ]; do
                sleep 1
                 CUR_RR_WAIT=$[ ${CUR_RR_WAIT} + 1 ]
                if [ ${CUR_RR_WAIT} -gt ${MAX_RR_WAIT} ]; then
                  echoit "pquery-run waited ${CUR_RR_WAIT} seconds for the RR trace to finish correctly, but it did not complete within this time: terminating this trial, but the trace is highly likely to be incomplete"
                  break
                fi
              done
              if [ ${CUR_RR_WAIT} -le ${MAX_RR_WAIT} ]; then
                echoit "RR completed successfully and the trace was saved in the rr/mysqld-0 or rr/mariadbd-0 directory inside the trial directory"
              fi
            fi
            if [ ${SHUTDOWN_CORE_PRESENT} -eq 0 ]; then  # genuine shutdown hang: save here. A crash (core present) falls through to the main detection block for classification + filtering
              sleep 1
              savetrial
              TRIAL_SAVED=1
            fi
            SHUTDOWN_CORE_PRESENT=
          fi
        fi
        sleep 2
      fi
    fi
    (
      sleep 0.2
      kill -9 ${MPID} ${SLAVE_MPID} > /dev/null 2>&1
      # Single 5s budget shared by both PIDs (matches the original `timeout 5s
      # wait MPID SLAVE_MPID` intent). Both are parent-shell children, so
      # subshell `wait` would error "not a child", and `timeout … wait` can't
      # run a shell builtin in any shell - so the prior form was a no-op.
      # After SIGKILL the kernel reaps in microseconds; the budget is rarely
      # consumed in practice.
      for X in $(seq 1 5); do
        STILL=0
        for P in ${MPID} ${SLAVE_MPID}; do
          [ -z "${P}" ] && continue
          kill -0 ${P} 2>/dev/null && STILL=1
        done
        [ ${STILL} -eq 0 ] && break
        sleep 1
      done
    ) # Terminate mysqld/mariadbd
    if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 ]; then
      (
        sleep 0.2
        kill -9 ${MPID2} > /dev/null 2>&1
        for X in $(seq 1 5); do kill -0 ${MPID2} 2>/dev/null || break; sleep 1; done  # see comment at the corresponding poll at end of this script for why this replaces `timeout … wait`
      ) # Terminate mysqld/mariadbd
      (
        sleep 0.2
        # Graceful first so the secondary-engine pquery's worker runs its
        # destructor + writeFinalReport (NODE SUMMARY line); then SIGKILL any
        # survivor. SIGTERM is sent to worker children (master noop-handles it
        # in fork-mode pquery; harmless on PQPID2 itself for older variants).
        if kill -0 ${PQPID2} 2>/dev/null; then
          WPIDS2=$(ps -o pid= --ppid ${PQPID2} 2>/dev/null | tr '\n' ' ')
          for WPID in ${WPIDS2} ${PQPID2}; do kill -SIGTERM ${WPID} 2>/dev/null; done
          for X in $(seq 1 5); do kill -0 ${PQPID2} 2>/dev/null || break; sleep 1; done
        fi
        kill -9 ${PQPID2} > /dev/null 2>&1
        # kill -0 poll instead of `wait` because PQPID2 is a child of the
        # parent shell, not this subshell; bash's `wait` returns 127 immediately
        # for non-children, which made the previous timeout-wait a no-op.
        for X in $(seq 1 5); do kill -0 ${PQPID2} 2>/dev/null || break; sleep 1; done
      ) # Terminate pquery (if it went past ${PQUERY_RUN_TIMEOUT} time, also see NOTE** above)
    fi
    sleep 1 # <^ Make sure all is gone
  elif [[ "${MDG}" -eq 1 || "${GRP_RPL}" -eq 1 ]]; then
    if [ "${VALGRIND_RUN}" == "1" ]; then # For Valgrind, we want the full Valgrind output in the error log, hence we need a proper/clean (and slow...) shutdown
      # Note that even if mysqladmin is killed with the 'timeout --signal=9', it will not affect the actual state of mysqld/mariadbd, all that was terminated was mysqladmin.
      # Thus, mysqld/mariadbd would (presumably) have received a shutdown signal (even if the timeout was 2 seconds it likely would have)
      # Proper/clean shutdown attempt (up to 20 sec wait), necessary to get full Valgrind output in error log
      timeout --signal=9 35s ${BASEDIR}/bin/mysqladmin -uroot -S${SOCKET3} shutdown > /dev/null 2>&1
      if [ $? -eq 137 ]; then
        if [ -n "$(ls ${RUNDIR}/${TRIAL}/node3/*core* 2>/dev/null)" ]; then
          echoit "mysqld/mariadbd for node3 did not shut down within 35 seconds AND a coredump is present: crash during shutdown (saved for Valgrind analysis)"
        else
          echoit "mysqld/mariadbd for node3 failed to shutdown within 35 seconds for this trial, saving it (pquery-results.sh will show these trials seperately)..."
          touch ${RUNDIR}/${TRIAL}/SHUTDOWN_TIMEOUT_ISSUE
        fi
        # Minor TODO: add RR provision for SHUTDOWN_TIMEOUT_ISSUEs seen under Valgrind (search for 'incomplete')
        sleep 1
        savetrial
        TRIAL_SAVED=1
      fi
      timeout --signal=9 35s ${BASEDIR}/bin/mysqladmin -uroot -S${SOCKET2} shutdown > /dev/null 2>&1
      if [ $? -eq 137 ]; then
        if [ -n "$(ls ${RUNDIR}/${TRIAL}/node2/*core* 2>/dev/null)" ]; then
          echoit "mysqld/mariadbd for node2 did not shut down within 35 seconds AND a coredump is present: crash during shutdown (saved for Valgrind analysis)"
        else
          echoit "mysqld/mariadbd for node2 failed to shutdown within 35 seconds for this trial, saving it (pquery-results.sh will show these trials seperately)..."
          touch ${RUNDIR}/${TRIAL}/SHUTDOWN_TIMEOUT_ISSUE
        fi
        sleep 1
        savetrial
        TRIAL_SAVED=1
      fi
      timeout --signal=9 35s ${BASEDIR}/bin/mysqladmin -uroot -S${SOCKET1} shutdown > /dev/null 2>&1
      if [ $? -eq 137 ]; then
        if [ -n "$(ls ${RUNDIR}/${TRIAL}/node1/*core* 2>/dev/null)" ]; then
          echoit "mysqld/mariadbd for node1 did not shut down within 35 seconds AND a coredump is present: crash during shutdown (saved for Valgrind analysis)"
        else
          echoit "mysqld/mariadbd for node1 failed to shutdown within 35 seconds for this trial, saving it (pquery-results.sh will show these trials seperately)..."
          touch ${RUNDIR}/${TRIAL}/SHUTDOWN_TIMEOUT_ISSUE
        fi
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
        sleep 1 # <^ Make sure mysqld/mariadbd is gone
        echoit "Odd mysqld/mariadbd hang detected (binary did not terminate even after 600 seconds), saving this trial... "
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
  # Ensure pquery has fully exited so its destructor wrote NODE SUMMARY into
  # *_general.log. pquery v2.1+ runs as a master + forked worker(s); the master
  # installs a no-op SIGTERM handler (pquery.cpp:pq_master_signal_noop) so it
  # keeps wait()-ing across signals, while the worker installs the graceful-stop
  # handler (node.cpp:pq_stop_handler) that flips g_stop_requested. So SIGTERM
  # must go to the worker child, not the master, to trigger writeFinalReport.
  # The master then exits on its own once wait() returns ECHILD. Without this,
  # non-crash save paths (e.g. error_log_scan flagging an InnoDB warning) leave
  # pquery alive until the next trial's process-cleanup SIGKILLs it, skipping
  # the destructor and losing the "pquery run details" line.
  for PQID in ${PQPID} ${PQPID2}; do
    [ -z "${PQID}" ] && continue
    if kill -0 ${PQID} 2>/dev/null; then
      WPIDS=$(ps -o pid= --ppid ${PQID} 2>/dev/null | tr '\n' ' ')
      for WPID in ${WPIDS} ${PQID}; do kill -SIGTERM ${WPID} 2>/dev/null; done  # PQID for older single-process variants; master noop-handles SIGTERM in fork variants so this is harmless
      for X in $(seq 1 5); do kill -0 ${PQID} 2>/dev/null || break; sleep 1; done
    fi
  done
  if [ ${ISSTARTED} -eq 1 ]; then  # Do not try and print pquery stats when mysqld/mariadbd failed to start
    FAILED_QUERIES_OUTPUT=
    if [ -d ${RUNDIR}/${TRIAL} ]; then
      FAILED_QUERIES_OUTPUT="$(grep -i 'SUMMARY.*queries failed' ${RUNDIR}/${TRIAL}/*.sql ${RUNDIR}/${TRIAL}/*.log 2>/dev/null | sed 's|.*:||;s|^[ \t]*||')"
    elif [ -d ${WORKDIR}/${TRIAL} ]; then
      FAILED_QUERIES_OUTPUT="$(grep -i 'SUMMARY.*queries failed' ${WORKDIR}/${TRIAL}/*.sql ${WORKDIR}/${TRIAL}/*.log 2>/dev/null | sed 's|.*:||;s|^[ \t]*||')"
    fi
    if [ ! -z "${FAILED_QUERIES_OUTPUT}" ]; then
      if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 ]; then
        echoit "Pri engine pquery run details: ${FAILED_QUERIES_OUTPUT}"
        # echoit "Sec engine pquery run details:"  # TODO: add sec engine result
      else
        echoit "pquery run details: ${FAILED_QUERIES_OUTPUT}"
      fi
      # How much of the input SQL the trial actually used. A small input against many executed queries means
      # the threads ran the same statements over and again, so the run covers less SQL than it could
      EXEC_TOTAL="$(echo "${FAILED_QUERIES_OUTPUT}" | grep --binary-files=text -om1 '[0-9]\+/[0-9]\+ queries failed' | sed 's|.*/||;s| .*||')"
      if [ -n "${EXEC_TOTAL}" ] && [ "${EXEC_TOTAL}" -gt 0 ] && [ "${PQUERY_INFILE_LINES:-0}" -gt 0 ]; then
        EXEC_RATIO="$(awk -v i=${PQUERY_INFILE_LINES} -v e=${EXEC_TOTAL} 'BEGIN{printf "%.2f", i*100/e}')"
        EXEC_COLOR="$(awk -v r=${EXEC_RATIO} 'BEGIN{print (r>=75)?"GREEN":((r>=35)?"ORANGE":"RED")}')"
        echoit "pquery input SQL vs runtime exec ratio: ${PQUERY_INFILE_LINES}/${EXEC_TOTAL}=${EXEC_RATIO}%" "${EXEC_COLOR}"
        EXEC_RATIO=; EXEC_COLOR=
      fi
      EXEC_TOTAL=
    fi
    FAILED_QUERIES_OUTPUT=
  fi
  # ======== MARIADB_BINLOG_RECOVERY_TESTING ========
  # Initiate binlog replay using mariadb-binlog  
  if [ "${MARIADB_BINLOG_RECOVERY_TESTING}" -eq 1 -a -d "${RUNDIR}/${TRIAL}" ]; then
    echoit "Binlog recovery testing: moving ${RUNDIR}/${TRIAL}/data to ${RUNDIR}/${TRIAL}/data.ORIGINAL"
    mv ${RUNDIR}/${TRIAL}/data ${RUNDIR}/${TRIAL}/data.ORIGINAL
    echoit "Binlog recovery testing: moving ${RUNDIR}/${TRIAL}/tmp to ${RUNDIR}/${TRIAL}/tmp.ORIGINAL"
    mv ${RUNDIR}/${TRIAL}/tmp ${RUNDIR}/${TRIAL}/tmp.ORIGINAL
    echoit "Binlog recovery testing: moving ${RUNDIR}/${TRIAL}/log to ${RUNDIR}/${TRIAL}/log.ORIGINAL"
    mv ${RUNDIR}/${TRIAL}/log ${RUNDIR}/${TRIAL}/log.ORIGINAL
    echoit "Binlog recovery testing: copying data dir template to ${RUNDIR}/${TRIAL}/data"
    mkdir -p ${RUNDIR}/${TRIAL}/data ${RUNDIR}/${TRIAL}/tmp ${RUNDIR}/${TRIAL}/log
    cp -R ${WORKDIR}/data.template/* ${RUNDIR}/${TRIAL}/data 2>&1
    echo "${MYEXTRA}" | if grep -qi "innodb[_-]log[_-]checksum[_-]algorithm"; then
      # Ensure that mysqld/mariadbd server startup will not fail due to a mismatched checksum algo between the original MID and the changed MYEXTRA options
      rm ${RUNDIR}/${TRIAL}/data/ib_log*
      rm ${RUNDIR}/${TRIAL}/data.ORIGINAL/ib_log*  # Note we are also pre-processing the original (data.ORIGINAL) instance here as it is brought back up for table checksums below (post the binlog recovery test)
    fi
    # Init new empty/clean instance based on the data template to test binlog recovery
    init_empty_port
    PORT=${NEWPORT}
    NEWPORT=
    rm -f "${SOCKET}"
    echoit "Binlog recovery testing: starting the binlog recovery instance. Error log: ${RUNDIR}/${TRIAL}/log/master.err"
    CMD="${BIN} ${MYSAFE} ${MYEXTRA} ${ENCRYPTION_OPTIONS} ${REPL_EXTRA} ${MASTER_EXTRA} --basedir=${BASEDIR} --datadir=${RUNDIR}/${TRIAL}/data --tmpdir=${RUNDIR}/${TRIAL}/tmp --core-file --port=$PORT --pid_file=${RUNDIR}/${TRIAL}/pid.pid --socket=${SOCKET} --log-output=none --log-error=${RUNDIR}/${TRIAL}/log/master.err"
    diskspace
    $CMD >> ${RUNDIR}/${TRIAL}/log/master.err 2>&1 & 
    MPID="$!"
    echoit "Binlog recovery testing: waiting for mysqld/mariadbd (pid: ${MPID}) to fully start..."
    for X in $(seq 0 ${MYSQLD_START_TIMEOUT}); do
      sleep 1
      if ${BASEDIR}/bin/mysqladmin -uroot -S${SOCKET} ping > /dev/null 2>&1; then  # Server up
        break
      fi
      if [ "${MPID}" == "" ]; then
        echoit "Assert! ${MPID} empty. Terminating!"
        exit 1
      fi
      if grep -qi "ERROR. Aborting" ${RUNDIR}/${TRIAL}/log/*.err; then
        if grep -qi "TCP.IP port.*Address already in use" ${RUNDIR}/${TRIAL}/log/*.err; then
          echoit "Assert! The text '[ERROR] Aborting' was found in the error log due to a IP port conflict (the port was already in use)"
          removetrial
        else
          if grep -qi "Can't initialize timers" ${RUNDIR}/${TRIAL}/log/*.err; then
            echoit "Error! '[ERROR] Aborting' was found in the error log, due to a 'Can't initialize timers' issue, ref https://jira.mariadb.org/browse/MDEV-22286, currently being researched. The run should be able to continue normally. Not saving trial."
            removetrial
          else
            echoit "Assert! '[ERROR] Aborting' was found in the error log. This is likely an issue with one of the \$MYEXTRA (or \$MYSAFE or \$ENCRYPTION_OPTIONS) startup parameters. Saving trial for further analysis, and dumping error log here for quick analysis. Please check the output against the \$MYEXTRA (or \$MYSAFE if it was modified) settings. You may also want to try setting \$MYEXTRA=\"${MYEXTRA}\" directly in start (as created by startup.sh using your base directory)."
            grep "ERROR" ${RUNDIR}/${TRIAL}/log/*.err | tee -a /${WORKDIR}/pquery-run.log
            if grep -qiE "error 28|out of disk space" ${RUNDIR}/${TRIAL}/log/*.err; then  # Likely OOS on /dev/shm
              echoit "Noticed a likely OOS on ${RUNDIR} or in /tmp or root (/). Removing trial to maximize space, and pausing 0.5 hour before trying again (reducer's may be running and consuming space)"
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
      fi
      # Break the wait-for-server-started loop if a core file is found. Handlin
      if [ $(ls -l ${RUNDIR}/${TRIAL}/*/*core* 2>/dev/null | wc -l) -ge 1 ]; then
        removetrial
        break
      fi 
    done
    # Check if binlog recovery instance is alive
    if ${BASEDIR}/bin/mysqladmin -uroot -S${SOCKET} ping > /dev/null 2>&1; then
      echoit "Binlog recovery testing: server started ok. Client: $(echo ${BIN} | sed 's|/mysqld|/mysql|;s|/mariadbd|/mariadb|') -uroot -S${SOCKET}"
      #${BASEDIR}/bin/mariadb -uroot -S${SOCKET} -e "CREATE DATABASE IF NOT EXISTS test;" > /dev/null 2>&1  # test db should be created by this call above (on the original run), and it should have been binlog-replicated
    fi
    echoit "Binlog recovery testing: attempting binlog recovery using mariadbd-binlog with the binlogs in ${RUNDIR}/${TRIAL}/data"
    if [ ! -x ${BASEDIR}/bin/mariadb-binlog ]; then
      echoit "Assert: ${BASEDIR}/bin/mariadb-binlog missing or not readable or not executable"
      exit 1
      break
    fi
    BINLOG_BASENAME="$(ls -1 ${RUNDIR}/${TRIAL}/data.ORIGINAL/*.idx | grep --binary-files=text -vi 'relay' | head -n1 | sed 's|.*/||;s|.idx||;s|[0]\+[0-9]\+|0*|')"
    # { cmd1 | cmd2 ; } >file 2>&1 - the brace group makes the redirect apply to BOTH ends of the pipeline, so mariadb-binlog's stderr (decode errors / "ERROR: ..." / "WARNING: ...") is captured alongside the mariadb client's stderr (replay "ERROR N at line ..."). A plain `cmd1 | cmd2 >file 2>&1` only captures cmd2's descriptors.
    echo "{ ${BASEDIR}/bin/mariadb-binlog \$(ls -1 ${RUNDIR}/${TRIAL}/data.ORIGINAL/${BINLOG_BASENAME} | grep -v idx | sort -n) | ${BASEDIR}/bin/mariadb -A -uroot -S${RUNDIR}/${TRIAL}/socket.sock --force --binary-mode test ; } >${RUNDIR}/${TRIAL}/binlog_recovery_result.txt 2>&1" > ${RUNDIR}/${TRIAL}/binlog_recovery_cmd.sh
    echo "# Reference command, indentical to the full used command in binlog_recovery_cmd.sh" > ${RUNDIR}/${TRIAL}/local_binlog_recovery
    echo "# For manual use in /test/MD..." >> ${RUNDIR}/${TRIAL}/local_binlog_recovery
    echo "cp ${WORKDIR}/${TRIAL}/${BINLOG_BASENAME} ." >> ${RUNDIR}/${TRIAL}/local_binlog_recovery
    echo "./all_no_cl ${MYEXTRA}" >> ${RUNDIR}/${TRIAL}/local_binlog_recovery
    echo "{ ./bin/mariadb-binlog \$(ls -1 ./${BINLOG_BASENAME} | grep -v idx | sort -n) | ./bin/mariadb -A -uroot -Ssocket.sock --force --binary-mode test ; } 2>&1" >> ${RUNDIR}/${TRIAL}/local_binlog_recovery
    chmod +x ${RUNDIR}/${TRIAL}/binlog_recovery_cmd.sh
    ${RUNDIR}/${TRIAL}/binlog_recovery_cmd.sh
    chmod -x ${RUNDIR}/${TRIAL}/binlog_recovery_cmd.sh  # There will be no need to re-run it manually
    BINLOG_BASENAME=
    # BINLOG_RECOVERY_ERROR_REGEX matches real error/warning lines from the mariadb client and from mariadb-binlog:
    #   - "ERROR 1234 (HY000) at line N: ..."   (mariadb client, replay errors)
    #   - "ERROR: ..."                          (mariadb-binlog, decode errors)
    #   - "WARNING: ..."                        (mariadb-binlog, decode warnings)
    # Avoids matching the substring "error" inside informational text, sysvar names, or base64 BINLOG payloads.
    BINLOG_RECOVERY_ERROR_REGEX='^ERROR [0-9]+|^ERROR:|^WARNING:'
    if grep --binary-files=text -qE "${BINLOG_RECOVERY_ERROR_REGEX}" ${RUNDIR}/${TRIAL}/binlog_recovery_result.txt; then
      # Marker file content: prefer mariadb client errors (`^ERROR [0-9]+ ... at line N: ...`) since they carry SQLSTATE + line offset and are more diagnostic; fall back to mariadb-binlog decode errors (`^ERROR:`/`^WARNING:`) only if no client errors present. Downstream consumers (new_text_string.sh, pquery-prep-red.sh, pquery-results.sh) read from this file.
      if grep --binary-files=text -qE '^ERROR [0-9]+' ${RUNDIR}/${TRIAL}/binlog_recovery_result.txt; then
        grep --binary-files=text -E '^ERROR [0-9]+' ${RUNDIR}/${TRIAL}/binlog_recovery_result.txt | head -n10 > ${RUNDIR}/${TRIAL}/BINLOG_RECOVERY_ERROR
      else
        grep --binary-files=text -E '^ERROR:|^WARNING:' ${RUNDIR}/${TRIAL}/binlog_recovery_result.txt | head -n10 > ${RUNDIR}/${TRIAL}/BINLOG_RECOVERY_ERROR
      fi
      echoit "Binlog recovery testing: FOUND issue during binlog recovery testing (max 10 shown):"
      cat ${RUNDIR}/${TRIAL}/BINLOG_RECOVERY_ERROR | tee -a /${WORKDIR}/pquery-run.log
      savetrial
      TRIAL_SAVED=1
      # Now that we have mariadb-binlog test completion, we can kill this recovery instance. If instead the trial is not saved here, due to succesful here binlog replay, the server will stay up and table checksums will be taken just below. After that the instance is terminated there
      echoit "Binlog recovery testing: terminating post-binlog recovery instance"
      (
        sleep 0.2
        kill -9 ${MPID} > /dev/null 2>&1
        for X in $(seq 1 5); do kill -0 ${MPID} 2>/dev/null || break; sleep 1; done  # see comment at the corresponding poll at end of this script for why this replaces `timeout … wait`
      ) # Terminate mysqld/mariadbd
    else
      echoit "Binlog recovery testing: NO issue found during binlog recovery testing"
    fi
    if [ "${TRIAL_SAVED}" != "1" ]; then  # Only check table checksums if binlog recovery succeeded (otherwise trial was saved and moved already)
      echoit "Binlog recovery testing: generating db tables checksum SQL for the post-binlog recovery instance"
      ${BASEDIR}/bin/mariadb -A -uroot -S${SOCKET} --force --binary-mode -e "SELECT CONCAT('CHECKSUM TABLE \`test\`.\`', REPLACE(table_name, '\`', '\`\`'), '\`;') FROM information_schema.tables;" | grep --binary-files=text -v 'CONCAT' > ${RUNDIR}/${TRIAL}/checksumlist2.sql
      echoit "Binlog recovery testing: running db tables checksum SQL for the post-binlog recovery instance"
      ${BASEDIR}/bin/mariadb -A -uroot -S${SOCKET} --force --binary-mode < ${RUNDIR}/${TRIAL}/checksumlist2.sql > ${RUNDIR}/${TRIAL}/checksumlist_result2.txt
      # Now that we have mariadb-binlog test completion & checksums for the recovery instance, we can kill this instance
      echoit "Binlog recovery testing: terminating post-binlog recovery instance"
      (
        sleep 0.2
        kill -9 ${MPID} > /dev/null 2>&1
        for X in $(seq 1 5); do kill -0 ${MPID} 2>/dev/null || break; sleep 1; done  # see comment at the corresponding poll at end of this script for why this replaces `timeout … wait`
      ) # Terminate mysqld/mariadbd
      # Re-init the original instance to obtain table checksums
      init_empty_port
      PORT=${NEWPORT}
      NEWPORT=
      rm -f "${SOCKET}"
      echoit "Binlog recovery testing: correcting missing user/GRANT privileges on the original instance about to be re-started by copying various recover files from the original template. Also fixing potential mysql.host issues"
      for CFILES in columns_priv global_priv procs_priv proxies_priv tables_priv db user roles_mapping proc func help time_zone plugin event servers; do
        cp ${WORKDIR}/data.template/mysql/${CFILES}* ${RUNDIR}/${TRIAL}/data.ORIGINAL/mysql 2>&1
      done
      rm ${RUNDIR}/${TRIAL}/data.ORIGINAL/mysql/host.* 2>/dev/null # Avoids '[ERROR] mariadbd: Fatal error: mysql.host table is damaged or in unsupported 3.20 format' if present
      echoit "Binlog recovery testing: re-starting the original instance. Error log (added unto): ${RUNDIR}/${TRIAL}/log.ORIGINAL/master.err"
      CMD="${BIN} ${MYSAFE} ${MYEXTRA} ${ENCRYPTION_OPTIONS} ${REPL_EXTRA} ${MASTER_EXTRA} --basedir=${BASEDIR} --datadir=${RUNDIR}/${TRIAL}/data.ORIGINAL --tmpdir=${RUNDIR}/${TRIAL}/tmp.ORIGINAL --core-file --port=$PORT --pid_file=${RUNDIR}/${TRIAL}/pid.pid --socket=${SOCKET} --log-output=none --log-error=${RUNDIR}/${TRIAL}/log.ORIGINAL/master.err"
      diskspace
      $CMD >> ${RUNDIR}/${TRIAL}/log.ORIGINAL/master.err 2>&1 & 
      MPID="$!"
      echoit "Binlog recovery testing: waiting for mysqld/mariadbd (pid: ${MPID}) to fully start..."
      for X in $(seq 0 ${MYSQLD_START_TIMEOUT}); do
        sleep 1
        if ${BASEDIR}/bin/mysqladmin -uroot -S${SOCKET} ping > /dev/null 2>&1; then  # Server up
          break
        fi
         if [ "${MPID}" == "" ]; then
          echoit "Assert! ${MPID} empty. Terminating!"
          exit 1
        fi
        if grep -qi "ERROR. Aborting" ${RUNDIR}/${TRIAL}/log.ORIGINAL/*.err; then
          if grep -qi "TCP.IP port.*Address already in use" ${RUNDIR}/${TRIAL}/log.ORIGINAL/*.err; then
            echoit "Assert! The text '[ERROR] Aborting' was found in the error log due to a IP port conflict (the port was already in use)"
            removetrial
          else
            if grep -qi "Can't initialize timers" ${RUNDIR}/${TRIAL}/log.ORIGINAL/*.err; then
              echoit "Error! '[ERROR] Aborting' was found in the error log, due to a 'Can't initialize timers' issue, ref https://jira.mariadb.org/browse/MDEV-22286, currently being researched. The run should be able to continue normally. Not saving trial."
              removetrial
            else
              echoit "Assert! '[ERROR] Aborting' was found in the error log. This is likely an issue with one of the \$MYEXTRA (or \$MYSAFE or \$ENCRYPTION_OPTIONS) startup parameters. Saving trial for further analysis, and dumping error log here for quick analysis. Please check the output against the \$MYEXTRA (or \$MYSAFE if it was modified) settings. You may also want to try setting \$MYEXTRA=\"${MYEXTRA}\" directly in start (as created by startup.sh using your base directory)."
              grep "ERROR" ${RUNDIR}/${TRIAL}/log.ORIGINAL/*.err | tee -a /${WORKDIR}/pquery-run.log
              if grep -qiE "error 28|out of disk space" ${RUNDIR}/${TRIAL}/log.ORIGINAL/*.err; then  # Likely OOS on /dev/shm
                echoit "Noticed a likely OOS on ${RUNDIR} or in /tmp or root (/). Removing trial to maximize space, and pausing 0.5 hour before trying again (reducer's may be running and consuming space)"
                removetrial
                sleep 1800
                echoit "Slept 0.5h, resuming pquery-run.sh run..."
              else
                savetrial
                echoit "Remember to cleanup/delete the rundir:  rm -Rf ${RUNDIR}"
                #exit 1  # we do not want to exit here; failures on some re-started trials are to be expected [*A]
              fi
            fi
          fi
        fi
        # Break the wait-for-server-started loop if a SECONDARY core file is found. TODO: this is not perfect. If the original instance did not crash, but the 2nd start up of the same instance (i.e. same data dir etc) does, there will be only one core. Current impact; minor: it just means that MYSQLD_START_TIMEOUT has to be reached before the process continues, and the expected frequency is low to start with. Another option is to delete any existing cores. For just 'MARIADB_BINLOG_RECOVERY_TESTING' this may be ok, but it's not ideal for combined runs (and then the status quo is better)
        if [ $(ls -l ${RUNDIR}/${TRIAL}/*/*core* 2>/dev/null | wc -l) -ge 2 ]; then
          removetrial  # We can remove the trial if the re-started server startup fails, as we won't be able to take checksums AND we already had a correct binlog replay (otherwise this code would not have been reached)
          break
        fi 
      done
      # Check if mysqld/mariadbd is alive
      if ${BASEDIR}/bin/mysqladmin -uroot -S${SOCKET} ping > /dev/null 2>&1; then
        echoit "Binlog recovery testing: original instance re-started ok. Client: $(echo ${BIN} | sed 's|/mysqld|/mysql|;s|/mariadbd|/mariadb|') -uroot -S${SOCKET}"
        #${BASEDIR}/bin/mariadb -uroot -S${SOCKET} -e "CREATE DATABASE IF NOT EXISTS test;" > /dev/null 2>&1  # test db should be created by this call above (on the original run), and it should have been binlog-replicated
      fi
      echoit "Binlog recovery testing: generating db tables checksum SQL for the re-started original instance"
      ${BASEDIR}/bin/mariadb -A -uroot -S${SOCKET} --force --binary-mode -e "SELECT CONCAT('CHECKSUM TABLE \`test\`.\`', REPLACE(table_name, '\`', '\`\`'), '\`;') FROM information_schema.tables;" | grep --binary-files=text -v 'CONCAT' > ${RUNDIR}/${TRIAL}/checksumlist1.sql
      echoit "Binlog recovery testing: running db tables checksum SQL for the re-started original instance"
      ${BASEDIR}/bin/mariadb -A -uroot -S${SOCKET} --force --binary-mode < ${RUNDIR}/${TRIAL}/checksumlist1.sql > ${RUNDIR}/${TRIAL}/checksumlist_result1.txt
      # Ensure indentical orders
      sort ${RUNDIR}/${TRIAL}/checksumlist_result1.txt -o ${RUNDIR}/${TRIAL}/checksumlist_result1.txt
      sort ${RUNDIR}/${TRIAL}/checksumlist_result2.txt -o ${RUNDIR}/${TRIAL}/checksumlist_result2.txt
      if ! diff -dq ${RUNDIR}/${TRIAL}/checksumlist_result1.txt ${RUNDIR}/${TRIAL}/checksumlist_result2.txt >/dev/null 2>&1; then
        # Marker file content: the first 10 diff lines. Downstream consumers (new_text_string.sh, pquery-prep-red.sh, pquery-results.sh) read from this file.
        # diff -d (default ed-style) so each differing line is prefixed with '< ' or '> '; grep '^[<>]' captures both deletions, additions, and the "same row, different value" case (which diff -dy formats with '|' and which the previous grep '<|>' filter silently missed).
        echo "diff -d ${RUNDIR}/${TRIAL}/checksumlist_result1.txt ${RUNDIR}/${TRIAL}/checksumlist_result2.txt | grep --binary-files=text -vE 'Table.*Checksum' | grep --binary-files=text -E '^[<>]'" > ${RUNDIR}/${TRIAL}/checksumlist_result_diff.sh
        chmod +x ${RUNDIR}/${TRIAL}/checksumlist_result_diff.sh
        ${RUNDIR}/${TRIAL}/checksumlist_result_diff.sh | head -n10 > ${RUNDIR}/${TRIAL}/BINLOG_CHECKSUM_DIFF
        echoit "Binlog recovery testing: FOUND table checksum difference(s) between the original re-started and binlog replay instances (max 10 shown):"
        cat ${RUNDIR}/${TRIAL}/BINLOG_CHECKSUM_DIFF | tee -a /${WORKDIR}/pquery-run.log
        savetrial
        TRIAL_SAVED=1
      else
        echoit "Binlog recovery testing: NO table checksum difference(s) between the original re-started and binlog replay instances were found"
      fi
      # Now that we have the checksums from the original instance (data.ORIGINAL), we can kill this instance
      echoit "Binlog recovery testing: terminating the re-started original instance"
      (
        sleep 0.2
        kill -9 ${MPID} > /dev/null 2>&1
        for X in $(seq 1 5); do kill -0 ${MPID} 2>/dev/null || break; sleep 1; done  # see comment at the corresponding poll at end of this script for why this replaces `timeout … wait`
      ) # Terminate mysqld/mariadbd
      rm -f "${SOCKET}"
    fi
  elif [ "${MARIADB_BINLOG_RECOVERY_TESTING}" -eq 1 -a ! -d "${RUNDIR}/${TRIAL}" ]; then
    echoit "MariaDB binlog recovery testing is enabled (MARIADB_BINLOG_RECOVERY_TESTING=1) however the trial dir (${RUNDIR}/${TRIAL}) is missing. Check messages above for cause and fix"  # TODO, as per output
  fi
  # ======== /MARIADB_BINLOG_RECOVERY_TESTING ========
  if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 -a $(ls -l ${RUNDIR}/${TRIAL}/*/*core* 2>/dev/null | wc -l) -eq 0 ]; then # If a core is found when query correctness testing is in progress, it will process it as a normal crash (without considering query correctness)
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
      VALGRIND_CHECK_1=$(grep "==[0-9]\+== ERROR SUMMARY: [0-9]\+ error" ${RUNDIR}/${TRIAL}/log/*.err 2>/dev/null | sed 's|.*ERROR SUMMARY: \([0-9]\+\) error.*|\1|')
      if [ "${VALGRIND_CHECK_1}" == "" ]; then VALGRIND_CHECK_1=0; fi
      if [ ${VALGRIND_CHECK_1} -gt 0 ]; then
        VALGRIND_ERRORS_FOUND=1
      fi
      if egrep -qi "^[ \t]*==[0-9]+[= \t]+[atby]+[ \t]*0x" ${RUNDIR}/${TRIAL}/log/*.err 2>/dev/null; then
        VALGRIND_ERRORS_FOUND=1
      fi
      if egrep -qi "==[0-9]+== ERROR SUMMARY: [1-9]" ${RUNDIR}/${TRIAL}/log/*.err 2>/dev/null; then
        VALGRIND_ERRORS_FOUND=1
      fi
      if [ ${VALGRIND_ERRORS_FOUND} -eq 1 ]; then
        VALGRIND_TEXT=$(${SCRIPT_PWD}/valgrind_string.sh ${RUNDIR}/${TRIAL}/log/master.err)
        VALGRIND_TEXT_S=$(${SCRIPT_PWD}/valgrind_string.sh ${RUNDIR}/${TRIAL}/log/slave.err)
        echoit "Valgrind error(s) detected: ${VALGRIND_TEXT} ${VALGRIND_TEXT_S}"
        if [ ${TRIAL_SAVED} -eq 0 ]; then
          savetrial
          TRIAL_SAVED=1
        fi
      else
        # Report that no Valgrind errors were found & include ERROR SUMMARY from error log
        echoit "No Valgrind errors detected. $(grep "==[0-9]\+== ERROR SUMMARY: [0-9]\+ error" ${RUNDIR}/${TRIAL}/log/*.err 2>/dev/null | sed 's|.*ERROR S|ERROR S|')"
      fi
    fi
    # If there are *SAN bugs, delete any known ones from the top of the error log(s)...
    if [ "${SAN_KNOWN_BUGS_DROPPED_FROM_ERROR_LOG_FLAG}" != "1" ]; then
      if grep --binary-files=text -qiE "=ERROR:|runtime error:|AddressSanitizer:|ThreadSanitizer:|LeakSanitizer:|MemorySanitizer:" ${RUNDIR}/${TRIAL}/log/*.err ${RUNDIR}/${TRIAL}/node*/node*.err 2>/dev/null; then
        SAN_KNOWN_BUGS_DROPPED_FROM_ERROR_LOG_FLAG=1
        echoit "Dropping any known *SAN bugs from the top of the error log for trial ${TRIAL}, if any"  # Note that reducer.sh matches this behavior when a TOP_SAN_ISSUES_REMOVED flag file is present for the trial, and drop_one_or_more_san_from_log.sh will create this flag when a pquery-run.sh based trial (like here) was found, and only writes this flag file if it has removed top level known issue(s)/bug(s)
        CUR_PWD_TMP="${PWD}"
        cd "${RUNDIR}/${TRIAL}"
        ${SCRIPT_PWD}/drop_one_or_more_san_from_log.sh  # Do not add any options to this script call as that will cause the top SAN issue to be deleted, irrespective of whetter an issue is known or not
        cd "${CUR_PWD_TMP}"
        CUR_PWD_TMP=
      fi
    fi
    # ...If any "=ERROR:|runtime error:|AddressSanitizer:|ThreadSanitizer:|LeakSanitizer:|MemorySanitizer:" mentions (checked in the long if/elif/elif... below) remain, it thus means that those issues are new and should be saved
    if [ ${TRIAL_SAVED} -eq 0 ]; then
      TRIAL_TO_SAVE=0
      # Checking for a core has to always come before all other checks; If there is a core, there is the possibility of gaining a unique bug identifier using new_text.string.sh.
      # The /*/ in the /*/*core* core search pattern is for to the /node1/ dir setup for cluster runs
      # TODO: verify if this means that /data/ is completely replaced by /node1/ at the same level
      # It is important in the below calls of fallback_text_string.sh that stderr is null redirected to avoid errors (for example Galera node3 error log not found) from presenting as non-empty outcomes
      if [ "$(ls -l ${RUNDIR}/${TRIAL}/*/*core* 2>/dev/null | wc -l)" -ge 1 -o "$(${SCRIPT_PWD}/fallback_text_string.sh ${RUNDIR}/${TRIAL}/log/master.err 2>/dev/null)" != "" -o "$(${SCRIPT_PWD}/fallback_text_string.sh ${RUNDIR}/${TRIAL}/log/slave.err 2>/dev/null)" != "" -o "$(${SCRIPT_PWD}/fallback_text_string.sh ${RUNDIR}/${TRIAL}/node1/node1.err 2>/dev/null)" != "" -o "$(${SCRIPT_PWD}/fallback_text_string.sh ${RUNDIR}/${TRIAL}/node2/node2.err 2>/dev/null)" != "" -o "$(${SCRIPT_PWD}/fallback_text_string.sh ${RUNDIR}/${TRIAL}/node3/node3.err 2>/dev/null)" != "" ]; then
        TRIAL_TO_SAVE=1  # A bug was definitely discovered (core presence or fallback_text_string.sh produced output) so we always need to save the trial. The reason this is set is for all cases where handle_bugs (which sets TRIAL_TO_SAVE=1) is not called, yet there is a bug present (i.e. fallback_text_string.sh produced output)
        if [ $(ls -l ${RUNDIR}/${TRIAL}/*/*core* 2>/dev/null | wc -l) -ge 1 ]; then
          if [[ "${MDG}" -eq 1 ]]; then
            for j in $(seq 1 ${NR_OF_NODES}); do
              if [ $(ls -l ${RUNDIR}/${TRIAL}/node${j}/*core* 2>/dev/null | wc -l) -ge 1 ]; then
                export GALERA_ERROR_LOG=${RUNDIR}/${TRIAL}/node${j}/node${j}.err
                export GALERA_CORE_LOC=$(ls -t ${RUNDIR}/${TRIAL}/node${j}/*core* 2>/dev/null)
                export node=node${j}
                echoit "mysqld/mariadbd coredump detected at $(ls ${RUNDIR}/${TRIAL}/node${j}/*core* 2>/dev/null)"
                handle_bugs
              fi
            done
          else
            echoit "mysqld/mariadbd coredump detected at $(ls ${RUNDIR}/${TRIAL}/*/*core* 2>/dev/null)"
            handle_bugs
          fi
        else
          echoit "No core present, but another issue was found in the error log by fallback_text_string.sh"
          handle_bugs
        fi
        # -- Output only (no actual functionality except output)
        if [[ "${MDG}" -eq 0 && "${GRP_RPL}" -eq 0 && -r ${WORKDIR}/${TRIAL}/log/slave.err && "$(${SCRIPT_PWD}/fallback_text_string.sh ${RUNDIR}/${TRIAL}/log/slave.err 2>/dev/null)" != "" ]]; then
          echoit "Bug found (as per slave error log)(as per fallback_text_string.sh): $(${SCRIPT_PWD}/fallback_text_string.sh ${WORKDIR}/${TRIAL}/log/slave.err)"
        elif [[ "${MDG}" -eq 0 && "${GRP_RPL}" -eq 0 && -r ${WORKDIR}/${TRIAL}/log/master.err ]]; then
          echoit "Bug found (as per error log)(as per fallback_text_string.sh): $(${SCRIPT_PWD}/fallback_text_string.sh ${WORKDIR}/${TRIAL}/log/master.err)"
        elif [[ "${MDG}" -eq 1 || "${GRP_RPL}" -eq 1 && -r ${WORKDIR}/${TRIAL}/node1/node1.err ]]; then
          if [ "$(${SCRIPT_PWD}/fallback_text_string.sh ${WORKDIR}/${TRIAL}/node1/node1.err 2>/dev/null)" != "" ]; then echoit "Bug found in MDG/GR node #1 (as per error log)(as per fallback_text_string.sh): $(${SCRIPT_PWD}/fallback_text_string.sh ${RUNDIR}/${TRIAL}/node1/node1.err)"; fi
          if [ "$(${SCRIPT_PWD}/fallback_text_string.sh ${WORKDIR}/${TRIAL}/node2/node2.err 2>/dev/null)" != "" ]; then echoit "Bug found in MDG/GR node #2 (as per error log)(as per fallback_text_string.sh): $(${SCRIPT_PWD}/fallback_text_string.sh ${RUNDIR}/${TRIAL}/node2/node2.err)"; fi
          if [ "$(${SCRIPT_PWD}/fallback_text_string.sh ${WORKDIR}/${TRIAL}/node3/node3.err 2>/dev/null)" != "" ]; then echoit "Bug found in MDG/GR node #3 (as per error log)(as per fallback_text_string.sh): $(${SCRIPT_PWD}/fallback_text_string.sh ${RUNDIR}/${TRIAL}/node3/node3.err)"; fi
        # -- /Output only
        fi
        if [ ${TRIAL_TO_SAVE} -eq 1 ]; then
          savetrial
          TRIAL_SAVED=1
        fi
      elif [ $(grep "SIGKILL myself" ${RUNDIR}/${TRIAL}/log/*.err 2>/dev/null | wc -l) -ge 1 ]; then
        echoit "'SIGKILL myself' detected in a mysqld/mariadbd error log for this trial; saving this trial"
        savetrial
        TRIAL_SAVED=1
      elif [[ ${CRASH_CHECK} -eq 1 ]]; then
        echoit "Saving this trial for backup restore analysis"
        savetrial
        TRIAL_SAVED=1
        CRASH_CHECK=0
      elif [ $(grep "MySQL server has gone away" ${RUNDIR}/${TRIAL}/*.sql 2>/dev/null | wc -l) -ge 200 -a ${TIMEOUT_REACHED} -eq 0 ]; then
        echoit "'MySQL server has gone away' detected >=200 times for this trial, and the pquery timeout was not reached; saving this trial for further analysis"
        savetrial
        TRIAL_SAVED=1
      # The various *SAN check below assume that any pre-existing/known *SAN issues have already been dropped from the log. Ref the provision for this before the first 'if' in this longer if/elif/elif...
      elif [ $(grep -im1 --binary-files=text "=ERROR:" ${RUNDIR}/${TRIAL}/log/*.err ${RUNDIR}/${TRIAL}/node*/node*.err 2>/dev/null | wc -l) -ge 1 ]; then
        echoit "Uknown/new ASAN issue detected in the mysqld/mariadbd error log for this trial; saving this trial"
        savetrial
        TRIAL_SAVED=1
      elif [ $(grep -im1 --binary-files=text "runtime error:" ${RUNDIR}/${TRIAL}/log/*.err ${RUNDIR}/${TRIAL}/node*/node*.err 2>/dev/null | wc -l) -ge 1 ]; then
        echoit "Uknown/new UBSAN issue detected in the mysqld/mariadbd error log for this trial; saving this trial"
        savetrial
        TRIAL_SAVED=1
      elif [ $(grep -im1 --binary-files=text "AddressSanitizer:" ${RUNDIR}/${TRIAL}/log/*.err ${RUNDIR}/${TRIAL}/node*/node*.err 2>/dev/null | wc -l) -ge 1 ]; then
        echoit "Uknown/new ASAN issue detected in the mysqld/mariadbd error log for this trial; saving this trial"
        savetrial
        TRIAL_SAVED=1
      elif [ $(grep -im1 --binary-files=text "ThreadSanitizer:" ${RUNDIR}/${TRIAL}/log/*.err ${RUNDIR}/${TRIAL}/node*/node*.err 2>/dev/null | wc -l) -ge 1 ]; then
        echoit "Uknown/new TSAN issue detected in the mysqld/mariadbd error log for this trial; saving this trial"
        savetrial
        TRIAL_SAVED=1
      elif [ $(grep -im1 --binary-files=text "LeakSanitizer:" ${RUNDIR}/${TRIAL}/log/*.err ${RUNDIR}/${TRIAL}/node*/node*.err 2>/dev/null | wc -l) -ge 1 ]; then
        echoit "Uknown/new LSAN issue detected in the mysqld/mariadbd error log for this trial; saving this trial"
        savetrial
        TRIAL_SAVED=1
      elif [ $(grep -im1 --binary-files=text "MemorySanitizer:" ${RUNDIR}/${TRIAL}/log/*.err ${RUNDIR}/${TRIAL}/node*/node*.err 2>/dev/null | wc -l) -ge 1 ]; then
        echoit "Uknown/new MSAN issue detected in the mysqld/mariadbd error log for this trial; saving this trial"
        savetrial
        TRIAL_SAVED=1
      elif [ ${SAVE_TRIALS_WITH_BUGS_ONLY} -eq 0 ]; then
        echoit "Saving full trial outcome (as SAVE_TRIALS_WITH_BUGS_ONLY=0 and so trials are saved irrespective of whether an issue was detected or not)"
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
              echoit "Nothing to save (SAVE_TRIALS_WITH_BUGS_ONLY=1 and no issue was seen), except the SQL trace (SAVE_SQL=1)"
            fi
          else
            echoit "Nothing to save (SAVE_TRIALS_WITH_BUGS_ONLY=1 and no issue was seen), except the SQL trace (SAVE_SQL=1)"
          fi
          savesql
        else
          if [ "${VALGRIND_RUN}" == "1" ]; then
            if [ ${VALGRIND_ERRORS_FOUND} -ne 1 ]; then
              echoit "Nothing to save (SAVE_TRIALS_WITH_BUGS_ONLY=1, SAVE_SQL=0, and no issue was seen)"
            fi
          else
            echoit "Nothing to save (SAVE_TRIALS_WITH_BUGS_ONLY=1, SAVE_SQL=0, and no issue was seen)"
          fi
        fi
      fi
    fi
    if [ ${TRIAL_SAVED} -eq 0 ]; then
      removetrial
    fi
  fi
  # The generated pools are rewritten at the start of every trial, so the copy from this trial is of no
  # further use. Delete it so it does not linger in-tree under generatorcpp/ or revgen/. The exit-time
  # rm still covers an interrupted run.
  if [ ${USE_GENERATOR} -eq 1 ]; then
    rm -f ${SCRIPT_PWD}/generatorcpp/out${RANDOMD}*.sql ${SCRIPT_PWD}/generatorcpp/out${RANDOMD}.sql.part* 2>/dev/null
  fi
  if [ ${USE_REVGEN} -eq 1 ]; then
    rm -f ${SCRIPT_PWD}/revgen/outrev${RANDOMD}*.sql ${SCRIPT_PWD}/revgen/outrev${RANDOMD}.sql.part* 2>/dev/null
  fi
}

# Setup
rm -Rf ${WORKDIR} ${RUNDIR}
diskspace
mkdir -p ${WORKDIR} ${WORKDIR}/log ${RUNDIR}
chmod -R +rX ${WORKDIR}
echo "grep -E '^BASEDIR=|^INFILE=|^THREADS=|^MYEXTRA=|^MYINIT=|^ADD_RANDOM_OPTIONS=' pquery*run*conf | sed 's|   #.*||;s|ADD_RANDOM|RND|;s|=|: \\t|'" > ${WORKDIR}/i
echo "find . | grep -E '_out$|_copy$' | sed \"s|^\./| \${PWD}/|\" | xargs -I{} wc -l {} | sort -h" > ${WORKDIR}/my  # _copy: as created by for example ./base_reducer<trial>.sh if an _out file already exists
echo "${BASEDIR}" > ${WORKDIR}/BASEDIR.template
ln -s "${SCRIPT_PWD}/filter_from_base.sh" "${WORKDIR}/filter_from_base"  # This script replaces pr_without_base_prs previously used, now remarked, in lines below
#echo '#!/bin/bash' > ${WORKDIR}/pr_without_base_prs
#echo 'set +H' >> ${WORKDIR}/pr_without_base_prs
#echo "if [ -z \"\${1}\" ]; then echo 'Please pass the file which contains all combined UniqueID's from base runs (use something like  pr | grep 'Seen' >> ~/base_mdev-00000_filter_list.txt  in every base workdir to get this list), pr will then be run with the filter applied'; exit 1; fi" >> ${WORKDIR}/pr_without_base_prs
#echo 'if [ ! -r "${HOME}/pr" ]; then echo "Assert: ${HOME}/pr is not available, run ~/mariadb-qa/linkit; exit 1; fi' >> ${WORKDIR}/pr_without_base_prs
#echo "echo \"pr results, without any UniqueID's seen in base runs (as per supplied filter file \${1}):\"" >> ${WORKDIR}/pr_without_base_prs
#echo "~/pr | grep 'Seen' | sed 's|[ ]*(Seen .*||' | grep -vEi '^#|no core file found|no parsable frames|SHUTDOWN' | grep -vFf <(cat \${1} | sed 's|[ ]*(Seen .*||;s|[ \\t]*$||;s|\\r$||')" >> ${WORKDIR}/pr_without_base_prs
#chmod +x ${WORKDIR}/i ${WORKDIR}/my ${WORKDIR}/pr_without_base_prs
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
  ONGOING="Workdir: ${WORKDIR} | Rundir: ${RUNDIR} | Basedir: ${BASEDIR}"
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
  mkdir -p ${WORKDIR}/vault
  rm -rf ${WORKDIR}/vault/*
  killall vault
  if [[ "${MDG}" -eq 1 ]]; then
    ${SCRIPT_PWD}/vault_test_setup.sh --workdir=${WORKDIR}/vault --setup-mdg-mount-points --use-ssl
  else
    ${SCRIPT_PWD}/vault_test_setup.sh --workdir=${WORKDIR}/vault --use-ssl
    #MYEXTRA="$MYEXTRA --early-plugin-load=keyring_vault.so --loose-keyring_vault_config=${WORKDIR}/vault/keyring_vault.cnf"
  fi
fi

if [ ${QUERY_CORRECTNESS_TESTING} -eq 1 ]; then
  echoit "mysqld/mariadbd Start Timeout: ${MYSQLD_START_TIMEOUT} | Client Threads: ${THREADS} | Trials: ${TRIALS} | Statements per trial: ${QC_NR_OF_STATEMENTS_PER_TRIAL} | Primary Engine: ${QC_PRI_ENGINE} | Secondary Engine: ${QC_SEC_ENGINE} | Eliminate Known Bugs: ${ELIMINATE_KNOWN_BUGS}"
else
  echoit "mysqld/mariadbd Start Timeout: ${MYSQLD_START_TIMEOUT} | Client Threads: ${THREADS} | Queries/Thread: ${QUERIES_PER_THREAD} | Trials: ${TRIALS} | Save coredump/valgrind issue trials only: $(if [ ${SAVE_TRIALS_WITH_BUGS_ONLY} -eq 1 ]; then
    echo -n 'TRUE'
    if [ ${SAVE_SQL} -eq 1 ]; then echo ' + save all SQL traces'; else echo ''; fi
  else echo 'FALSE'; fi)"
fi

if [ ${REPLICATION} -eq 1 ]; then
  if [ "${CRASH_RECOVERY_TESTING}" -eq 1 ]; then
    if [ "${REPLICATION_SHUTDOWN_OR_KILL}" -eq 0 ]; then
      echoit "Replication testing: YES | Crash Recovery Testing: YES | Mode: Normal shutdown"
    else
      echoit "Replication testing: YES | Crash Recovery Testing: YES | Mode: Forceful shutdown using kill -9 command"
    fi
  else
    echoit "Replication testing: YES"
  fi
  echoit "REPL_EXTRA: '${REPL_EXTRA}' | MASTER_EXTRA: '${MASTER_EXTRA}' | SLAVE_EXTRA: '${SLAVE_EXTRA}'"  # Report extra options (replication general (master+slave), master, slave)
else
  echoit "Replication testing: NO: Disabling all REPL_EXTRA, MASTER_EXTRA, SLAVE_EXTRA settings"
  REPL_EXTRA=
  MASTER_EXTRA=
  SLAVE_EXTRA=
fi

# Measure the input file once, for the per-trial selection or window in emit_trial_sources(). With
# QUERIES_PER_INFILE > 0 each trial randomly selects up to that many lines from the whole file
# (xoshiro256++ entropy). At 0 the whole file is used, and a file larger than the line cap is then read
# from a random offset each trial, so a run sees the whole file over its trials instead of the first
# PQUERY_MAX_SQL_LINES lines every time. The configured input file itself is never changed.
INFILE_LINES=0
INFILE_WINDOW_MAX_OFFSET=1
INFILE_ASM_KB=0  # What this source can add to one trial's SQL, for the diskspace check in assemble_trial_sql()
if [ "${USE_INFILE}" -eq 1 ]; then
  INFILE_LINES="$(wc -l < ${INFILE})"
  if [ "${INFILE_LINES}" -lt 1 ]; then
    echoit "Assert: the SQL input file (${INFILE}) holds no lines"
    exit 1
  fi
  INFILE_ASM_KB=$(( $(stat -c %s ${INFILE}) / 1024 + 1 ))
  if [ "${QUERIES_PER_INFILE}" -gt 0 ]; then
    if [ "${QUERIES_PER_INFILE}" -lt "${INFILE_LINES}" ]; then
      # Only the selected lines reach a trial, so the diskspace check must not ask for the whole file.
      # The bytes per line are rounded up, so the estimate errs on the large side
      INFILE_ASM_KB=$(( ( ( $(stat -c %s ${INFILE}) + INFILE_LINES - 1 ) / INFILE_LINES ) * QUERIES_PER_INFILE / 1024 + 1 ))
    fi
    echoit "The SQL input file holds ${INFILE_LINES} lines. Each trial randomly selects up to QUERIES_PER_INFILE=${QUERIES_PER_INFILE} of them"
  elif [ "${INFILE_LINES}" -gt "${PQUERY_MAX_SQL_LINES}" ]; then
    # Leave room for a full window: stop the random offset one window short of the end of the file. The
    # bytes per line are rounded up, so the room reserved is not short and a trial gets its full window.
    # A window can still come out a little short where the lines around it run longer than the average
    INFILE_WINDOW_BYTES=$(( ( ( $(stat -c %s ${INFILE}) + INFILE_LINES - 1 ) / INFILE_LINES ) * PQUERY_MAX_SQL_LINES ))
    INFILE_WINDOW_MAX_OFFSET=$(( $(stat -c %s ${INFILE}) - INFILE_WINDOW_BYTES ))
    [ "${INFILE_WINDOW_MAX_OFFSET}" -lt 1 ] && INFILE_WINDOW_MAX_OFFSET=1
    # Only one window of it reaches a trial, so the diskspace check must not ask for the whole file
    INFILE_ASM_KB=$(( INFILE_WINDOW_BYTES / 1024 + 1 ))
    echoit "The SQL input file holds ${INFILE_LINES} lines, more than PQUERY_MAX_SQL_LINES=${PQUERY_MAX_SQL_LINES}. Each trial reads a window of ${PQUERY_MAX_SQL_LINES} lines from a random offset in it"
  fi
fi

# The all-disk source: index every SQL file on the disk now, so no trial has to search the disk again
ALL_DISK_SQL_INDEX="${WORKDIR}/all_disk_sql.index"
ALL_DISK_SQL_POOL="${TRIAL_SQL_DIR}/${RANDOMD}_all_disk.sql"
ALL_DISK_SQL_LINES=0
if [ "${USE_ALL_DISK_SQL}" -eq 1 ]; then
  all_disk_sql_index
fi

SQL_INPUT_TEXT=
if [ ${USE_GENERATOR} -eq 1 ]; then SQL_INPUT_TEXT="SQL Generator (${QUERIES_PER_GENERATOR_RUN} queries per trial)"; fi
if [ ${USE_REVGEN} -eq 1 ]; then SQL_INPUT_TEXT="${SQL_INPUT_TEXT}${SQL_INPUT_TEXT:+ + }revgen (${QUERIES_PER_REVGEN_RUN} queries per trial)"; fi
if [ ${USE_INFILE} -eq 1 ]; then
  if [ "${QUERIES_PER_INFILE}" -gt 0 ]; then
    SQL_INPUT_TEXT="${SQL_INPUT_TEXT}${SQL_INPUT_TEXT:+ + }SQL file ${INFILE} (up to ${QUERIES_PER_INFILE} of ${INFILE_LINES} lines per trial)"
  else
    SQL_INPUT_TEXT="${SQL_INPUT_TEXT}${SQL_INPUT_TEXT:+ + }SQL file ${INFILE} (${INFILE_LINES} lines)"
  fi
fi
if [ ${USE_ALL_DISK_SQL} -eq 1 ]; then SQL_INPUT_TEXT="${SQL_INPUT_TEXT}${SQL_INPUT_TEXT:+ + }all SQL on disk (${QUERIES_PER_ALL_DISK_RUN} lines, new every ${ALL_DISK_SQL_NEW_QUERIES_EVERY_X_TRIALS} trials)"; fi
SQL_INPUT_TEXT="Sources: ${SQL_INPUT_TEXT}"
echoit "Valgrind run: $(if [ "${VALGRIND_RUN}" == "1" ]; then echo -n 'TRUE'; else echo -n 'FALSE'; fi) | pquery timeout: ${PQUERY_RUN_TIMEOUT} | ${SQL_INPUT_TEXT}$(if [ ${THREADS} -ne 1 ]; then echo -n " | Testcase size (chunked from infile): ${MULTI_THREADED_TESTC_LINES}"; fi)"
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

# Workaround, ref https://github.com/google/sanitizers/issues/856
# This will show even for the "version detection" below, causing it to fail if the vm.mmap_rnd_bits workaround is not set
#==180506==Shadow memory range interleaves with an existing memory mapping. ASan cannot proceed correctly. ABORTING.
#==180506==ASan shadow was supposed to be located in the [0x00007fff7000-0x10007fff7fff] range.
#==180506==This might be related to ELF_ET_DYN_BASE change in Linux 4.12.
#==180506==See https://github.com/google/sanitizers/issues/856 for possible workarounds.
#==180506==Process memory map follows:
#...
#==180506==End of process memory map.
#This workaround is no longer needed, provided another workaround (set soft/hard stack 16000000 in /etc/security/limits.conf instead of unlimited) is present. Ref same ticket, later comments.
#sudo sysctl vm.mmap_rnd_bits=28   # Workaround, ref https://github.com/google/sanitizers/issues/856

# Get version specific options
MID=
if [ -r ${BASEDIR}/scripts/mariadb-install-db ]; then MID="${BASEDIR}/scripts/mariadb-install-db"; fi
if [ -r ${BASEDIR}/scripts/mysql_install_db ]; then MID="${BASEDIR}/scripts/mysql_install_db"; fi
if [ -r ${BASEDIR}/bin/mysql_install_db ]; then MID="${BASEDIR}/bin/mysql_install_db"; fi
START_OPT="--core-file"                                  # Compatible with 5.6,5.7,8.0
INIT_OPT="--no-defaults --initialize-insecure ${MYINIT}" # Compatible with 5.7,8.0 (mysqld init)
INIT_TOOL="${BIN}"                                       # Compatible with 5.7,8.0 (mysqld init), changed to MID later if version <=5.6
VERSION_INFO=$(${BIN} --version | grep -oe '[589]\.[0-9]' | head -n1)
VERSION_INFO_2=$(${BIN} --version | grep --binary-files=text -i 'MariaDB' | grep -oe '1[0-5]\.[0-9][0-9]*' | head -n1)
if [ -z "${VERSION_INFO_2}" ]; then VERSION_INFO_2="NA"; fi

if [[ "${VERSION_INFO_2}" =~ ^10.[1-3]$ ]]; then
  VERSION_INFO="5.1"
  INIT_TOOL="${BASEDIR}/scripts/mysql_install_db"
  INIT_OPT="--no-defaults --force ${MYINIT}"
  START_OPT="--core"
elif [[ "${VERSION_INFO_2}" =~ ^1[0-5].[0-9][0-9]* ]]; then
  VERSION_INFO="5.6"
  INIT_TOOL="${BASEDIR}/scripts/mariadb-install-db"
  INIT_OPT="--no-defaults --force --auth-root-authentication-method=normal ${MYINIT}"
  START_OPT="--core-file --core"
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
  echo "WARNING: mysqld/mariadbd (${BIN}) version detection failed. This is likely caused by using this script with a non-supported distribution or version of mysqld/mariadbd, or simply because this directory is not a proper MySQL[-fork] base directory. Please expand this script to handle (which shoud be easy to do). Even so, the scipt will now try and continue as-is, but this may and will likely fail."
  echo "=========================================================================================="
fi

echoit "Generating datadir template (using mysql_install_db or mysqld/mariadbd --init)..."
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

if [[ "${MDG}" -eq 0 && "${GRP_RPL}" -eq 0 ]]; then
  if [ ! -d "${RUNDIR}" ]; then mkdir -p ${RUNDIR}; fi  # In case the filtering took a long time and tmpfs_clean.sh cleaned up the RUNDIR directory already
  echoit "Making a copy of the mysqld/mariadbd used to ${WORKDIR}/mysqld (handy for coredump analysis and manual bundle creation)..."
  mkdir -p ${WORKDIR}/mysqld
  cp ${BIN} ${WORKDIR}/mysqld/
  # Updated 13/5/24: The new BIN link in RUNDIR (rather than BIN copy) saves 300-400Mb per RUNDIR
  if [[ "${BIN}" == *"mariadbd" ]]; then
    echoit "Making a link to mariadbd in ${RUNDIR}/mariadbd for in-run coredump analysis..."
    ln -s ${WORKDIR}/mysqld/mariadbd ${RUNDIR}/mariadbd
  elif [[ "${BIN}" == *"mysqld" ]]; then
    echoit "Making a link to mysqld in ${RUNDIR}/mysqld for in-run coredump analysis..."
    ln -s ${WORKDIR}/mysqld/mysqld ${RUNDIR}/mysqld
  else  # mysqld-debug etc.
    echo "Making a copy of ${BIN} in ${RUNDIR} for in-run coredump analysis..."
    cp ${BIN} ${RUNDIR}
  fi
  if [ -r ${BASEDIR}/include/mysql/server/private/source_revision.h ]; then
    echo "Making a copy of source_revision.h to ${WORKDIR}/mysqld for later version reference"
    cp ${BASEDIR}/include/mysql/server/private/source_revision.h ${WORKDIR}/mysqld/
  fi
  echoit "Making a copy of the ldd files required for mysqld/mariadbd core analysis to ${WORKDIR}/mysqld..."
  PWDTMPSAVE="${PWD}"
  cd ${WORKDIR}/mysqld || exit 1
  ${SCRIPT_PWD}/ldd_files.sh
  cd ${PWDTMPSAVE} || exit 1

  # Data template creation
  TEMPLATE_CREATE_ATTEMPTS=0
  while true; do
    TEMPLATE_CREATE_ATTEMPTS=$[ ${TEMPLATE_CREATE_ATTEMPTS} + 1]
    rm -Rf ${WORKDIR}/data.template
    ${INIT_TOOL} ${INIT_OPT} --basedir=${BASEDIR} --datadir=${WORKDIR}/data.template > ${WORKDIR}/log/mysql_install_db.txt 2>&1
    if [ "$(ls ${WORKDIR}/data.template/mysql 2>/dev/null | wc -l)" -gt 50 ]; then  # Likely succesfull template creation
      echoit "Created datadir template at ${WORKDIR}/data.template"
      break
    else
      echoit "Attempt ${TEMPLATE_CREATE_ATTEMPTS} (max: 10) of creating a datadir template at ${WORKDIR}/data.template failed. Retrying in 10 seconds"
      sleep 10
      if [ "${TEMPLATE_CREATE_ATTEMPTS}" -eq 10 ]; then
        echo "Assert: 10 attempts to create ${WORKDIR}/data.template failed. Terminating"
        exit 1
        break
      else
        continue
      fi
    fi
  done
  TEMPLATE_CREATE_ATTEMPTS=
  # Sysbench dataload
  diskspace
  if [ ${SYSBENCH_DATALOAD} -eq 1 ]; then
    echoit "Starting mysqld/mariadbd for sysbench data load. Error log: ${WORKDIR}/data.template/master.err"
    CMD="${BIN} --basedir=${BASEDIR} --datadir=${WORKDIR}/data.template --tmpdir=${WORKDIR}/data.template --core-file --port=$PORT --pid_file=${WORKDIR}/data.template/pid.pid --socket=${WORKDIR}/data.template/socket.sock --log-output=none --log-error=${WORKDIR}/data.template/master.err"
    diskspace
    $CMD >> ${WORKDIR}/data.template/master.err 2>&1 &
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
    timeout --signal=9 20s ${BASEDIR}/bin/mysqladmin -uroot -S${WORKDIR}/data.template/socket.sock shutdown > /dev/null 2>&1
    (
      sleep 0.2
      kill -9 ${MPID} > /dev/null 2>&1
      # kill -0 poll instead of `wait`: this PID is a parent-shell child, not
      # a child of this subshell; `wait $PID` would error "not a child" and
      # return 127 instantly. `timeout` is external (coreutils) and can't
      # invoke a shell builtin, so the previous `timeout … wait $PID` form
      # was a no-op regardless of subshell.
      for X in $(seq 1 5); do kill -0 ${MPID} 2>/dev/null || break; sleep 1; done
    ) # Terminate mysqld/mariadbd
  fi
  echo "${MYEXTRA}${MYSAFE}" | if grep -qi "innodb[_-]log[_-]checksum[_-]algorithm"; then
    # Ensure that if MID created log files with the standard checksum algo, whilst we start the server with another one, that log files are re-created by mysqld/mariadbd
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
    if [[ ! -e $(which pmm-admin 2>/dev/null) ]]; then
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
elif [[ "${MDG}" -eq 1 || "${GRP_RPL}" -eq 1 ]]; then
  echoit "Making a copy of the mysqld/mariadbd used to ${RUNDIR} for in-run coredump analysis..."
  cp ${BIN} ${RUNDIR}
  echoit "Making a copy of the mysqld/mariadbd used to ${WORKDIR}/mysqld (handy for coredump analysis and manual bundle creation)..."
  mkdir -p ${WORKDIR}/mysqld
  cp ${BIN} ${WORKDIR}/mysqld
  echoit "Making a copy of the ldd files required for mysqld/mariadbd core analysis to ${WORKDIR}/mysqld..."
  PWDTMPSAVE=${PWD}
  cd ${WORKDIR}/mysqld || exit 1
  ${SCRIPT_PWD}/ldd_files.sh
  cd ${PWDTMPSAVE} || exit 1
  if [[ "${MDG}" -eq 1 ]]; then
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
TRIALS_STARTED=1  # From here on, echoit dims a routine step, so the trial results stand out on screen
COUNT=0
for X in $(seq 1 ${TRIALS}); do
  pquery_test
  COUNT=$(($COUNT + 1))
done
# All done, wrap up pquery run
echoit "pquery finished requested number of trials (${TRIALS})... Terminating..."
if [[ "${MDG}" -eq 1 || "${GRP_RPL}" -eq 1 ]]; then
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
# The last trial's SQL and the all-disk pool are the only ones left: every earlier trial's file was
# deleted as the next was written, and the generated pools are deleted at the end of each trial
echoit "Done. Attempting to cleanup the per-trial SQL of this run..."
rm -f ${TRIAL_SQL_DIR}/${RANDOMD}_*
echoit "The results of this run can be found in the workdir ${WORKDIR}..."
echoit "Done. Exiting $0 with exit code 0..."
exit 0
