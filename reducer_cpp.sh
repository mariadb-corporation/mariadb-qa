#!/bin/bash

# Copyright (c) 2012,2013 Oracle and/or its affiliates. All rights reserved.
# Use is subject to license terms.
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
# You should have received a copy of the GNU General Public License
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301, USA

# This program has been used to reduce tens of thousands of SQL based testcases,
# from tens (or hundreds) of thousands of SQL lines to less then 10 lines, each.

# In active development: 2012-2025

# Learn more at:
# https://www.percona.com/blog/2014/09/03/reducer-sh-a-powerful-mysql-test-case-simplificationreducer-tool/
# https://www.percona.com/blog/2015/07/21/mysql-qa-episode-7-single-threaded-reducer-sh-reducing-testcases-for-beginners
# https://www.percona.com/blog/2015/07/23/mysql-qa-episode-8-reducing-testcases-engineers-tuning-reducer-sh/
# https://www.percona.com/blog/2015/07/28/mysql-qa-episode-9-reducing-testcases-experts-multi-threaded-reducer-sh/
# https://www.percona.com/blog/2015/07/31/mysql-qa-episode-10-reproducing-simplifying-get-right/
# https://www.percona.com/blog/2015/03/17/free-mysql-qa-and-bash-linux-training-series/

# ======== Dev Contacts
# Main developer: Roel Van de Paar <roel A.T vandepaar D.O.T com>
# With contributions from & thanks to: Andrew Dalgleish, Ramesh Sivaraman, Tomislav Plavcic
# With thanks to the team at Oracle for open sourcing the original internal version

# ======== User configurable variables section (see 'User configurable variable reference' below for more detail)
# === Basic options
INPUTFILE=                      # The SQL file to be reduced. This can also be given as the first option to reducer.sh. Do not use double quotes
MODE=4                          # Required. Most often used modes: 4=Any crash (TEXT not required), 3=Search for a specific TEXT in mariadbd/mysqld error log, 2=Idem, but in client log
TEXT="somebug"                  # The text string you want reducer to search for, in specific locations depending on the MODE selected. Regex capable. Use with MODEs=1,2,3,5,6,7,8
MODE3_ANY_SIG=0                 # MODE=3 Modifier which works similar to MODE=4. 1: MODE 3 will look for any UniqueID starting with 'SIG'. Requires USE_NEW_TEXT_STRING. TEXT is ignored
WORKDIR_LOCATION=1              # 0: use /tmp (disk bound) | 1: use tmpfs (default) | 2: use ramfs (needs setup) | 3: use storage at WORKDIR_M3_DIRECTORY
WORKDIR_M3_DIRECTORY="/data"    # Only relevant if WORKDIR_LOCATION is set to 3, use a specific directory/mount point
MYEXTRA="--no-defaults --loose-innodb-buffer-pool-in-core-dump=0 --log-output=none --sql_mode="  # mariadbd/mysqld options to be used (and reduced). Note: TokuDB plugin loading is checked/done automatically. # RV 14/05/22 ONLY_FULL_GROUP_BY removed
MYINIT=""                       # Extra options to pass to mariadbd/mysqld AND at data dir init time. See pquery-run-*.conf for more info
BASEDIR="${PWD}"                # Path to the MySQL BASE directory to be used
DISABLE_TOKUDB_AUTOLOAD=0       # On/Off (1/0) Prevents mariadbd/mysqld startup issues when using standard MySQL server (i.e. no TokuDB available) with a testcase containing TokuDB SQL
DISABLE_TOKUDB_AND_JEMALLOC=1   # For MariaDB, TokuDB is deprecated, so we always disable both in full
SCRIPT_PWD=$(dirname $(readlink -f "${0}"))

# === Sporadic testcases        # Used when testcases prove to be sporadic *and* fail to reduce using basic methods
FORCE_SKIPV=0                   # On/Off (1/0) Forces verify stage to be skipped (auto-enables FORCE_SPORADIC)
FORCE_SPORADIC=0                # On/Off (1/0) Forces issue to be treated as sporadic
NR_OF_TRIAL_REPEATS=1           # Set to 1 (default) to repeat/try/attempt each trial 1 time. Increase to re-attempt trials when reduction was not succesful for that trial; ideal for sporadic issues which need x attempts per trial. Will work irrespective of detected sporadicity. Ref TODO-3017

# === True Multi-Threaded       # True multi-threaded testcase reduction (only program in the world that does this) based on random replay (auto-covers sporadic testcases)
PQUERY_MULTI=0                  # On/off (1/0) Enables true multi-threaded testcase reduction based on random replay (auto-enables USE_PQUERY)

# === Reduce startup issues     # Reduces startup issues. This will only work if a clean start (mariadbd/mysqld --no-defaults) works correctly; otherwise template creation will fail also
REDUCE_STARTUP_ISSUES=0         # Default/normal use: 0. Set to 1 to reduce mariadbd/mysqld startup (ie. failing mariadbd/mysqld --option etc.) issues (with SQL replay but without SQL simplication)

# === Reduce GLIBC/SS crashes   # Remember that if you use REDUCE_GLIBC_OR_SS_CRASHES=1 with MODE=3, then the console/typescript log is searched for TEXT, not the mariadbd/mysqld error log. Note: reducing 'buffer overflow' has previously been difficult (unknown reason, not enough samples to establish cause), try an ASAN dbg+opt build first, often they report on the memory issues more easily.
REDUCE_GLIBC_OR_SS_CRASHES=0    # Default/normal use: 0. Set to 1 to reduce testcase based on a GLIBC crash or stack smash being detected. MODE=3 (TEXT) and MODE=4 (all) supported
SCRIPT_LOC=/usr/bin/script      # The script binary (sudo yum install util-linux) is required for reducing GLIBC crashes

# === Reduce replication issues 
REPLICATION=0                   # Default: 0: disabled, 1: enable standard master/slave replication. Replay will be against the master
REPL_EXTRA="--gtid_strict_mode=1 --relay-log=relaylog"  # Extra parameters to pass to the master and the slave, besides MYEXTRA (both are used)
MASTER_EXTRA="--log_bin=binlog --binlog_format=ROW --log_bin_trust_function_creators=1 --server_id=1"  # Extra mariadbd/mysqld options to pass to the master server only
SLAVE_EXTRA="--slave_skip_errors=ALL --server_id=2"  # Extra mariadbd/mysqld options to pass to the slave server only

# === Hang issues               # For catching hang issues (both in normal runtime as well as during shutdown). Must set MODE=0 for this option to become active
TIMEOUT_CHECK=350               # When MODE=0 is used, this specifies the nr of seconds to be used as a timeout. Do not set too small (eg. 350 sec is likely best. In the past this was 600 best. 350 to be confirmed as new best. note that ~/ds only alllows up to 397 here (400 hardcoded in ~/ds) - this may or may not require further work; TODO: to be tested with a new set of hang bugs). See examples in help below. Set to approx FULL testcase duration + 20 seconds, keeping in mind load on the server. Minimum: 31 seconds. 'FULL': Because the chuncking algorithm could eliminate the hanging query, but if the TIMEOUT_CHECK is set too small then a timeout will still occur due to overall testcase duration! Likely best to take overall testcase lenght (without the hanging query) + 30 seconds on otherwise unused server, or simply set it to a large number as this is less error-prone (though note the hardcoded ~/ds note above). A good approach is to pre-trim the file past the hanging query first manually, then remove last statement, check duration client. Then add 30 seconds.

# === Timeout mariadbd/mysqld   # Uncommonly used option. Used to terminate (timeout) mariadbd/mysqld after x seconds, while still checking for MODE=2/3 TEXT. See examples in help below.
TIMEOUT_COMMAND=""              # A specific command, executed as a prefix to mariadbd/mysqld. For example, TIMEOUT_COMMAND="timeout --signal=SIGKILL 10m"

# === Advanced options          # Note: SLOW_DOWN_CHUNK_SCALING is of beta quality. It works, but it may affect chunk scaling somewhat negatively in some cases
SLOW_DOWN_CHUNK_SCALING=0       # On/off (1/0) If enabled, reducer will slow down it's internal chunk size scaling (also see SLOW_DOWN_CHUNK_SCALING_NR)
SLOW_DOWN_CHUNK_SCALING_NR=3    # Slow down chunk size scaling (both for chunk reductions and increases) by not modifying the chunk for this number of trials. Default=3
USE_NEW_TEXT_STRING=0           # On/off (1/0) If enabled, when using MODE=3, this uses new_text_string.sh (from mariadb-qa) instead of searching the entire error log. No effect otherwise. Note: enabling this makes $TEXT non-regex aware.
TEXT_STRING_LOC="${SCRIPT_PWD}/new_text_string.sh"  # new_text_string.sh script in mariadb-qa. To get this script use:  cd ~; git clone https://github.com/Percona-QA/mariadb-qa.git (used when USE_NEW_TEXT_STRING is set to 1, which is the case for all inside-MariaDB runs, as set by pquery-prep-red.sh)
SCAN_FOR_NEW_BUGS=1             # Scan for any new bugs seen during testcase reduction
KNOWN_BUGS_LOC="${SCRIPT_PWD}/known_bugs.strings"  # If SCAN_FOR_NEW_BUGS=1 then this file is used to filter which bugs are known. i.e. if a certain unremarked text string appears in the KNOWN_BUGS_LOC file, it will not be considered a new issue when it is seen by reducer.sh
NEW_BUGS_SAVE_DIR="/data/NEWBUGS"  # Save new bugs into a specific directory (otherwise it will be saved in the workdir)
SHOW_SETUP_DEBUGGING=0          # Set to 1 to enable [Setup] messages with extra debug information
RR_TRACING=0                    # Set to 1 to start server under the 'rr' debugger
RR_SAVE_ALL_TRACES=0            # Set to 1 to save all rr traces rather than only the final one
PAUSE_AFTER_EACH_OCCURRENCE=0   # Set to 1 to pause reducer after each successful issue occurrence (other search keywords: stop, halt, kill)

# === Expert options (Do not change, unless you fully understand the change)
MULTI_THREADS=10                # Default=10 | Number of subreducers. This setting has no effect if PQUERY_MULTI=1, use PQUERY_MULTI_THREADS instead when using PQUERY_MULTI=1 (ref below). Each subreducer can idependently find the issue and will report back to the main reducer.
MULTI_THREADS_INCREASE=5        # Default=5  | Increase of MULTI_THREADS per bug-failed-to-be-detected round, both for standard and PQUERY_MULTI=1 runs
MULTI_THREADS_MAX=50            # Default=50 | Max number of MULTI_THREADS threads, both for standard and PQUERY_MULTI=1 runs
PQUERY_EXTRA_OPTIONS=""         # Default="" | Adds extra options to pquery replay, used for Query Correctness (QC) trials
PQUERY_MULTI_THREADS=3          # Default=3  | The numberof subreducers when PQUERY_MULTI=1 (MULTI_THREADS will be set to this number at startup)
PQUERY_MULTI_CLIENT_THREADS=30  # Default=30 | The number of pquery client threads per subreducer/mariadbd/mysqld
PQUERY_MULTI_QUERIES=99999999   # Default=99999999 | The number of queries to be executed per client per trial
PQUERY_REVERSE_NOSHUFFLE_OPT=0  # Default=0  | Reverses --no-shuffle into shuffle and vice versa
                                # On/Off (1/0) (Default=0: --no-shuffle is used for standard pquery replay, shuffle is used for PQUERY_MULTI. =1 reverses this)
SAVE_RESULTS=0                  # On/Off (1/0) (Default=1: save a copy of reducer and related files to /tmp on completion, provided a volatile storage memory, like tmpfs, was used as workdir. A 0 setting will ensure no such copy is made). Recommendation is to enable this only when there are issues with reducer itself or with a particular testcase to debug

# === pquery options            # Note: only relevant if pquery is used for testcase replay, ref USE_PQUERY and PQUERY_MULTI
USE_PQUERY=0                    # On/Off (1/0) Enable to use pquery instead of the mysql CLI. pquery binary (as set in PQUERY_LOC) must be available
PQUERY_LOC="${SCRIPT_PWD}/pquery/pquery2-md"  # The pquery binary in mariadb-qa. To get this binary use:  cd ~; git clone https://github.com/Percona-QA/mariadb-qa.git
PQUERY_CONS_Q_FAIL=0            # On/Off (1/0) (Default=0) Checks the pquery log for 'Last [0-9]+ consecutive queries all failed' while ignoring all other issue occurrences (auto-sets USE_PQUERY=1, MODE=3, TEXT='Last [0-9]+ consecutive queries all failed', and USE_NEW_TEXT_STRING=0). This is a MODE=3 hack to use the pquery log irrespective of any crashes/TEXT/error log contents or similar to debug the 'x consecutive queries all failed' scenario (which may indicate valid bugs). Do not turn on unless specifically needed. When using this, note that testcases can never become much shorter then let's say 251-265 queries, and that only the top 1 to 10 orso queries will matter (i.e. until it starts failing queries, which will should be visible in the pquery output i.e. ;#ERROR... or likely similar in the CLI) as the last 250 queries in the testcase are needed to produce the reducible outcome of having that message in the pquery log

# === Other options             # The options are not often changed
CLI_MODE=2                      # When using the CLI; 0: sent SQL using a pipe, 1: sent SQL using --execute="SOURCE ..." command, 2: sent SQL using redirection (mysql < input.sql)
ENABLE_QUERYTIMEOUT=0           # On/Off (1/0) Enable the Query Timeout function (which also enables and uses the MySQL event scheduler)
QUERYTIMEOUT=90                 # Query timeout in sec. Note: queries terminated by the query timeout did not fully replay, and thus overall issue reproducibility may be affected
LOAD_TIMEZONE_DATA=0            # On/Off (1/0) Enable loading Timezone data into the database (mainly applicable for RQG runs) (turned off by default=0 since 26.05.2016)
STAGE1_LINES=90                 # Proceed to stage 2 when the testcase is less then x lines (auto-reduced when FORCE_SPORADIC or FORCE_SKIPV are active)
SKIPSTAGEBELOW=0                # Usually not changed (default=0), skips stages below and including this stage
SKIPSTAGEABOVE=99               # Usually not changed (default=99), skips stages above and including this stage
FORCE_KILL=0                    # On/Off (1/0) Enable to forcefully kill mariadbd/mysqld instead of using mariadb-admin/mysqladmin shutdown etc. Auto-disabled for MODE=0.

# === MariaDB Galera Cluster
MDG=0                           # On/Off (1/0) Enable to reduce testcases using a MariaDB Galera Cluster. Auto-enables USE_PQUERY=1
MDG_ISSUE_NODE=0                # The node on which the issue would/should show (0,1,2 or 3) (default=0 = check all nodes to see if issue occured)
NR_OF_NODES=3                   # Nr of MDG nodes 1-n
GALERA_NODE=1                   # Default galera node to analyse the issue
WSREP_PROVIDER_OPTIONS=""       # wsrep_provider_options to be used (and reduced).

# === MySQL Group Replication
GRP_RPL=0                       # On/Off (1/0) Enable to reduce testcases using MySQL Group Replication. Auto-enables USE_PQUERYE=1
GRP_RPL_ISSUE_NODE=0            # The node on which the issue would/should show (0,1,2 or 3) (default=0 = check all nodes to see if issue occured)

# === MODE=5 Settings           # Only applicable when MODE5 is used
MODE5_COUNTTEXT=1               # Number of times the text should appear (default=1 = minimum). Currently only used for MODE=5
MODE5_ADDITIONAL_TEXT=""        # An additional string to look for in the CLI output when using MODE 5. When not using this set to "" (=default)
MODE5_ADDITIONAL_COUNTTEXT=1    # Number of times the additional text should appear (default=1 = minimum). Only used for MODE=5 and where MODE5_ADDITIONAL_TEXT is not ""

# === MODE=11 Settings          # Only applicable when MODE=11 is used (dump/binlog roundtrip fidelity testing)
MODE11_TYPE=dump                # dump | binlog. 'dump': use mariadb-dump+restore for the roundtrip. 'binlog': use --log_bin + mariadb-binlog replay
MODE11_BINLOG_FORMAT=MIXED      # MIXED | ROW | STATEMENT ; only used when MODE11_TYPE=binlog (default=MIXED; matches MariaDB default)

# === FireWorks Mode Settings
FIREWORKS=0                     # FireWorks mode: setups reducer.sh in such a way that any new bug observed, using a given input file, will be stored, and no actual reduction will be done. Expert use only; turning this on changes many settings, and thus changes the operation of reducer completely (default=0 = off)
FIREWORKS_LINES=200000          # How many lines to slice from the provided input file. Previous testing seems to shows an almost even distribution to original testcase lenght. High number: higher possibility of hitting a bug per run, but slower. Low number: the same, both in reverse. (default=200000, needs testing with 50000, 100000 etc.)
FIREWORKS_TIMEOUT=450           # Avoid runaway queries or hanging server instances from halting FireWorks runs. Server is terminated after this many seconds (using timeout command)

# === Old ThreadSync options    # No longer commonly used
TS_TRXS_SETS=0
TS_DBG_CLI_OUTPUT=0
TS_DS_TIMEOUT=10
TS_VARIABILITY_SLEEP=1

# ======== Machine configurable variables section: DO NOT REMOVE THIS
#VARMOD# < please do not remove this, it is here as a marker for other scripts (including reducer itself) to auto-insert settings

# ======== End of user/machine configurable variables. Hand-off to C++ backend.
#
# This bash wrapper is intentionally thin: it preserves the variable-definitions
# layout of the canonical reducer.sh so existing framework tools (pquery-prep-red.sh,
# startup.sh, pg, watchdog.sh, etc.) keep working — they sed-modify the VAR= lines
# above and inject Machine-section vars before #VARMOD#. After those edits run,
# we export every reducer-known variable and exec the C++ binary, which reads
# them via getenv() and performs the full reduction.
#
# Watchdog/process-grep compatibility: exec -a "$THIS_REDUCER" preserves argv[0]
# so process listings still show the reducer<N>.sh path, not the C++ binary path.
# THIS_REDUCER and SCRIPT_PWD are already set at the top of this file (line ~46);
# both follow the canonical reducer.sh contract so pquery-prep-red.sh's
# sed-rewrite of SCRIPT_PWD continues to work unchanged.
THIS_REDUCER="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
# Locate the C++ reducer binary. Search order: explicit REDUCER_CPP_BIN env,
# next to SCRIPT_PWD/reducercpp/, $HOME/mariadb-qa/reducercpp/, then $PATH.
if [ -z "${REDUCER_CPP_BIN}" ]; then
  for _candidate in \
    "${SCRIPT_PWD}/reducercpp/reducer" \
    "${HOME}/mariadb-qa/reducercpp/reducer" \
    "$(command -v reducer 2>/dev/null)"; do
    if [ -n "${_candidate}" ] && [ -x "${_candidate}" ]; then
      REDUCER_CPP_BIN="${_candidate}"; break
    fi
  done
fi

# If the C++ binary is missing, fall back to the archived bash reducer at
# ~/mariadb-qa/OLD/reducer.sh (parity safety net — the canonical reducer.sh
# was moved to OLD/ after the C++ port took over).
if [ -z "${REDUCER_CPP_BIN}" ] || [ ! -x "${REDUCER_CPP_BIN}" ]; then
  _fallback="${SCRIPT_PWD}/OLD/reducer.sh"
  [ ! -r "${_fallback}" ] && _fallback="${HOME}/mariadb-qa/OLD/reducer.sh"
  if [ -r "${_fallback}" ]; then
    echo "Warning: C++ reducer binary not found; falling back to archived bash reducer at ${_fallback}" >&2
    exec bash "${_fallback}" "$@"
  fi
  echo "Error: C++ reducer binary not found and OLD/reducer.sh fallback also missing." >&2
  echo "       Run: cd ~/mariadb-qa/reducercpp && ./build.sh" >&2
  exit 1
fi

export SCRIPT_PWD  # so pquery-prep-red.sh's hardcoded SCRIPT_PWD line wins over argv[0]'s parent
export INPUTFILE MODE TEXT MODE3_ANY_SIG WORKDIR_LOCATION WORKDIR_M3_DIRECTORY
export MYEXTRA MYINIT BASEDIR DISABLE_TOKUDB_AUTOLOAD DISABLE_TOKUDB_AND_JEMALLOC
export FORCE_SKIPV FORCE_SPORADIC NR_OF_TRIAL_REPEATS PQUERY_MULTI
export REDUCE_STARTUP_ISSUES REDUCE_GLIBC_OR_SS_CRASHES SCRIPT_LOC
export REPLICATION REPL_EXTRA MASTER_EXTRA SLAVE_EXTRA
export TIMEOUT_CHECK TIMEOUT_COMMAND
export SLOW_DOWN_CHUNK_SCALING SLOW_DOWN_CHUNK_SCALING_NR
export USE_NEW_TEXT_STRING TEXT_STRING_LOC
export SCAN_FOR_NEW_BUGS KNOWN_BUGS_LOC NEW_BUGS_SAVE_DIR SHOW_SETUP_DEBUGGING
export RR_TRACING RR_SAVE_ALL_TRACES PAUSE_AFTER_EACH_OCCURRENCE
export MULTI_THREADS MULTI_THREADS_INCREASE MULTI_THREADS_MAX
export PQUERY_EXTRA_OPTIONS PQUERY_MULTI_THREADS PQUERY_MULTI_CLIENT_THREADS PQUERY_MULTI_QUERIES
export PQUERY_REVERSE_NOSHUFFLE_OPT SAVE_RESULTS
export USE_PQUERY PQUERY_LOC PQUERY_CONS_Q_FAIL
export CLI_MODE ENABLE_QUERYTIMEOUT QUERYTIMEOUT LOAD_TIMEZONE_DATA
export STAGE1_LINES SKIPSTAGEBELOW SKIPSTAGEABOVE FORCE_KILL
export MDG MDG_ISSUE_NODE NR_OF_NODES GALERA_NODE WSREP_PROVIDER_OPTIONS
export GRP_RPL GRP_RPL_ISSUE_NODE
export MODE5_COUNTTEXT MODE5_ADDITIONAL_TEXT MODE5_ADDITIONAL_COUNTTEXT
export MODE11_TYPE MODE11_BINLOG_FORMAT
export FIREWORKS FIREWORKS_LINES FIREWORKS_TIMEOUT
export TS_TRXS_SETS TS_DBG_CLI_OUTPUT TS_DS_TIMEOUT TS_VARIABILITY_SLEEP

# Preserve argv[0] for watchdog process-grep compatibility (so ps shows
# reducer<N>.sh, not the C++ binary path).
exec -a "${THIS_REDUCER}" "${REDUCER_CPP_BIN}" "$@"

# Framework EOF marker — pquery-go-expert.sh greps for `^finish .INPUTFILE`
# to confirm pquery-prep-red.sh finished writing this file before applying
# its sed cleanup pass. The C++ wrapper never reaches this line (exec'd
# above) but the marker preserves the framework grep contract.
finish $INPUTFILE  # NEVER EXECUTED — exec'd above; framework marker only
