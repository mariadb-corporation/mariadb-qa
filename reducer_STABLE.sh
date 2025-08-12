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
MYEXTRA="--no-defaults --log-output=none --sql_mode="  # mariadbd/mysqld options to be used (and reduced). Note: TokuDB plugin loading is checked/done automatically. # RV 14/05/22 ONLY_FULL_GROUP_BY removed 
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
TIMEOUT_CHECK=600               # When MODE=0 is used, this specifies the nr of seconds to be used as a timeout. Do not set too small (eg. >600 sec is likely best). See examples in help below. Set to approx FULL testcase duration + 20 seconds, keeping in mind load on the server. Minimum: 31 seconds. 'FULL': Because the chuncking algorithm could eliminate the hanging query, but if the TIMEOUT_CHECK is set too small then a timeout will still occur due to overall testcase duration! Likely best to take overall testcase lenght (without the hanging query) + 30 seconds on otherwise unused server, or simply set it to a large number like 600 as this is less error-prone. A good approach is to pre-trim the file past the hanging query first manually, then remove last statement, check duration client. Then add 30 seconds.

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
WSREP_PROVIDER_OPTIONS=""       # wsrep_provider_options to be used (and reduced).

# === MySQL Group Replication
GRP_RPL=0                       # On/Off (1/0) Enable to reduce testcases using MySQL Group Replication. Auto-enables USE_PQUERYE=1
GRP_RPL_ISSUE_NODE=0            # The node on which the issue would/should show (0,1,2 or 3) (default=0 = check all nodes to see if issue occured)

# === MODE=5 Settings           # Only applicable when MODE5 is used
MODE5_COUNTTEXT=1               # Number of times the text should appear (default=1 = minimum). Currently only used for MODE=5
MODE5_ADDITIONAL_TEXT=""        # An additional string to look for in the CLI output when using MODE 5. When not using this set to "" (=default)
MODE5_ADDITIONAL_COUNTTEXT=1    # Number of times the additional text should appear (default=1 = minimum). Only used for MODE=5 and where MODE5_ADDITIONAL_TEXT is not ""

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

# ==== MySQL command line (CLI) output TEXT search examples
#TEXT=                       "\|      0 \|      7 \|"  # Example of how to set TEXT for MySQL CLI output (for MODE=2 or 5)
#TEXT=                       "\| i      \|"            # Idem, text instead of number (text is left-aligned, numbers are right-aligned in the MySQL CLI output)

# ======== User configurable variable reference
# - INPUTFILE: the SQL trace to be reduced by reducer.sh. This can also be given as the fisrt option to reducer.sh (i.e. $ ./reducer.sh {inputfile.sql})
# - MODE:
#   - MODE=0: Timeout testing (server hangs, shutdown issues, excessive command duration etc.) (set TIMEOUT_CHECK)
#   - MODE=1: Valgrind output testing (set TEXT)
#   - MODE=2: mysql CLI (Command Line Interface, i.e. the mysql client)/pquery client output testing (set TEXT)
#   - MODE=3: mariadbd/mysqld error output log or console/typescript log (when REDUCE_GLIBC_OR_SS_CRASHES=1) testing (set TEXT)
#   - MODE=4: Crash or GLIBC crash (when REDUCE_GLIBC_OR_SS_CRASHES=1) testing
#   - MODE=5 [BETA]: MTR testcase reduction (set TEXT) (Can also be used for multi-occurrence CLI output testing - see MODE5_COUNTTEXT)
#   - MODE=6 [ALPHA]: Multi threaded (ThreadSync) Valgrind output testing (set TEXT)
#   - MODE=7 [ALPHA]: Multi threaded (ThreadSync) mysql CLI/pquery client output testing (set TEXT)
#   - MODE=8 [ALPHA]: Multi threaded (ThreadSync) mariadbd/mysqld error output log testing (set TEXT)
#   - MODE=9 [ALPHA]: Multi threaded (ThreadSync) crash testing
# - SKIPSTAGEBELOW: Stages up to and including this one are skipped (default=0).
# - SKIPSTAGEABOVE: Stages above and including this one are skipped (default=9).
# - TEXT: Text to look for in MODEs 1,2,3,5,6,7,8. Ignored in MODEs 4 and 9.
#   Can contain extended grep (i.e. grep -E --binary-files=text or egrep)+regex syntax like "^ERROR|some_other_string". Remember this is regex: specify | as \| etc.
#   For MODE5, you would use a mysql CLI to get the desired output "string" (see example given above) and then set MODE5_COUNTTEXT
# - USE_PQUERY: 1: use pquery, 0: use mysql CLI. Causes reducer.sh to use pquery instead of the mysql client for replays (default=0). Supported for MODE=1,3,4
# - PQUERY_LOC: Location of the pquery binary (ref ~/mariadb-qa/pquery/pquery[-ms])
# - PQUERY_EXTRA_OPTIONS: Extra options to pquery which will be added to the pquery command line. This is used for query correctness trials
# - MDG: 1: bring up 3 node MariaDB Galera Cluster instead of default server, 0: use default non-cluster server (mariadbd/mysqld)
# - GRP_RPL: 1: bring up 3 node Group Replication instead of default server, 0: use default non-cluster server (mariadbd/mysqld)
#   see lp:/mariadb-qa/mdg-pquery/new/mdg-pquery_info.txt and lp:/mariadb-qa/docker_info.txt for more information on this. See above for some limitations etc.
#   IMPORTANT NOTE: If this is set to 1, ftm, these settings (and limitations) are automatically set: INHERENT: USE_PQUERY=1, LIMTATIONS: FORCE_SPORADIC=0,
#   SPORADIC=0, FORCE_SKIPV=0, SKIPV=1, MYEXTRA="", MULTI_THREADS=0
# - MDG_ISSUE_NODE: This indicates which node you would like to be checked for presence of the issue. 0 = Any node. Valid options: 0, 1, 2, or 3. Only works
#   for MODE=4 currently.
# - GRP_RPL_ISSUE_NODE: This indicates which node you would like to be checked for presence of the issue. 0 = Any node. Valid options: 0, 1, 2, or 3. Only works
#   for MODE=4 currently.
# - MDG_DOCKER_COMPOSE_LOC: Location of the Docker Compose file used to bring up 3 node MariaDB Galera Cluster (using images previously prepared by "new" method)
# - QUERYTIMEOUT: Number of seconds to wait before terminating a query (similar to RQG's querytimeout option). Do not set < 40 to avoid initial DDL failure
#   Warning: do not set this smaller then 1.5x what was used in RQG. If set smaller, the bug may not reproduce. 1.5x instead of 1x is a simple precaution
# - TS_TRXS_SETS [ALPHA]: For ThreadSync simplification (MODE 6+), use the last x set of thread actions only
#   (i.e. the likely crashing statements are likely at the end only) (default=1, 0=disable)
#   Increase to increase reproducibility, but increasing this exponentially also slightly lowers reliability. (DEBUG_SYNC vs session sync issues)
# - TS_DBG_CLI_OUTPUT: ONLY activate for debugging. We need top speed for the mysql CLI to reproduce multi-threaded issues accurately
#   This turns on -vvv debug output for the mysql client (Best left disabled=default=0)
#   Turning this on *will* significantly reduce (if not completely nullify) issue reproducibility due to excessive disk logging
# - TS_DS_TIMEOUT: Number of seconds to wait in a DEBUG_SYNC lock situation before terminating current DEBUG_SYNC lock holds
# - TS_VARIABILITY_SLEEP: Number of seconds to wait before a new transaction set is processed (may slightly increase/decrease issue reproducibility)
#   Suggested values: 0 (=default) or 1. This is one of the first parameters to test (change from 0 to 1) if a ThreadSync issue is not reproducible
# - WORKDIR_LOCATION: Select which medium to use to store the working directory (Note that some issues require the extra speed of setting 1,2 or 3 to reproduce)
#   (Note that the working directory is also copied to /tmp/ after the reducer run finishes if tmpfs or ramfs are used)
#   - WORKDIR_LOCATION=0: use /tmp/ (disk bound)
#   - WORKDIR_LOCATION=1: use tmpfs (default)
#   - WORKDIR_LOCATION=2: use ramfs (setup: sudo mkdir -p /mnt/ram; sudo mount -t ramfs -o size=4g ramfs /mnt/ram; sudo chmod -R 777 /mnt/ram;)
#   - WORKDIR_LOCATION=3: use a specific storage device (like an ssd or other [fast] storage device), mounted as WORKDIR_M3_DIRECTORY
# - WORKDIR_M3_DIRECTORY: If WORKDIR_LOCATION is set to 3, then this directory is used
# - STAGE1_LINES: When the testcase becomes smaller than this number of lines, proceed to STAGE2 (default=90)
#   Only change if reducer keeps trying to reduce by 1 line in STAGE1 for a long time (seen very rarely)
# - MYEXTRA: Extra options to pass to myqsld
#   - Also, --no-defaults as set in the default is removed automatically later on. It is just present here to highlight it's effectively (seperately) set.
# - BASEDIR: Full path to MySQL basedir (example: "/mysql/mysql-5.6").
#   If the directory name starts with '/mysql/' then this may be ommited (example: BASEDIR="mysql-5.6-trunk")
# - MULTI_THREADS: This option was an internal one only before. Set it to change the number of threads Reducer uses for the verify stage intially, and for reduction of sproradic issues if the verify stage found it is a sporadic issue. Recommended: 10, based on experience/testing/time-proven correctness.
#   Do not change unless you need to. Where this may come in handy, for a single occassion, is when an issue is hard to reproduce and very sporadic. In this case you could activate FORCE_SKIPV (and thus automatically also FORCE_SPORADIC) which would skip the verify stage, and set this to a higher number for
#   example 20 or 30. This would then immediately boot into 20 or 30 threads trying to reduce the issue with subreducers (note: thus 20 or 30x mariadbd/mysqld...)
#   A setting less then 10 is really not recommended as a start since sporadic issues regularly only crash a few threads in 10 or 20 run threads.
# - MULTI_THREADS_INCREASE: this option configures how many threads are added to MULTI_THREADS if the original MULTI_THREADS setting did not prove to be sufficient to trigger a (now declared highly-) sporadic issue. Recommended is setting 5 or 10. Note that reducer has a limit of MULTI_THREADS_MAX (50)
#   threads (this literally means 50x mariadbd/mysqld + client thread(s)) as most systems (including high-end servers) start to seriously fail at this level (and earlier) Example; if you set MULTI_THREADS to 10 and MULTI_THREADS_INCREASE to 10, then the sequence (if no single reproduce can be established) will be:
#   10->20->30->40->50->Issue declared non-reproducible and program end. By this stage, the testcase has executed 6 verify levels *(10+20+30+40+50)=900 times.
#   Still, even in this case there are methods that can be employed to let the testcase reproduce. For further ideas what to do in these cases, see; https://github.com/mariadb-corporation/mariadb-qa/blob/master/reproducing_and_simplification.txt
# - FORCE_SPORADIC=0 or 1: If set to 1, STAGE1_LINES setting is ignored and set to 3, unless it was set to a non-default number (i.e. !=90 - to enable reduction of issues via MULTI until a given amount of lines is reached, which is handy for tools like pquery-reach.sh where a mix of sporadic and non-sporadic issues may be seen). MULTI reducer mode is used after verify, even if issue is found to seemingly not be sporadic (i.e. all verify threads reproduced the issue). This can be handy for issues which are very slow to reduce or which, on visual inspection of the testcase reduction
#   process are clearly sporadic (i.e. it comes to 2 line chunks with still thousands of lines in the testcase and/or there are many trials without the issue being observed. Another situation which would call for use of this parameter is when produced testcases are still greater then 15 to 80 lines - this also indicates a possibly sporadic issue (even if verify stage manages to produce it against all started subreducer threads).
#   Note that this may be a bug in reducer too - i.e. a mismatch between verify stage and stage 1. Yet, if that were true, the issue would likely not reproduce to start with. Another plausible reason for this occurrence (all threads verified in verify stage but low frequency reproduction later on) is the existence of all threads in verify stage vs 1 thread in stage 1. It has been observed that a very loaded server (or using Valgrind as it also slows the code down significantly) is better at reproducing (many) issues then a low-load/single-thread-running machine. Whatever the case, this option will help.
# - FORCE_SKIV=0 or 1: If set to 1, FORCE_SPORADIC is automatically set to 1 also. This option skips the verify stage and goes straight into testcase reduction mode. Ideal for issues that have a very low reproducibility, at least initially (usually either increases or decreases during a simplification run.)
#   Note that skipping the verify stage means that you may not be sure if the issue is reproducibile untill it actually reproduces (how long is a piece of string), and the other caveat is that the verify stage normally does some very important inital simplifications which is now skipped. It is suggested that
#   if the issue becomes more reproducible during simplification, to restart reducer with this option turned off. This way you get the best of both worlds.
# - PQUERY_MULTI=0 or 1: If set to 1, FORCE_SKIV (and thus FORCE_SPORADIC) are automatically set to 1 also. This is true multi-threaded testcase reduction, and it is based on random replay. Likely this will be slow, but effective. Beta quality. This option removes the --no-shuffle option for pquery (i.e.
#   random replay) and sets pquery options --threads=x (x=PQUERY_MULTI_CLIENT_THREADS) and --queries=5*testcase size. It also sets the number of subreducer threads to PQUERY_MULTI_THREADS. To track success/status, view reducer output and/or check error logs;
#   $ grep -E --binary-files=text "Assertion failure" /dev/shm/{reducer's epoch}/subreducer/*/error.log
#   Note that, idem to when you use FORCE_SKIV and/or FORCE_SPORADIC, STAGE1_LINES is set to 3. Thus, reducer will likely never completely "finish" (3 line testases are somewhat rare), as it tries to continue to reduce the test to 3 lines. Just watch the output (reducer continually reports on remaining number of lines and/or filesize) and decide when you are happy with the lenght of any reduced testcase. Suggested for developer convenience; 5-10 lines or less.
# - PQUERY_MULTI_THREADS: Think of this variable as "the initial setting for MULTI_THREADS" when PQUERY_MULTI mode is enabled; the initial number of subreducers
# - PQUERY_MULTI_CLIENT_THREADS: The number of client threads used for PQUERY_MULTI (see above) replays (i.e. --threads=x for pquery)
# - PQUERY_MULTI_QUERIES: The number of queries to execute for each and every trial before pquery ends (unless the server crashes/asserts). Must be sufficiently high, given that the random replay which PQUERY_MULTI employs may not easily trigger an issue (and especially not if also sporadic)
# - PQUERY_REVERSE_NOSHUFFLE_OPT=0 or 1: If set to 1, PQUERY_MULTI runs will use --no-shuffle (the reverse of normal operation), and standard pquery (not multi-threaded) will use shuffle (again the reverse of normal operation). This is a very handy option to increase testcase reproducibility. For example, when
#   reducing a non-multithreaded testcase (i.e. normally --no-shuffle would be in use), and reducer.sh gets 'stuck' at around 60 lines, setting this to on will start replaying the testcase randomly (shuffled). This may increase reproducibility. The final run scripts will have matching --no-shuffle or
#   shuffle (i.e. no --no-shuffle present) set. Note that this may mean that a testcase has to be executed a few or more times given that if shuffle is active (pquery's default, i.e. no --no-shuffle present), the testcase may replay differently then to what is needed. Powerful option, slightly confusing.
# - TIMEOUT_COMMAND: this can be used to set a timeout command for mariadbd/mysqld. It is prefixed to the mariadbd/mysqld startup. This is handy when encountering a shutdown or server hang issue. When the timeout is reached, mariadbd/mysqld is terminated, but reduction otherwise happens as normal. Note that reducer will need some way to establish that an actual problem was triggered. For example, suppose that a shutdown issue shows itself in the error log by starting to output INNODB
#   STATUS MONITOR output whenever the shutdown issue is occuring (i.e. server refuses to shutdown and INNODB STATUS MONITOR output keeps looping & end of the SQL input file is apparently never reached). In this case, after a timeout of x minutes, thanks to the TIMEOUT_COMMAND, mariadbd/mysqld is terminated. After the termination, reducer checks for "INNODB MONITOR OUTPUT" (MODE=3). It sees or not sees this output, and hereby it can continue to reduce the testcase further. This would have been using MODE=3 (check error log output). Another method may be to interleave the SQL with a SHOW PROCESSLIST; and then
#   check the client output (MODE=2) for (for example) a runaway query. Different are issues where there is a 1) complete hang or 2) an issue that does not or cannot!) represent itself in the error log/client log etc. In such cases, use TIMEOUT_CHECK and MODE=0.
# - TIMEOUT_CHEK: used when MODE=0. Though there is no connection with TIMEOUT_COMMAND, the idea is similar; When MODE=0 is active, a timeout command prefix for mariadbd/mysqld is auto-generated by reducer.sh. Note that MODE=0 does NOT check for specific TEXT string issues. It just checks if a timeout was reached at the end of each trial run. Thus, if a server was hanging, or a statement ran for a very long time (if not terminated by the QUERYTIMEOUT setting), or a shutdon was initiated but never completed etc. then reducer.sh will notice that the timeout was reached, and thus assume the issue reproduced. Always set this setting at least to 2x the expected testcase run/duration lenght in seconds + 30 seconds extra. This longer duration is to prevent false positives. Reducer auto-sets this value as the timeout for mariadbd/mysqld, and checks if the termination of mariadbd/mysqld was within 30 seconds of this duration.
# - FORCE_KILL=0 or 1: If set to 1, then reducer.sh will forcefully terminate mariadbd/mysqld instead of using mariadb-admin/mysqladmin. This can be used when for example authentication issues prevent mariadb-admin/mysqladmin from shutting down the server cleanly. Normally it is recommended to leave this =0 as certain issues only present themselves at the time of mariadbd/mysqld shutdown. However, in specific use cases it may be handy. Not often used. Auto-disabled for MODE=0.

# ======== Gotcha's
# - When any form of random replay is used (for example when using PQUERY_REVERSE_NOSHUFFLE_OPT=1 with PQUERY_MULTI=0 or when using PQUERY_MULTI=1 with PQUERY_REVERSE_NOSHUFFLE_OPT=0, or when using FIREWORKS=1), then there is a risk that DROP_C is not executed, i.e. reducer will try and run queries against no database. To avoid this in the future, on 24-08-20 RV updated all pquery and CLI call commands to auto-connect to the TEST database. While this has other implications (reduction will be able to remove the USE test; line eventually for example), this looks to be the best way forward to have maximum issue reproducibility.
# - When reducing an SQL file using for example FORCE_SKIPV=1, FORCE_SPORADIC=1, PQUERY_MULTI=0, PQUERY_REVERSE_NOSHUFFLE_OPT=1, USE_PQUERY=1, then reducer will replay the SQL file, using pquery (USE_PQUERY=1), using a single client (i.e. pquery) thread against mariadbd/mysqld (PQUERY_MULTI=0), in a sql shuffled order (PQUERY_REVERSE_NOSHUFFLE_OPT=1) untill (FORCE_SKIPV=1 and FORCE_SPORADIC=1) it hits a bug. But notice that when the partially reduced file is written as _out, it is normally not valid to re-start reducer using this _out file (for further reduction) using PQUERY_REVERSE_NOSHUFFLE_OPT=0. The reason is that the sql replay order was random, but _out is generated based on the original testcase (sequential). Thus, the _out, when replayed sequentially, may not re-hit the same issue. Especially when things are really sporadic this can mean having to wait long and be confused about the results. Thus, if you start off with a random replay, finish with a random replay, and let the final bug testcase (auto-generated as {epoch}.*) be random replay too! See also the multirun scripts as generated inside basedirs (by startup.sh).

# ======== General develoment information
# - Subreducer(s): these are multi-threaded runs of reducer.sh started from within reducer.sh. They have a specific role, similar to the main reducer.
#   At the moment there are only two such specific roles: verfication (reproducible yes/no + sporadic yes/no) and simplification (terminate a subreducer batch
#   (all of it) once a simpler testcase is found by one of the subthreads (subreducers), and use that testcase to again start new simplification subreducers.)
# - The files that are initially seen in the root working directory (i.e. $WORKD) are those generated by the step "[Init] Setting up data directory standard working template", they are not an actual replay of any SQL file, at least not intitially; once the processing continues past this initial template creation, then the results
#   (i.e. the results of actual replays of SQL) will be in either;
#   - The subreducer directories $WORKD/subreducer/<nr>/ (ref above), provided reducer.sh is working in MULTI mode (even the standard VERIFY stage is MULTI)
#   - Or, they will be in the same aforementioned directory $WORKD (and the output files from the initial template creation will now have been overwritten, though not the actual template), provided reducer.sh is working in single-threaded reduction mode (i.e. MULTI mode is not active).
# - Never use grep, always use egrep. See the next line why. Remember also that [0-9]\+ (a regex valid for grep) is written as [0-9]+ when using egrep/grep -E --binary-files=text.
#   grep -E --binary-files=text is the same as egrep. It is best to use grep -E --binary-files=text because egrep will likely be deprecated from various OS'es at some point.
# - When using grep -E --binary-files=text, ALWAYS use --binary-files=text to avoid issues with hex characters causing non-reproducibility and/or grep playing up. If you see things like 'Binary file ... matches' as grep output it means you have executed grep against a file with binary chars, which is seen by the system as a binary file (even though it may be a flat sql text file with a few hex characters in it). Adding the --binary-files=text will correctly process the file.

# ======== Ideas for improvement
# - A SUBREDUCER_TIMEOUT=x option which by default is turned off, i.e. set to 0 but otherwise places a timeout (with kill -9) on the Bash shell (or similar) for subreducers, and restart the shell (or similar) if the timeout is hit. This will avoid any (if any) stuck subreducers. Frequency of running into this is likely low to start with
# - The write of the file should be atomic - i.e. if reducer is interrupted during a testcase_out write, the file may be faulty. Check if this is so & fix
# - A new mode could do this; main thread (single): run SQL, secondary thread (new functionality): check SHOW PROCESSLIST for certain regex TEXT regularly. This would allow creating testcases for queries that have a long runtime. This new functionality likely will live outside process_outcome() as it is a live check
# - Incorporate 3+ different playback options: SOURCE ..., redirection with <, redirection with cat, (stretch goal; replay via MTR), etc. (there may be more)
#   THIS FUNCTIONALITY WAS ADDED 09-06-2016. "An expansion of this..." below is not implmeneted yet
#   - It has been clearly shown that different ways of replaying SQL may trigger a bug where other replay options do not. This looks to be more related to for example timing/server access method then to an inherent/underlying bug in for example the mysql client (CLI) workings. As such, the "resolution" is not to change ("fix") the client instead exploit this difference between replay options to trigger/reproduce bugs/replay test cases in multiple ways.
#   - An expansion of this could be where the initial stage (as it goes through it's iterations) replays each next iteration with a different replay method.
#     This is not 100% covering however, as the last stage (with the least amount of changes to the SQL input file) would replay with replay method/option x, while x may not be the replay option which triggers the bug at hand. As such, a few more verify stage rounds (there's 6 atm - each with 10 replay threads) may be needed to replay (partly "again", but this time with the least changed SQL file) the same SQL with each replay option. This would thus result in reducer needing a bit more time to do the VERIFY stage, but likely with good improved bug reproducibility. Untill this functionality is implemented, see the following file/page for reproducing & simplification ideas, which (if all followed diligently) usually result in bugs becoming reproducible; https://github.com/mariadb-corporation/mariadb-qa/blob/master/reproducing_and_simplification.txt
# - MDG Node work: rm -Rf's in other places (non-supported subreducers for example) will need sudo. Also test for sudo working correctly upfront
# - Add a MYEXTRA simplificator at end (extra stage) so that mariadbd/mysqld options are minimal
# - Improve ";" work in STAGE4 (";" sometimes missing from results - does not affect reproducibility)
# - Improve VALGRIND/ERRORLOG run work (complete?)
# - Improve clause elimination when sub queries are used: "ORDER BY f1);" is not filtered due to the ending ")"
# - Keep 'success counters' over time of regex replacements so that reducer can eliminate those that are not effective
#   Do this by proceduralizing the sed and then writing the regexes to a file with their success/failure rates
# - Include a note for Valgrind runs on a "universal" string - a string which would be found if there were any valgrind errors
#   Something like "[1-9]* ERRORS" or something
# - Keep counters over time of which sed's have been successfull or not. If after many different runs, a sed remains 0 success, remove it
# - Proceduralize stages and re-run STAGE2 after the last stage as this is often beneficial for # of lines (and remove last [Info] line in [Finish])
# - Have to find some solution for the crash in tzinfo where reducer needs to use a non-Valgrind-instrumented build for tzinfo
# - (process) script could pass all RQG-set extra mariadbd/mysqld options into MYEXTRA or another variable to get non-reproducible issues to work
# - STAGE6: can be improved slightly furhter. See function for ideas.
#   Also, the removal of a column fails when a CREATE TABLE statement includes KEY(col), so maybe these keys can be pre-dropped or at the same time
#   Also, try and swap any use of the column to be removed to the name of column-1 (just store it in a variable) to avoid column missing error
#   And at the same time still promote removal of the said column
# - start_mysqld_main() needs a bit more work to generate the $WORK_RUN file for MODE6+ as well (multiple $WORKO files are used in MODE6+)
#   Also remove the ifthen in finish() which test for MODE6+ for this and reports that implementation is not complete yet
# - STAGE6: 2 small bugs (ref output lines below): 1) Trying to eliminate a col that is not one & 2) `table0_myisam` instead of table0_myisam
#   Note that 2) may not actually be a bug; if the simplifacation of "'" failed for a sporadic testcase (as is the case here), it's hard to fix (check)
#   | 2013-08-19 10:35:04 [*] [Stage 6] [Trial 2] [Column 22/22] Trying to eliminate column '/*Indices*/' in table '`table0_myisam`'
#   | sed: -e expression #1, char 41: unknown command: `*'
# - Need another MODE which will look for *any* Valgrind issue based on the error count not being 0 (instead of named MODE1)
#   Make a note that this may cause issues to be missed: often, after simplification, less Valgrind errors are seen as the entire SQL trace likely contained a number of issues, each originating from different Valgrind statements (can multi-issue be automated?)
# - Need another MODE which will attempt to crash the server using the crashing statement from the log, directly starting the vardir left by RQG. If this works, dump the data, add crashing statement and load in a fresh instance and re-try. If this works, simplify.
# - "Previous good testcase backed up as $WORKO.prev" was only implemented for 1) parent seeing a new simplification subreducer testcase and
#   2) main single-threaded reducer seeing a new testcase. It still needs to be added to multi-threaded (ThreadSync) (i.e. MODE6+) simplification. (minor)
# - Multi-threaded simplification: thread-elimination > DATA + SQL threads simplified as if "one file" but accross files.
#   Hence, all stages need to be updated to be multi-threaded/TS aware. Fair amount of work, but doable.
#   See initial section of 'Verify' for some more information around multi_reducer_decide_input
# - Multi-threaded simplification: # threads left + non-sporadic: attempt all DATA+SQL1+SQLx combinations. Then normal simplify.
#   Sporadic: normal simplify immediately.
# - Multi-threaded simplification of sporadic issues: could also start # subreducer sessions and have main reducer watch for _out creation.
#   Once found, abort all live subreducer threads and re-init with found _out file. Maybe a safety copy of original file should be used for running.
# - MODE9 work left
#   - When 2 threads are left (D+2T) then try MODE4 immediately instead of executing x TS_TE_ATTEMPTS attempts
#   - In single thread replay it should always do grep -E --binary-files=text -v "DEBUG_SYNC" as DEBUG_SYNC does not make sense there (cosmetic, would be filtered anyway)
#   - bash$ echo -ne "test\r"; echo "te2" > use this implementation for same-line writing of threa fork commands etc
#   - TS_TRXS_SETS "greps" not fully corret yet: setting this to 10 lead to 2x main delay while it should have been 10. Works correctly when "1"
#   - TS_TRXS_SETS processing can be automated - and this is the simplification: test last, test last+1, test last+2, untill crash. (or chuncks?)
#   - Check if it is a debug server by issuing dummy DEBUG_SYNC command and see if it waits (TIMEOUT?)
#   - cut_threadsync_chunk is not in use at the moment, this will be used? but try ts_thread_elimination first
# - Need to capture interrupt (CTRL+C) signal and do some end-processing (show info + locations + copy to tmp if tmpfs/ramfs used)
# - If "sed: -e expression #1, char 44: unknown option to `s'" text or similar is seen in the output, it is likely due to the #VARMOD# block
#   replacement in multi_reducer() failing somewhere. Update RV 16/9: Added functionality to fix/change ":" to "\:" ($FIXED_TEXT) to avoid this error.
# - Implement cmd line options instead of in-file options. Example:
#   while [ "$1" != ""]; do
#    case $1 in
#      -m | --mode     shift;MODE=$1;;   # shift to get actual file name into $1
#      -f | --file     shift;file=$1;;
#      *)              no_options;exit 1;;
#    esac
#    shift
#   done
# - Optimization: let 'Waiting for any forked subreducer threads to find a shorter file (Issue is deemed to be sporadic: this may take time)' work for 30 minutes
#   or so, depending on file size. If no issue is found by then, restart or increase number of threads by 5.

# ======== Internal variable Reference
# $WORKD = Working directory (i.e. likely /tmp/<epoch>/ or /dev/shm/<epoch>)
# $INPUTFILE = The original input file (the file to reduce). This file, and this variable, are never changed (to protect the original file from being changed).
# $WORK_BUG_DIR = The directory in which the original input file resides (i.e. where $INPUTFILE resides, which may have been set to $1 specifically as well). In this directory the output files will be stored
# $WORKF = This is *originally* a copy of $INPUTFILE, seen in the working directory as $WORKD/in.sql
#   work   From it are then made chunk deletes etc. and the result is stored in the $WORKT file. Then, $WORKT ovewrites $WORKF when
#   file   a [for MODE4+9: "likely the same", for other MODES: "the same"] issue was located when executing $WORKT
# $WORKT = A temporary "made smaller" (and thus changed) version of $WORKF, seen in the working directory as $WORKD/in.tmp
#   temp   It may or may not cause the same issue like $WORKF can. This file is overwritten each time a new "to be tested" version is being created
#   file   $WORKT overwrites $WORKF and $WORKO when a [for MODE4+9: "likely the same", for other MODES: "the same"] issue was located when executing $WORKT
# $WORKO = The reduced version of $WORKF, stored in the same directory of the original input file as <name>_out
#   outf   This file definitely causes the same issue as $INPUTFILE can, while being smaller
# $WORK_INIT, $WORK_START, $WORK_STOP, $WORK_CL, $WORK_RUN, $WORK_RUN_PQUERY: Vars that point to various start/run scripts that get added to testcase working dir
# $WORK_OUT: an eventual copy of $WORKO, made for the sole purpose of being used in combination with $WORK_RUN etc. This makes it handy to bundle them as all
#   of them use ${EPOCH} in the filename, so you get {some_epochnr}_start/_stop/_cl/_run/_run_pquery/.sql

# Disable history substitution and avoid  -bash: !: event not found  like errors
set +H

# Provision ABORT_ACTIVE
ABORT_ACTIVE=0

# Random entropy init
RANDOM=$(date +%s%N | cut -b10-19 | sed 's|^[0]\+||')

# Ensure MYPORT is not set
export -n MYPORT
MYPORT=

# Set SAN options
# https://github.com/google/sanitizers/wiki/SanitizerCommonFlags
# https://github.com/google/sanitizers/wiki/AddressSanitizerFlags
# https://clang.llvm.org/docs/UndefinedBehaviorSanitizer.html
# https://github.com/google/sanitizers/wiki/AddressSanitizerLeakSanitizer (LSAN is enabled by default except on OS X)
# detect_invalid_pointer_pairs changed from 1 to 3 at start of 2021 (effectively used since)
export ASAN_OPTIONS=suppressions=${HOME}/mariadb-qa/ASAN.filter:quarantine_size_mb=512:atexit=0:detect_invalid_pointer_pairs=3:dump_instruction_bytes=1:abort_on_error=1:allocator_may_return_null=1
# check_initialization_order=1 cannot be used due to https://jira.mariadb.org/browse/MDEV-24546 TODO
# detect_stack_use_after_return=1 will likely require thread_stack increase (check error log after ./all) TODO
#export ASAN_OPTIONS=suppressions=${SCRIPT_PWD}/ASAN.filter:quarantine_size_mb=512:atexit=0:detect_invalid_pointer_pairs=3:dump_instruction_bytes=1:abort_on_error=1:allocator_may_return_null=1
export UBSAN_OPTIONS=suppressions=${HOME}/mariadb-qa/UBSAN.filter:print_stacktrace=1:report_error_type=1
export TSAN_OPTIONS=suppress_equal_stacks=1:suppress_equal_addresses=1:history_size=7:verbosity=1
export MSAN_OPTIONS=abort_on_error=1:poison_in_dtor=0

# Flags
FIRST_MYSQLD_START_FLAG=1  # Avoids FORCE_KILL=1 from being used at '[Init] Attempting first mariadbd/mysqld startup with all MYEXTRA options passed' stage.

# ===== [SPECIAL MYEXTRA SECTION START] Preparation for STAGES 8 and 9: special MYEXTRA startup option sets handling
# Important: If you add a section below for additional startup option sets, be sure to add the final outcome to SPECIAL_MYEXTRA_OPTIONS at the end of this section (marked by "[SPECIAL MYEXTRA SECTION END]")
#            And additionaly to add a new trial in STAGE9 to cover the additional startup option set created here.
SPECIAL_MYEXTRA_OPTIONS=
# === Check TokuDB & RocksDB storage engine options, .so availability, split options into ROCKSDB and TOKUDB variables, and cleanup MYEXTRA to remove the related options
# SE Removal approach; 1) If the engine is referred to by .so reference in MYEXTRA, reducer.sh uses it, but reducer.sh ensure the engine .so file exists
#                      2) Any reference to the engine is removed from MYEXTRA and stored in two variables TOKUDB/ROCKSDB to allow more control/testcase reducability
#                      3) Testcase reduction removal of engines (one-by-one) is tested in STAGE9

TOKUDB=
ROCKSDB=
#Check BASEDIR and auto-update to a build in /data/VARIOUS_BUILDS/ if BASEDIR directory does not exist
BASEDIR_ALT="$(echo "${BASEDIR}" | sed 's|/test/|/data/VARIOUS_BUILDS/|')"  # Check /data/VARIOUS_BUILDS (and use any dir found there if BASEDIR does not exist), as it often contains older BASEDIR directories. This aids in just starting reducer.sh without having to update the BASEDIR path/directory
#if [ ! -d "${PWD}" -a ! -d "${BASEDIR_ALT}" ]; then
if [ ! -d "${BASEDIR}" -a ! -d "${BASEDIR_ALT}" ]; then  # RV 19/2/24: Changed PWD to BASEDIR as PWD does not make sense?
  #echo "Assert: Neither '${PWD}' nor '${BASEDIR_ALT}' directories exist, please set the BASEDIR variable correctly"
  echo "Assert: Neither '${BASEDIR}' nor '${BASEDIR_ALT}' directories exist, please set the BASEDIR variable correctly"
  exit 1
elif [ -d "${BASEDIR_ALT}" ]; then  # BASEDIR not found, but BASEDIR_ALT (/data/VARIOUS_BUILDS/ archive) found
  echo "Note: Updating BASEDIR from '${BASEDIR}' to '${BASEDIR_ALT}' as set BASEDIR did not exist, but the same/required server build was found in /data/VARIOUS_BUILDS/"
  sleep 2
  BASEDIR="${BASEDIR_ALT}"
fi
BASEDIR_ALT=
# Workaround, ref https://github.com/google/sanitizers/issues/856
# This will show even for simple version detection, causing it to fail if the vm.mmap_rnd_bits workaround is not set
#==180506==Shadow memory range interleaves with an existing memory mapping. ASan cannot proceed correctly. ABORTING.
#==180506==ASan shadow was supposed to be located in the [0x00007fff7000-0x10007fff7fff] range.
#==180506==This might be related to ELF_ET_DYN_BASE change in Linux 4.12.
#==180506==See https://github.com/google/sanitizers/issues/856 for possible workarounds.
#==180506==Process memory map follows:
#...
#==180506==End of process memory map.
#This workaround is no longer needed, provided another workaround (set soft/hard stack 16000000 in /etc/security/limits.conf instead of unlimited) is present. Ref same ticket, later comments.
#if [[ "${BASEDIR}" == *"SAN"* ]]; then sudo sysctl vm.mmap_rnd_bits=28; fi  # Workaround, ref https://github.com/google/sanitizers/issues/856
#Check replication option
if [ $REPLICATION -ne 1 ]; then  # If replication is not active, we do not want any REPL_EXTRA, MASTER_EXTRA and SLAVE_EXTRA options to take effect
  REPL_EXTRA=
  MASTER_EXTRA=
  SLAVE_EXTRA=
fi
#Check rr binary location and set startup option
export RR_OPTIONS=
if [[ ${RR_TRACING} -eq 1 ]]; then
  if [[ -z $(which rr) ]]; then
    echo "Assert: rr binary not found! Please install rr and ensure:  which rr  works correctly at the command line"
    exit 1
  fi
  export RR_OPTIONS="$(which rr) record --chaos"
fi
if [[ "${MYEXTRA}" == *"ha_rocksdb.so"* ]]; then
  if [ -r ${BASEDIR}/lib/mysql/plugin/ha_rocksdb.so ]; then
    ROCKSDB="$(echo "${MYEXTRA}" | grep -o "\-\-plugin[-_][^ ]\+ha_rocksdb.so" | head -n1)"  # Grep all text including and after ' --plugin[-_]' (upto any space as a new option starts there) upto and including the last 'ha_rocksdb.so' for that option
    MYEXTRA="$(echo "${MYEXTRA}" | sed "s|${ROCKSDB}||g")"
    # The below issues should never happen in the Percona pquery framework as we simply use;
    # --plugin-load-add=tokudb=ha_tokudb.so --tokudb-check-jemalloc=0 --plugin-load-add=rocksdb=ha_rocksdb.so --init-file=${HOME}/mariadb-qa/plugins_57.sql
    # And the init-file loads any other required plugins using the same .so file. These options (in MYEXTRA) are not complex and easy too parse as per below -
    # and this is handled fine by the code here. It would only happen if someone used a complex string like the one shown in https://jira.percona.com/browse/DOC-444
    if [[ "${MYEXTRA}" == *"ha_rocksdb.so"* ]]; then
      echo "Error: The MYEXTRA string is formulated in a seemingly complex manner; it should contain (per engine) only one '--plugin-load[-add]=...ha_....so' (and note that --plugin-load can only be used once; perhaps best to use --plugin-load-add for each engine)."
      echo "Please simplify it, or improve the code in reducer.sh which handles this (search for this text)."
      echo "Terminating now."
      exit 1
    elif [[ "${ROCKSDB}" == *"ha_tokudb.so"* ]]; then
      echo "Error: The MYEXTRA string is formulated in a seemingly complex manner; it should contain (per engine) only one '--plugin-load[-add]=...ha_....so' (and note that --plugin-load can only be used once; perhaps best to use --plugin-load-add for each engine)."
      echo "It looks like the ha_tokudb.so plugin load call was nested inside the --plugin-load[-add]=...ha_rocksdb.so plugin load call."
      echo "Please simplify it by using a separate --plugin-load-add for each engine, or improve the code in reducer.sh which handles this (search for this text) to extract the TokuDB load code into the TOKUDB variable at this point in the code (complex)."
      echo "Terminating now."
      exit 1
    fi
  else
    echo "Error: MYEXTRA contains ha_rocksdb.so, yet ${BASEDIR}/lib/mysql/plugin/ha_rocksdb.so des not exist."
    echo "Terminating now."
    exit 1
  fi
fi
if [ "${DISABLE_TOKUDB_AND_JEMALLOC}" -eq 0 ]; then
  if [[ "${MYEXTRA}" == *"ha_tokudb.so"* ]]; then
    if [ -r ${BASEDIR}/lib/mysql/plugin/ha_tokudb.so ]; then
      TOKUDB="$(echo "${MYEXTRA}" | grep -o "\-\-plugin[-_][^ ]\+ha_tokudb.so" | head -n1)"  # Grep all text including and after '--plugin[-_]' (upto any space as a new option starts there) upto and including the last 'ha_tokudb.so' for that option
      MYEXTRA="$(echo "${MYEXTRA}" | sed "s|${TOKUDB}||g")"
      if [[ "${MYEXTRA}" == *"--tokudb"[-_]"check"[-_]"jemalloc"* ]]; then
        TOKUDBJC="$(echo "${MYEXTRA}" | grep -o "\-\-tokudb[-_]check[-_]jemalloc[^ ]*" | head -n1)"  # Grep all text including and after '--tokudb[-_]check[-_]jemalloc' upto the first space
        MYEXTRA="$(echo "${MYEXTRA}" | sed "s|${TOKUDBJC}||g")"
        TOKUDB="$(echo "${TOKUDB} ${TOKUDBCJ}")"
      fi
      # The below issues should never happen in the Percona pquery framework; ref info above in ha_rocksdb.so section with the same start as this line
      if [[ "${MYEXTRA}" == *"ha_tokudb.so"* ]]; then
        echo "Error: The MYEXTRA string is formulated in a seemingly complex manner; it should contain (per engine) only one '--plugin-load[-add]=...ha_....so' (and note that --plugin-load can only be used once; perhaps best to use --plugin-load-add for each engine)."
        echo "Please simplify it, or improve the code in reducer.sh which handles this (search for this text)."
        echo "Terminating now."
        exit 1
      elif [[ "${TOKUDB}" == *"ha_rocksdb.so"* ]]; then
        echo "Error: The MYEXTRA string is formulated in a seemingly complex manner; it should contain (per engine) only one '--plugin-load[-add]=...ha_....so' (and note that --plugin-load can only be used once; perhaps best to use --plugin-load-add for each engine)."
        echo "It looks like the ha_rocksdb.so plugin load call was nested inside the --plugin-load[-add]=...ha_tokudb.so plugin load call."
        echo "Please simplify it by using a separate --plugin-load-add for each engine, or improve the code in reducer.sh which handles this (search for this text) to extract the RocksDB load code into the ROCKSDB variable at this point in the code (complex)."
        echo "Terminating now."
        exit 1
      fi
    else
      echo "Error: MYEXTRA contains ha_tokudb.so, yet ${BASEDIR}/lib/mysql/plugin/ha_tokudb.so des not exist."
      echo "Terminating now."
      exit 1
    fi
  fi
  if [[ "${MYEXTRA}" == *"--tokudb"[-_]"check"[-_]"jemalloc"* ]]; then
    echo "Error: MYEXTRA contains --tokudb-check-jemalloc, yet ha_tokudb.so is not present in the MYEXTRA string."
    echo "Terminating now."
    exit 1
  fi
fi
# === Check binary log encryption options, split it into a BL_ENCRYPTION variable, and cleanup MYEXTRA to remove the related options
BL_ENCRYPTION=
if [[ "${MYEXTRA}" == *"encrypt"[-_]"binlog"* ]]; then
  if [[ ! "${MYEXTRA}" == *"master"[-_]"verify"[-_]"checksum"* ]]; then
    echo "Error: --encrypt-binlog is present in MYEXTRA whereas --master-verify-checksum is not (as required by binary log encryption). Please fix this."
    echo "Terminating now."
    exit 1
  fi
  if [[ ! "${MYEXTRA}" == *"binlog"[-_]"checksum"* ]]; then
    echo "Error: --encrypt-binlog is present in MYEXTRA whereas --binlog-checksum is not (as required by binary log encryption). Please fix this."
    echo "Terminating now."
    exit 1
  fi
  BL_ENCRYPTION="$(echo "${MYEXTRA}" | grep -o "\-\-encrypt[-_]binlog[^ ]*" | head -n1)"  # Grep all text including and after '--encrypt_binlog' upto the first space
  MYEXTRA="$(echo "${MYEXTRA}" | sed "s|${BL_ENCRYPTION}||g")"
  BL_ENCRYPTIONMVC="$(echo "${MYEXTRA}" | grep -o "\-\-master[-_]verify[-_]checksum[^ ]*" | head -n1)"  # Grep all text including and after '--master[-_]verify[-_]checksum' upto the first space
  MYEXTRA="$(echo "${MYEXTRA}" | sed "s|${BL_ENCRYPTIONMVC}||g")"
  BL_ENCRYPTIONBC="$(echo "${MYEXTRA}" | grep -o "\-\-binlog[-_]checksum[^ ]*" | head -n1)"  # Grep all text including and after '--binlog[-_]checksum' upto the first space
  MYEXTRA="$(echo "${MYEXTRA}" | sed "s|${BL_ENCRYPTIONBC}||g")"
  BL_ENCRYPTION="$(echo "${BL_ENCRYPTION} ${BL_ENCRYPTIONMVC} ${BL_ENCRYPTIONBC}")"
fi
# === Check keyring file encryption options, split it into a KF_ENCRYPTION variable, and cleanup MYEXTRA to remove the related options
KF_ENCRYPTION=
if [[ "${MYEXTRA}" == *"plugin"[-_]"load=keyring_file.so"* ]]; then
  if [[ ! "${MYEXTRA}" == *"keyring"[-_]"file"[-_]"data"* ]]; then
    echo "Error: --[early-]plugin-load=keyring_file.so is present in MYEXTRA whereas --keyring_file_data (as required by the keyring file plugin) is not. Please fix this."
    echo "Terminating now."
    exit 1
  fi
  KF_ENCRYPTION="$(echo "${MYEXTRA}" | grep -o "\-\-[^ ]\+keyring_file.so" | head -n1)"  # Grep all text (which is not a space) including and after '--' upto and including 'keyring_file.so'
  MYEXTRA="$(echo "${MYEXTRA}" | sed "s|${KF_ENCRYPTION}||g")"
  if [[ "${MYEXTRA}" == *"--keyring"[-_]"file"[-_]"data"* ]]; then
    KF_ENCRYPTIONFD="$(echo "${MYEXTRA}" | grep -o "\-\-keyring[-_]file[-_]data[^ ]*" | head -n1)"  # Grep all text including and after '--keyring[-_]file[-_]data' upto the first space
    MYEXTRA="$(echo "${MYEXTRA}" | sed "s|${KF_ENCRYPTIONFD}||g")"
    KF_ENCRYPTION="$(echo "${KF_ENCRYPTION} ${KF_ENCRYPTIONFD}")"
  fi
else
  if [[ "${MYEXTRA}" == *"keyring"[-_]"file"[-_]"data"* ]]; then
    echo "Error: --keyring_file_data is present in MYEXTRA whereas --[early-]plugin-load=keyring_file.so is not. Please fix this."
    echo "Terminating now."
    exit 1
  fi
fi
# === Check Binary logging options, split it into a BINLOG variable, and cleanup MYEXTRA to remove the related options
BINLOG=
if [[ ${MDG} -ne 1 ]]; then
  if [[ "${MYEXTRA}" == *"server"[-_]"id"* ]]; then
    if [[ ! "${MYEXTRA}" == *"log"[-_]"bin"* ]]; then
      BIN_TO_USE="${BASEDIR}/bin/mariadbd"
      if [ ! -r "${BIN_TO_USE}" ]; then BIN_TO_USE="${BASEDIR}/bin/mysqld"; fi
      if [[ ! "$(${BIN_TO_USE} --no-defaults --version | grep -E --binary-files=text -oe '5\.[1567]|8\.[0-9]' | head -n1)" =~ ^8.[0-9]$ ]]; then  # version is not 8.0 (--log-bin is not required as it is default already (8.0 has binary logging enabled by default))
        echo "Error: --server-id is present in MYEXTRA whereas --log-bin is not. Please fix this."
        echo "Terminating now."
        exit 1
      else
        echo "Warning: --server-id is present in MYEXTRA whereas --log-bin is not. This is a valid setup for 8.0 in which binary logging is enabled by default already. Still, reduction may fail in STAGE9 as reducer has not been updated yet to handle this situation. As a workaround, add --log-bin to MYEXTRA, or simply stop at STAGE8 reduction, or add this functionality to STAGE9 and please push it back to the repository"
        # To add this functionality, it is likely required to just handle the --server-id option removal using the BINLOG variable whilst setting --log-bin=0 at the same time or something - and this would be a good improvement for 8.0 (and beyond) testcase reduction in any case, as it would show/prove whetter it is necesary to have binlog on or not for a given testcase
      fi
      BIN_TO_USE=
    fi
  fi
  if [[ "${MYEXTRA}" == *"log"[-_]"bin"* ]]; then
    BIN_TO_USE="${BASEDIR}/bin/mariadbd"
    if [ ! -r "${BIN_TO_USE}" ]; then BIN_TO_USE="${BASEDIR}/bin/mysqld"; fi
    if [[ ! "$(${BIN_TO_USE} --no-defaults --version | grep -E --binary-files=text -oe '5\.[1567]|8\.[0-9]' | head -n1)" =~ ^5.[156]$ ]]; then  # version is 5.7 or 8.0 and NOT 5.1, 5.5 or 5.6, i.e. --server-id is required
      if [[ ! "$(${BIN_TO_USE} --no-defaults --version | grep -E --binary-files=text -ioe 'mariadb' | head -n1)" =~ ^mariadb$ ]]; then  # For MariaDB this is not the case (at least for 10.5. TODO: check other versions)
        if [[ ! "${MYEXTRA}" == *"server"[-_]"id"* ]]; then
          echo "Error: The version of mysqld is 5.7 or 8.0 and a --bin-log option was passed in MYEXTRA, yet no --server-id option was found whereas this is required for 5.7 and 8.0."
          echo "Terminating now."
          exit 1
        fi
      fi
    fi
    BIN_TO_USE=
    BINLOG="$(echo "${MYEXTRA}" | grep -o "\-\-log[-_]bin[^ ]*" | head -n1)"  # Grep all text including and after '--log[-_]bin' upto a space
    MYEXTRA="$(echo "${MYEXTRA}" | sed "s|${BINLOG}||g")"
    if [[ "${MYEXTRA}" == *"--server"[-_]"id"* ]]; then
      BINLOGSI="$(echo "${MYEXTRA}" | grep -o "\-\-server[-_]id[^ ]*" | head -n1)"  # Grep all text including and after '--server[-_]id' upto the first space
      MYEXTRA="$(echo "${MYEXTRA}" | sed "s|${BINLOGSI}||g")"
      BINLOG="$(echo "${BINLOG} ${BINLOGSI}")"
    fi
    if [[ "${MYEXTRA}" == *"server"[-_]"id"* ]]; then
      echo "Error: --server-id seems to be present twice in MYEXTRA. Please remove at least one instance."
      echo "Terminating now."
      exit 1
    fi
  fi
fi
# === Check for ONLY_FULL_GROUP_BY sql mode, split it into a ONLYFULLGROUPBY variable, and cleanup MYEXTRA to remove the option
ONLYFULLGROUPBY=
if [[ "${MYEXTRA}" != *"--sql_mode=ONLY_FULL_GROUP_BY,"* ]]; then  # Avoid scenario where multiple sql_mode's are set, handling this would be mode complex (TODO)
  if [[ "${MYEXTRA}" == *"--sql_mode=ONLY_FULL_GROUP_BY"* ]]; then
    ONLYFULLGROUPBY="--sql_mode=ONLY_FULL_GROUP_BY"
    MYEXTRA="$(echo "${MYEXTRA}" | sed "s|${ONLYFULLGROUPBY}||g")"
  fi
fi
# ===== [SPECIAL MYEXTRA SECTION END]: Make sure to update 'SPECIAL_MYEXTRA_OPTIONS' re-declaration below if you add additional sections (i.e. MYEXTRA special option sets) above!
SPECIAL_MYEXTRA_OPTIONS="$TOKUDB $ROCKSDB $BL_ENCRYPTION $KF_ENCRYPTION $BINLOG $ONLYFULLGROUPBY"
SPECIAL_MYEXTRA_OPTIONS=$(echo $SPECIAL_MYEXTRA_OPTIONS | sed 's|^[ \t]\+||;s|[ \t]\+$||;s|  | |g')

# For GLIBC crash reduction, we need to capture the output of the console from which reducer.sh is started. Currently only a SINGLE threaded solution using the 'scrip'
# binary from the util-linux package was found. The script binary is able to capture the GLIC output from the main console. It may be interesting to review the source C
# code for script, if available, to see how this is done. The following URL's may help with other possible solutions. However, LIBC_FATAL_STDERR_=1 has been found not to
# work at all. Perhaps this is due to mariadbd/mysqld being a setuid program (which is not confirmed). exec 2> and exec 1> redirections as well as process substitution i.e. >() have
# also been found not to work at all. Either the GLIBC trace will still be sent to the main console (and this may be the problem to start with), or it does not display at
# all when testing various interactions. To further complicate things, subshells $() and & may have interesting redirection dynamics. Many combinations were tried. Complex.
# * http://stackoverflow.com/questions/2821577/is-there-a-way-to-make-linux-cli-io-redirection-persistent
# * http://stackoverflow.com/questions/4616061/glibc-backtrace-cant-redirect-output-to-file
# * http://stackoverflow.com/questions/4290336/how-to-redirect-runtime-errors-to-stderr
# * https://sourceware.org/git/?p=glibc.git;a=patch;h=1327439fc6ef182c3ab8c69a55d3bee15b3c62a7
if [ $REDUCE_GLIBC_OR_SS_CRASHES -gt 0 ]; then
  if [ ! -r $SCRIPT_LOC ]; then
    echo "Error: REDUCE_GLIBC_OR_SS_CRASHES is activated, which requires the 'script' binary (part of the util-linux package), but this binary could not be found at $SCRIPT_LOC"
    echo "Please install it and/or set the correct path/binary name using the SCRIPT_LOC variable."
    echo "Terminating now."
    exit 1
  fi
  # Ensure the output of this console is logged. For this, reducer.sh is restarted with self-logging activated using script
  # With thanks, http://stackoverflow.com/a/26308092 from http://stackoverflow.com/questions/5985060/bash-script-using-script-command-from-a-bash-script-for-logging-a-session
  if [ -z "$REDUCER_TYPESCRIPT" ]; then
    TYPESCRIPT_UNIQUE_FILESUFFIX=$RANDOM$RANDOM
    # TODO: this does not work for *** buffer overflow detected *** at all atm; it looks like the typescript is not being captured correctly until CTRL+C is pressed (even with SKIPV turned off). Needs bugfix, though the issue may be OS-related. Example contents in ~/ts_example.log
    # TODO: the following line does not work correctly when passing multiple variables to reducer (outside of the input file), or when such variables contain spaces. This is currenty only seen for the basedir local reducers as created by startup.sh, and is not a common issue otherwise. Workaround; just specify everything in the variables inside the script, without passing command line parameters.
    exec $SCRIPT_LOC -q -f /tmp/reducer_typescript${TYPESCRIPT_UNIQUE_FILESUFFIX}.log -c "REDUCER_TYPESCRIPT=1 TYPESCRIPT_UNIQUE_FILESUFFIX=${TYPESCRIPT_UNIQUE_FILESUFFIX} $0 $@"
  fi
fi

echoit(){
  echo "$(date +'%F %T') $1"
  if [ -r $WORKD/reducer.log ]; then echo "$(date +'%F %T') $1" >> $WORKD/reducer.log; fi
  if [ "${ABORT_ACTIVE}" != "1" ]; then
    if [ ! -r $INPUTFILE ]; then abort; fi  # The inputfile was removed (for example by homedir_scripts/ca etc.)
  fi
}

echoit_overwrite(){
  # Used for frequent on-screen updating when using threads etc.
  echo -ne "$(date +'%F %T') $1\r"
}

save_rr_trace(){
  RR_SAVE_LOCATION=${1}
  rm -rf ${RR_SAVE_LOCATION}
  mkdir -p "${RR_SAVE_LOCATION}/"
  cp -r ${WORKD}/rr/* ${RR_SAVE_LOCATION}/
  rm -rf ${WORKD}/rr
  chmod -R 777 ${RR_SAVE_LOCATION}/
  chmod -R +rX ${RR_SAVE_LOCATION}/
}

abort(){  # Additionally/also used for when echoit cannot locate $INPUTFILE anymore
  trap SIGINT  # Clear the SIGINT trap
  ABORT_ACTIVE=1
  if [ ! -d "${WORKD}" ]; then
    if [ -r "${WORKO}" ]; then
      echoit "[Abort] The work directory (${WORKD}) disappeared, it was likely deleted. Terminating."
    else
      echoit "[Abort] The work directory (${WORKD}) disappeared, it was likely deleted. Last good known testcase: $WORKO (provided the disk being used did not run out of space). Terminating."
    fi
    # TODO: ~/ds (most likely) or ~/memory seem to be causing this more recently and more frequently: to fix
    echoit "[Abort] Any 'Killed' message on the next line is reducer self-terminating after an [Abort]; it is not caused by any watchdog"
    kill -9 $$  # Effectively self-terminate
    exit 1
  elif [ -r $INPUTFILE ]; then
    echoit "[Abort] CTRL+C Was pressed. Dumping variable stack"
  else
    echoit "[Abort] Original input file (${INPUTFILE}) no longer present or readable."
    echoit "[Abort] The source for this reducer was likely deleted. Terminating."
    echo "[Abort] Any 'Killed' message on the next line is reducer self-terminating after an [Abort]; it is not caused by any watchdog"
    kill -9 $$  # Effectively self-terminate
    exit 1
  fi
  echoit "[Abort] WORKD: $WORKD (reducer log @ $WORKD/reducer.log) | EPOCH ID: $EPOCH"
  if [ -r $WORKO ]; then  # If there were no issues found, $WORKO was never written
    echoit "[Abort] Best testcase thus far: $WORKO"
  else
    echoit "[Abort] Best testcase thus far: $INPUTFILE (= input file; no optimizations were successful)"
  fi
  echoit "[Abort] End of dump stack"
  if [ $MDG -eq 1 ]; then
    echoit "[Abort] Ensuring any remaining MDG nodes are terminated and removed"
    ( ps -def | grep -E 'n*.cnf' | grep $EPOCH | awk '{print $2}' | xargs -I{} kill -9 {} >/dev/null 2>&1; ) >/dev/null  2>&1
    sleep 2; sync
  fi
  if [ $GRP_RPL -eq 1 ]; then
    echoit "[Abort] Ensuring any remaining Group Replication nodes are terminated and removed"
    ( ps -def | grep -E  'node1_socket|node2_socket|node3_socket' | grep $EPOCH | awk '{print $2}' | xargs -I{} kill -9 {} >/dev/null 2>&1; ) >/dev/null 2>&1
    sleep 2; sync
  fi
  echoit "[Abort] Ensuring any remaining processes are terminated"
  if [ "$EPOCH" != "" ]; then
    PIDS_TO_TERMINATE=$(ps -def | grep -E --binary-files=text $WHOAMI | grep -E --binary-files=text $EPOCH | grep -E --binary-files=text -v "grep" | awk '{print $2}' | tr '\n' ' ')
  else
    echoit "Assert: \$EPOCH is empty! in abort()!"
  fi
  echoit "[Abort] Terminating these PID's: $PIDS_TO_TERMINATE"
  ( kill -9 $PIDS_TO_TERMINATE >/dev/null 2>&1; ) >/dev/null 2>&1
  if [ -r $INPUTFILE ]; then
    echoit "[Abort] What follows below is a call of finish(), the results are likely correct, but may be mangled due to the interruption"
  else
    echoit "[Abort] What follows below is a call of finish(), the results are likely correct, but may be mangled due to the abort"
  fi
  finish 'abort'
  exit 2
}

options_check(){
  # $1 to this procedure = $1 to the program - i.e. the SQL file to reduce
  if [ "$1" == "" -a "$INPUTFILE" == "" ]; then
    echo "Error: no input file given. Please give an SQL file to reduce as the first option to this script, or set inside the script as INPUTFILE=file_to_reduce.sql"
    echo "Terminating now."
    exit 1
# TODO: The new code below did not work/has issues. To research
#  else
#    if [ "${1}" == "" ]; then
#      if [ ! -r "${INPUTFILE}" ]; then
#        echo "Error: no input file was specified from the command line, and the INPUTFILE listed inside the script (${INPUTFILE}) cannot be read"
#        echo "Terminating now."
#        exit 1
#      fi
#    else
#      if [ ! -z "${INPUTFILE}" ]; then
#        echo "Error: an input file was specified on the command line (${1}), yet INPUTFILE inside the script is also set. Not sure what file to proceed with. Please remove the INPUTFILE setting from inside script, or do not pass an input file on the command line"
#        echo "Terminating now."
#        exit 1
#      fi
#      if [ ! -r "${1}" ]; then
#        echo "A input file was specified on the command line (${1}), yet this file cannot be read by this script"
#        echo "Terminating now."
#        exit 1
#      fi
#    fi
  fi
  # Sudo check
  if [ "$(sudo -A echo 'test' 2>/dev/null)" != "test" ]; then
    echo "Error: sudo is not available or requires a password. This script needs to be able to use sudo, without password, from the userID that invokes it ($(whoami))"
    echo "To get your setup correct, you may like to use a tool like visudo (use 'sudo visudo' or 'su' and then 'visudo') and consider adding the following line to the file:"
    echo "$(whoami)   ALL=(ALL)      NOPASSWD:ALL"
    echo "If you do not have sudo installed yet, try 'su' and then 'yum install sudo' or the apt-get equivalent"
    echo "Terminating now."
    exit 1
  fi
  # Note that instead of giving the SQL file on the cmd line, $INPUTFILE can be set (./process does so automaticaly using the #VARMOD# marker above)
  if [ $(sysctl -n fs.aio-max-nr) -lt 300000 ]; then
    echo "As fs.aio-max-nr on this system is lower than 300000, so you will likely run into BUG#12677594: INNODB: WARNING: IO_SETUP() FAILED WITH EAGAIN"
    echo "To prevent this from happening, please use the following command at your shell prompt (you will need to have sudo privileges):"
    echo "sudo sysctl -w fs.aio-max-nr=300000"
    echo "The setting can be verified by executing: sysctl fs.aio-max-nr"
    echo "Alternatively, you can add make the following settings to be system wide:"
    echo "sudo vi /etc/sysctl.conf           # Then, add the following two lines to the bottom of the file"
    echo "fs.aio-max-nr = 1048576"
    echo "fs.file-max = 6815744"
    echo "Terminating now."
    exit 1
  fi
  # Check if O_DIRECT is being used on tmpfs, which (when the original run was not on tmpfs) is not a 100% reproduce match, which may affect reproducibility
  # See http://bugs.mysql.com/bug.php?id=26662 for more info
  if $(echo $MYEXTRA | grep -E --binary-files=text -qi "MYEXTRA=.*O_DIRECT"); then
    if [ $WORKDIR_LOCATION -eq 1 -o $WORKDIR_LOCATION -eq 2 ]; then  # ramfs may not have this same issue, maybe '-o $WORKDIR_LOCATION -eq 2' can be removed?
      echo 'Error: O_DIRECT is being used in the MYEXTRA option string, and tmpfs (or ramfs) storage was specified, but because'
      echo 'of bug http://bugs.mysql.com/bug.php?id=26662 one would see a WARNING for this in the error log along the lines of;'
      echo '[Warning] InnoDB: Failed to set O_DIRECT on file ./ibdata1: OPEN: Invalid argument, continuing anyway.'
      echo "          O_DIRECT is known to result in 'Invalid argument' on Linux on tmpfs, see MySQL Bug#26662."
      echo 'So, reducer is exiting to allow you to change WORKDIR_LOCATION in the script to a non-tmpfs setting.'
      echo 'Note: this assertion currently shows for ramfs as well, yet it has not been established if ramfs also'        #
      echo '      shows the same problem. If it does not (modify the script in this section to get it to run with ramfs'  # ramfs, delete if ramfs is affected
      echo '      as a trial/test), then please remove ramfs, or, if it does, then please remove these 3 last lines.'     #
      echo "Terminating now."
      exit 1
    fi
  fi
  # This section could be expanded to check for any directory specified (by for instance checking for paths), not just the two listed here
  DIR_ISSUE=0
  if $(echo $MYEXTRA | grep -E --binary-files=text -qi "MYEXTRA=.*innodb_log_group_home_dir"); then DIR_ISSUE='innodb_log_group_home_dir'; fi
  if $(echo $MYEXTRA | grep -E --binary-files=text -qi "MYEXTRA=.*innodb_log_arch_dir"); then DIR_ISSUE='innodb_log_arch_dir'; fi
  if [ "$DIR_ISSUE" != "0" ]; then
    echo "Error: the $DIR_ISSUE option is being used in the MYEXTRA option string. This can lead to all sorts of problems;"
    echo 'Remember that reducer 1) is multi-threaded - i.e. it would access that particularly named directory for each started mariadbd/mysqld, which'
    echo 'clearly would result in issues, and 2) whilst reducer creates new directories for every trial (and for each thread), it would not do'
    echo 'anything for this hardcoded directory, so this directory would get used every time, again clearly resulting in issues, especially'
    echo 'when one considers that 3) running mariadbd/mysqld instances get killed once the achieved result (for example, issue discovered) is obtained.'
    echo 'Suggested course of action: remove this/these sort of options from the MYEXTRA string and see if the issue reproduces. This/these sort'
    echo 'of options often have little effect on reproducibility. Howerver, if found significant, reducer.sh can be expanded to cater for this/'
    echo 'these sort of options being in MYEXTRA by re-directing them to a per-trial (and per-thread) subdirectory of the trial`s rundir used.'
    echo 'Terminating reducer to allow this change to be made.'
    exit 1
  fi
  if [ "$(echo "${NR_OF_TRIAL_REPEATS}" | grep --binary-files=text -o '[0-9]*')" != "${NR_OF_TRIAL_REPEATS}" ]; then
    echo "Error: NR_OF_TRIAL_REPEATS (${NR_OF_TRIAL_REPEATS}) is not numeric."
    exit 1
  elif [ ${NR_OF_TRIAL_REPEATS} -lt 1 ]; then
    echo "Error: NR_OF_TRIAL_REPEATS (${NR_OF_TRIAL_REPEATS}) is less than 1 which is an impossible setting."
    exit 1
  fi
  if [ "${PQUERY_CONS_Q_FAIL}" -eq 1 ]; then
    if [ "${REDUCE_GLIBC_OR_SS_CRASHES}" -eq 1 ]; then
      echo "Error: PQUERY_CONS_Q_FAIL=1 and REDUCE_GLIBC_OR_SS_CRASHES=1: these modes are incompatible, please turn off at least one"
      exit 1 
    fi
    echoit "[Setup] PQUERY_CONS_Q_FAIL is enabled, setting USE_PQUERY=1, TEXT='Last [0-9]+ consecutive queries all failed', MODE=3, USE_NEW_TEXT_STRING=0"
    USE_PQUERY=1
    TEXT='Last [0-9]+ consecutive queries all failed'
    MODE=3
    USE_NEW_TEXT_STRING=0
  fi
  if [ $MODE -ge 6 ]; then
    if [ ! -d "$1" ]; then
        echo 'Error: A file name was given as input, but a directory name was expected.'
        echo "(MODE $MODE is set. Where you trying to use MODE 4 or lower?)"
        echo "Terminating now."
        exit 1
    fi
    if ! [ -d "$1/log/" -a -x "$1/log/" ]; then
      echo 'Error: No input directory containing a "/log" subdirectory was given, or the input directory could not be read.'
      echo 'Please specify a correct RQG vardir to reduce a multi-threaded testcase.'
      echo 'Example: ./reducer /starfish/data_WL1/vardir1_1000 -> to reduce ThreadSync trial 1000'
      echo "Terminating now."
      exit 1
    else
      TS_THREADS=$(ls --color=never -l $1/log/C[0-9]*T[0-9]*.sql | wc -l | tr -d '[\t\n ]*')
      # Making sure $TS_ELIMINATION_THREAD_ID is higher than number of threads to avoid 'unary operator expected' in cleanup_and_save during STAGE V
      TS_ELIMINATION_THREAD_ID=$[$TS_THREADS+1]
      if [ $TS_THREADS -lt 1 ]; then
        echo 'Error: though input directory was found, no ThreadSync SQL trace files are present, or they could not be read.'
        echo "Please check the directory at $1"
        echo 'For the presence of 'C[0-9]*T[0-9]*.sql' files (for example, C1T10.sql).'
        echo 'Note: a data load file (such as CT2.sql or CT3.sql) alone is not sufficient: thread sql data would be missing.'
        echo "Terminating now."
        exit 1
      else
        TS_INPUTDIR="$1/log"
        if [ "${DISABLE_TOKUDB_AND_JEMALLOC}" -eq 0 ]; then
          TOKUDB_RUN_DETECTED=0
          if echo "${SPECIAL_MYEXTRA_OPTIONS} ${MYEXTRA}" | grep -E --binary-files=text -qi "tokudb" 2>/dev/null; then TOKUDB_RUN_DETECTED=1; fi
          if [ ${DISABLE_TOKUDB_AUTOLOAD} -eq 0 ]; then
            if grep -E --binary-files=text -qi "tokudb" $TS_INPUTDIR/C[0-9]*T[0-9]*.sql 2>/dev/null; then TOKUDB_RUN_DETECTED=1; fi
          fi
          if [ ${TOKUDB_RUN_DETECTED} -eq 1 ]; then
            if [ -r `sudo find /usr/*lib*/ -name libjemalloc.so.2 | head -n1` ]; then
              export LD_PRELOAD=`sudo find /usr/*lib*/ -name libjemalloc.so.2 | head -n1`
            elif [ -r `sudo find /usr/local/*lib*/ -name libjemalloc.so.2 | head -n1` ]; then
              export LD_PRELOAD=`sudo find /usr/local/*lib*/ -name libjemalloc.so.2 | head -n1`
            elif [ -r `sudo find /usr/*lib*/ -name libjemalloc.so | head -n1` ]; then
              export LD_PRELOAD=`sudo find /usr/*lib*/ -name libjemalloc.so | head -n1`
            elif [ -r `sudo find /usr/local/*lib*/ -name libjemalloc.so | head -n1` ]; then
              export LD_PRELOAD=`sudo find /usr/local/*lib*/ -name libjemalloc.so | head -n1`
            elif [ -r `sudo find /usr/*lib*/ -name libjemalloc.so.1 | head -n1` ]; then
              export LD_PRELOAD=`sudo find /usr/*lib*/ -name libjemalloc.so.1 | head -n1`
            elif [ -r `sudo find /usr/local/*lib*/ -name libjemalloc.so.1 | head -n1` ]; then
              export LD_PRELOAD=`sudo find /usr/local/*lib*/ -name libjemalloc.so.1 | head -n1`
            else
              echo 'This run contains TokuDB SE SQL, yet jemalloc - which is required for TokuDB - was not found, please install it first'
              echo 'This can be done with a command similar to: $ sudo apt install jemalloc libjemalloc-dev libjemalloc2  # or yum instead of apt-get when using RedHat. Name varies so you may only need for example libjemalloc2'
              echo "Terminating now."
              exit 1
            fi
          fi
        fi
      fi
    fi
  else
    if [ -d "$1" ]; then
        echo 'Error: A directory was given as input, but a filename was expected.'
        echo "(MODE $MODE is set. Where you trying to use MODE 6 or higher?)"
        echo "Terminating now."
        exit 1
    fi
    if [ ! -r "$1" ]; then
      if [ ! -r $INPUTFILE ]; then
        if [ "$INPUTFILE" == "" -a "$1" == "" ]; then
          echo 'Error: No input file was given.'
        else
          echo "Error: The specified input file ($INPUTFILE) did not exist or could not be read."
        fi
        echo 'Please specify a single SQL file to reduce.'
        echo 'Example: ./reducer ~/1.sql     --> to process ~/1.sql'
        echo 'Also, please ensure input file name only contains [0-9a-zA-Z_-] characters'
        echo "For reference, this message was produced by $0"
        echo 'Terminating now.'
        exit 1
      fi
    else
      export -n INPUTFILE=$1  # export -n is not necessary for this script, but it is here to prevent pquery-prep-red.sh from seeing this as a adjustable var
    fi
    if [[ "${0}" == *"base_reducer"* ]]; then
      if [ -r "${INPUTFILE}_out" ]; then  # A reduced testcase already exists, copy it unless a previously made copy already exists too
        if [ -r "${INPUTFILE}_out_copy" ]; then  # A previously made copy of a previously reduced testcase also already exists
          echo "Error: the input file (${INPUTFILE}) already has a reduced testcase (${INPUTFILE}_out), which would be ovewritten by running this reducer script as-is. Still, in such cases reducer generally takes a copy of the previously reduced testcase into ${INPUTFILE}_out_copy, howerver, that file also already exists. Please cleanup files as deemed best, and then restart reducer."
          exit 1
        else
          echo "Warning: a reduced testcase (${INPUTFILE}_out) already exists and will be overwritten, thus backing it up as ${INPUTFILE}_out_copy now"
          cp ${INPUTFILE}_out ${INPUTFILE}_out_copy
        fi
      fi
    fi
    if [ "${DISABLE_TOKUDB_AND_JEMALLOC}" -eq 0 ]; then
      TOKUDB_RUN_DETECTED=0
      if echo "${SPECIAL_MYEXTRA_OPTIONS} ${MYEXTRA}" | grep -E --binary-files=text -qi "tokudb" 2>/dev/null; then TOKUDB_RUN_DETECTED=1; fi
      if [ ${DISABLE_TOKUDB_AUTOLOAD} -eq 0 ]; then
        if grep -E --binary-files=text -qi "tokudb" ${INPUTFILE} 2>/dev/null; then TOKUDB_RUN_DETECTED=1; fi
      fi
      if [ ${TOKUDB_RUN_DETECTED} -eq 1 ]; then
        #if [ ${DISABLE_TOKUDB_AUTOLOAD} -eq 0 ]; then  # Just here for extra safety
        #  if ! echo "${SPECIAL_MYEXTRA_OPTIONS} ${MYEXTRA}" | grep -E --binary-files=text -qi "plugin-load=tokudb=ha_tokudb.so"; then MYEXTRA="${MYEXTRA} --plugin-load=tokudb=ha_tokudb.so"; fi
        #  if ! echo "${SPECIAL_MYEXTRA_OPTIONS} ${MYEXTRA}" | grep -E --binary-files=text -qi "tokudb-check-jemalloc"; then MYEXTRA="${MYEXTRA} --tokudb-check-jemalloc=0"; fi
        #fi
        #if [ -r /usr/lib64/libjemalloc.so.1 ]; then
        #  export LD_PRELOAD=/usr/lib64/libjemalloc.so.1
        if [ -r `sudo find /usr/*lib*/ -name libjemalloc.so.1 | head -n1` ]; then
          export LD_PRELOAD=`sudo find /usr/*lib*/ -name libjemalloc.so.1 | head -n1`
        else
          if [ -r `sudo find /usr/local/*lib*/ -name libjemalloc.so.1 | head -n1` ]; then
            export LD_PRELOAD=`sudo find /usr/local/*lib*/ -name libjemalloc.so.1 | head -n1`
          else
            echo 'This run contains TokuDB SE SQL, yet jemalloc - which is required for TokuDB - was not found, please install it first'
            echo 'This can be done with a command similar to: $ yum install jemalloc'
            echo "Terminating now."
            exit 1
          fi
        fi
      fi
    fi
  fi
  if [ "${MODE3_ANY_SIG}" == "1" ]; then
    if [ "${USE_NEW_TEXT_STRING}" != "1" ]; then
      echo "Error: MODE3_ANY_SIG is set to 1, yet USE_NEW_TEXT_STRING, which is required for MODE3_ANY_SIG=1, is set to ${USE_NEW_TEXT_STRING}"
      echo "Terminating now."
      exit 1
    fi
    TEXT=''  # TEXT is not used when using the MODE3_ANY_SIG modifier as reducer will look for the regex '^SIG' in the USE_NEW_TEXT_STRING output
  fi
  # Sanitize input filenames which do not have a path specified by pointing to the current path (only possible conclusion). This ensures [Finish] output looks correct (ref $WORK_BUG_DIR)
  if [[ "${INPUTFILE}" != *"/"* ]]; then
    INPUTFILE="${PWD}/${INPUTFILE}"
  fi
  if [ ! -r "${INPUTFILE}" -a ! -d "${INPUTFILE}" ]; then
    echo "Assert: INPUTFILE is not a readable file, nor a directory"
    exit 1
  fi
  if [ $MODE -eq 0 ]; then
    if [ "${TIMEOUT_COMMAND}" != "" ]; then
      echo "Error: MODE is set to 0, and TIMEOUT_COMMAND is set. Both functions should not be used at the same time"
      echo "Use either MODE=0 (and set TIMEOUT_CHECK), or TIMEOUT_COMMAND in combination with some other MODE, for example MODE=2 or MODE=3"
      echo "Terminating now."
      exit 1
    fi
    if [ ${TIMEOUT_CHECK} -le 30 ]; then
      echo "Error: MODE=0 and TIMEOUT_CHECK<=30. When using MODE=0, set TIMEOUT_CHECK at least to: (2x the expected testcase duration lenght in seconds)+30 seconds extra!"
      echo "Terminating now."
      exit 1
    fi
    TIMEOUT_CHECK_REAL=$[ ${TIMEOUT_CHECK} - 30 ];
    if [ ${TIMEOUT_CHECK_REAL} -le 0 ]; then
      echo "Assert: TIMEOUT_CHECK_REAL<=0"
      echo "Terminating now."
      exit 1
    fi
    TIMEOUT_COMMAND="timeout --signal=SIGKILL ${TIMEOUT_CHECK}s"  # TIMEOUT_COMMAND var is used (hack) instead of adding yet another MODE0 specific variable
  fi
  if [ "${TIMEOUT_COMMAND}" != "" -a "$(timeout 2>&1 | grep -E --binary-files=text -o 'information')" != "information" ]; then
    echo "Error: TIMEOUT_COMMAND is set, yet the timeout command does not seem to be available"
    echo "Terminating now."
    exit 1
  fi
  if [ $MODE -eq 3 -a $USE_NEW_TEXT_STRING -eq 1 ]; then
    if [ $(echo "${TEXT}" | sed 's/[^|]//g' | tr -d '\n' | wc -m) -lt 3 ]; then  # Actual normal is 4. 3 Used for small safety buffer yet avoiding most '||' (OR) error-log-search based TEXT's. Still, the new text string could in principle have less then 4 also if not enough stacks were available in the core dump, or if we ever decide to use the old unique strings as a fallback for the case where new strings are not available (unlikely).
      if [ "${FIREWORKS}" != "1" ]; then
        if [[ "${TEXT}" != "MUTEX"* && "${TEXT}" != "MEMORY_NOT_FREED"* && "${TEXT}" != "GOT_FATAL_ERROR"* && "${TEXT}" != "GOT_ERROR"* && "$TEXT" != "MARKED_AS_CRASHED"* && "$TEXT" != "MARIADB_ERROR"* && "${TEXT}" != "SERVER_ERRNO"* && "${TEXT}" != "SLAVE_ERROR"* && "${TEXT}" != "FALLBACK"* && "${TEXT}" != "INNODB_ERROR"* && "$TEXT" != "GENERIC_ISSUE"* ]]; then  # Avoid situations where it is expected to see this, ref new_text_string.sh
          if [ "${MODE3_ANY_SIG}" != "1" ]; then  # When MODE3_ANY_SIG is being used, TEXT is blanked
            echo "Likely misconfiguration: MODE=3 and USE_NEW_TEXT_STRING=1, yet the TEXT string ('${TEXT}') does not contain at least 3 '|' symbols, which are normally used in new text string unique bug ID's! It is highly likely reducer will not locate any bugs this way. Are you perhaps attempting to look for a specific TEXT string in the standard server error log? If so, please set USE_NEW_TEXT_STRING=0 and SCAN_FOR_NEW_BUGS=0 ! Another possibility is that you incorrectly set the TEXT variable to something that is not a/the unique bug ID. Please check your setup. Pausing 13 seconds for consideration. Press CTRL+c if you want to stop at this point. If not, reducer will look for '${TEXT}' in the new text string script unique bug ID output. Again, this is unlikely to work, unless in the specific use case of looking for a partial match of a limited TEXT string against the new text string script unique bug ID output."
            sleep 13
          fi
        fi
      fi
    fi
    if [ ! -r "$TEXT_STRING_LOC" ] ; then
      echo "Assert: MODE=3 and USE_NEW_TEXT_STRING=1, so reducer.sh looked for $TEXT_STRING_LOC (as set in \$TEXT_STRING_LOC), but this program was either not found (most likely), or it is not readable (check file privileges)"
      echo "Terminating now."
      exit 1
    elif ! egrep -qi "set logging" $TEXT_STRING_LOC; then
      echo "Assert: MODE=3 and USE_NEW_TEXT_STRING=1, so reducer.sh looked for $TEXT_STRING_LOC (as set in \$TEXT_STRING_LOC), and found a readable file at this location, however it did not contain the text 'set logging' so it is likely not the right script!"
      echo "Terminating now."
      exit 1
    fi
  fi
  if [ $USE_NEW_TEXT_STRING -eq 1 -a $MODE -ne 3 ]; then
    echo "Assert: USE_NEW_TEXT_STRING=1 and MODE!=3 (MODE=${MODE}). This scenario is not covered by reducer yet. Suggestion; disable USE_NEW_TEXT_STRING and instead use a string from the error log; TEXT='some_search_string_from_error_log' to let reducer use that (search for that string) to reduce the testcase. OR, altenatively, please expand reducer.sh to handle this scenario too. For this, the main change would be to avoid using a regex-aware grep in the actual bug-found-or-not checking section of the individual mode (MODE=${MODE}) inside the process_outcome() function. This can be done by using grep -Fi instead of grep -E. So basically, check for USE_NEW_TEXT_STRING being enabled, then, if so, use different grep to check. Needs qucik eval of usefullness per MODE."  # TODO
    exit 1
  fi
  if [ $MODE -eq 2 ]; then
    if [ $USE_PQUERY -eq 1 ]; then  # pquery client output testing run in MODE=2 - we need to make sure we have pquery client logging activated
      if [ "$(echo $PQUERY_EXTRA_OPTIONS | grep -E --binary-files=text -io "log-client-output")" != "log-client-output" ]; then
        echo "Assert: USE_PQUERY=1 && PQUERY_EXTRA_OPTIONS does not contain log-client-output, so not sure what file reducer.sh should check for TEXT occurrence."
        exit 1
      fi
    fi
  fi
  BIN="${BASEDIR}/bin/mariadbd"
  if [ ! -r "${BIN}" ]; then
    BIN="${BASEDIR}/bin/mysqld"
    if [ ! -r "${BIN}" ]; then
      BIN="${BASEDIR}/bin/mysqld-debug"
      if [ ! -r "${BIN}" ]; then
        echo "Assert: No mariadbd, mysqld or mysqld-debug binary was found in ${BASEDIR}/bin"
        echo 'Please check script options and please set the $BASEDIR variable correctly'
        echo "The BASEDIR variable is currently set to ${BASEDIR}"
        echo "Terminating now."
        exit 1
      fi
    fi
  fi
  if [ $MODE -ne 0 -a $MODE -ne 1 -a $MODE -ne 2 -a $MODE -ne 3 -a $MODE -ne 4 -a $MODE -ne 5 -a $MODE -ne 6 -a $MODE -ne 7 -a $MODE -ne 8 -a $MODE -ne 9 ]; then
    echo "Error: Invalid MODE set: $MODE (valid range: 1-9)"
    echo 'Please check script contents/options ($MODE variable)'
    echo "Terminating now."
    exit 1
  fi
  if [ $MODE -eq 1 -o $MODE -eq 2 -o $MODE -eq 3 -o $MODE -eq 5 -o $MODE -eq 6 -o $MODE -eq 7 -o $MODE -eq 8 ]; then
    if [ ! -n "$TEXT" -a "${MODE3_ANY_SIG}" != "1" ]; then
      echo "Error: MODE set to $MODE, but no \$TEXT variable was defined, or \$TEXT is blank"
      echo 'Please check script contents/options ($TEXT variable)'
      echo "Terminating now."
      exit 1
    fi
  fi
  if [[ $MDG -eq 1  || $GRP_RPL -eq 1 ]]; then
    USE_PQUERY=1
    # ========= These are currently limitations of MDG/Group Replication mode. Feel free to extend reducer.sh to handle these ========
    #export -n MYEXTRA=""  # Serious shortcoming. Work to be done. PQUERY MYEXTRA variables will be added docker-compose.yml
    if [ ${SHOW_SETUP_DEBUGGING} -gt 0 ]; then
      echoit "[Setup] MDG or GRP_RPL is enabled, setting FORCE_SPORADIC=0, SPORADIC=0, FORCE_SKIPV=0, SKIPV=1, MULTI_THREADS=0"
    fi
    # /==========
    if [ $MODE -eq 0 ]; then
      echo "Error: MDG/Group Replication mode is set to 1, and MODE=0 set to 0, but this option combination has not been tested/added to reducer.sh yet. Please do so!"
      echo "Terminating now."
      exit 1
    fi
    if [ "${TIMEOUT_COMMAND}" != "" ]; then
      echo "Error: MDG/Group Replication mode is set to 1, and TIMEOUT_COMMAND is set, but this option combination has not been tested/added to reducer.sh yet. Please do so!"
      echo "Terminating now."
      exit 1
    fi
    if [ $MODE -eq 1 -o $MODE -eq 6 ]; then
      echo "Error: Valgrind for ${NR_OF_NODES} node MDG/Group Replication replay has not been implemented yet. Please do so! Free cookies afterwards!"
      echo "Terminating now."
      exit 1
    fi
    if [ $MODE -ge 6 -a $MODE -le 9 ]; then
      echo "Error: wrong option combination: MODE is set to $MODE (ThreadSync) and MDG/Group Replication mode is active"
      echo 'Please check script contents/options ($MODE and $MDG mode variables)'
      echo "Terminating now."
      exit 1
    fi
  fi
  if [ $PQUERY_MULTI -eq 1 ]; then
    USE_PQUERY=1
  fi
  if [ $USE_PQUERY -eq 1 ]; then
    if [ ! -r "$PQUERY_LOC" ]; then
      echo "Error: USE_PQUERY is set to 1, but the pquery binary (as defined by PQUERY_LOC; currently set to '$PQUERY_LOC') is not available."
      echo 'Please check script contents/options ($USE_PQUERY and $PQUERY_LOC variables)'
      echo "Terminating now."
      exit 1
    fi
  fi
  if [ $PQUERY_MULTI -gt 0 ]; then
    if [ ${SHOW_SETUP_DEBUGGING} -gt 0 ]; then
      echoit "[Setup] PQUERY_MULTI is set, setting FORCE_SKIPV=1"
    fi
    export -n FORCE_SKIPV=1
    MULTI_THREADS=$PQUERY_MULTI_THREADS
    if [ $PQUERY_MULTI_CLIENT_THREADS -lt 1 ]; then
      echoit "Error: PQUERY_MULTI_CLIENT_THREADS is set to less then 1 ($PQUERY_MULTI_CLIENT_THREADS), while PQUERY_MULTI active, this does not work; reducer needs threads to be able to replay the issue"
      echo "Terminating now."
      exit 1
    elif [ $PQUERY_MULTI_CLIENT_THREADS -eq 1 ]; then
      echoit "Warning: PQUERY_MULTI active, and PQUERY_MULTI_CLIENT_THREADS is set to 1; 1 thread for a multi-threaded issue does not seem logical. Proceeding, but this is highly likely incorrect. Please check. NOTE: There is at least one possible use case for this: proving that a sporadic mariadbd/mysqld startup can be reproduced (with a near-empty SQL file; i.e. the run is concerned with reproducing the startup issue, not reducing the SQL file)"
    elif [ $PQUERY_MULTI_CLIENT_THREADS -lt 5 ]; then
      echoit "Warning: PQUERY_MULTI active, and PQUERY_MULTI_CLIENT_THREADS is set to $PQUERY_MULTI_CLIENT_THREADS, $PQUERY_MULTI_CLIENT_THREADS threads for reproducing a multi-threaded issue via random replay seems insufficient. You may want to increase PQUERY_MULTI_CLIENT_THREADS. Proceeding, but this is likely incorrect. Please check"
    fi
  fi
  if [ $REDUCE_GLIBC_OR_SS_CRASHES -gt 0 ]; then
    if [ ${SHOW_SETUP_DEBUGGING} -gt 0 ]; then
      echoit "[Setup] REDUCE_GLIBC_OR_SS_CRASHES is set, setting MULTI_THREADS=1, MULTI_THREADS_INCREASE=0, SLOW_DOWN_CHUNK_SCALING=1, SKIPV=1"
    fi
    export -n MULTI_THREADS=1            # Likely not needed, because MULTI mode should never become active for REDUCE_GLIBC_OR_SS_CRASHES=1 (and there is a matching assert),
    export -n MULTI_THREADS_INCREASE=0   # so it is here as a safety measure only FTM.
    export -n SLOW_DOWN_CHUNK_SCALING=1
    export -n SKIPV=1
    if [ $MODE -ne 3 -a $MODE -ne 4 ]; then
      echo "REDUCE_GLIBC_OR_SS_CRASHES is active, and MODE is set to MODE=$MODE, which is not supported (yet). Currently only modes 3 and 4 are supported when reducing GLIBC crashes"
      echo "Terminating now."
      exit 1
    fi
    if [[ $MDG -gt 0 || $GRP_RPL -eq 1 ]]; then
      echo "GLIBC testcase reduction is not yet supported for MDG=1 or GRP_RPL=1. This would be very complex to code, except perhaps for a single node cluster or for one node only. See source code for details. Search for 'GLIBC crash reduction'"
      echo "A workaround may be to see if this GLIBC crash reproduces on standard (non-cluster) mariadbd/mysqld also, which is likely."
      echo "Terminating now."
      exit 1
    fi
    if [ $PQUERY_MULTI -gt 0 ]; then
      echo "GLIBC testcase reduction is not yet supported for PQUERY_MULTI=1. This would be very complex to code. See source code for details. Search for 'GLIBC crash reduction'"
      echo "A workaround may be to see if this GLIBC crash reproduces using a single threaded execution, which in most cases is somewhat likely."
      echo "Terminating now."
      exit 1
    fi
  fi
  if [ $FORCE_SKIPV -gt 0 ]; then
    if [ ${SHOW_SETUP_DEBUGGING} -gt 0 ]; then
      echoit "[Setup] FORCE_SKIPV was set to 0, setting FORCE_SPORADIC=1 and SKIPV=1"
    fi
    export -n FORCE_SPORADIC=1
    export -n SKIPV=1
  fi
  if [ $FORCE_SPORADIC -gt 0 ]; then
    if [ $STAGE1_LINES -eq 90 ]; then  # Do not change any customized/non-default (i.e. !=90) setting as this may be handy for automation. For example, pquery-reach.sh will set STAGE1_LINES to 13 while activating FORCE_SKIPV=1 which means that reducer will reduce in MULTI (multi-threaded subreducer) mode until 13 lines are reached, then it will swap to single threaded. This is great to manage a combination of both sporadic (they will be reduced to at max 13 lines) and static (they will be full reduced) issues.
      if [ ${SHOW_SETUP_DEBUGGING} -gt 0 ]; then
        echoit "[Setup] FORCE_SPORADIC is set and STAGE1_LINES!=90, settting STAGE1_LINES=3"
      fi
      export -n STAGE1_LINES=3
    fi
    if [ ${SHOW_SETUP_DEBUGGING} -gt 0 ]; then
      echoit "[Setup] FORCE_SPORADIC is set, setting SPORADIC=1 and SLOW_DOWN_CHUNK_SCALING=1"
    fi
    export -n SPORADIC=1
    export -n SLOW_DOWN_CHUNK_SCALING=1
  fi
  if [ $MODE -eq 0 -a $FORCE_KILL=1 ]; then
    if [ ${SHOW_SETUP_DEBUGGING} -gt 0 ]; then
      echoit "[Setup] FORCE_KILL was set to 1, however as this is a MODE=0 run, setting FORCE_KILL=0"
    fi
    FORCE_KILL=0
  fi
  if [ ${SCAN_FOR_NEW_BUGS} -eq 1 ]; then
    if [ ! -r ${KNOWN_BUGS_LOC} ]; then
      echo "SCAN_FOR_NEW_BUGS was set to 1, yet the file specified in KNOWN_BUGS_LOC (${KNOWN_BUGS_LOC}) does not exist?"
      echo "Terminating now."
      exit 1
    fi
    # TODO: the following can be improved. If it is empty, we save to the workdir by default, but yet we assert here if is empty. As long as the feature is beta, this is a good idea to make sure new bugs are always saved correctly. What is not clear yet is if pquery-run.sh will copy the full trial dir on various reductions back. And, if you for example use reducer_new_text_string.sh from a basedir (after ~/start), then any newbugs will be saved in /dev/shm but not elsehwere unless NEW_BUGS_SAVE_DIR was set. It is, but it shows how new bugs could be missed if we don't assert here, just save to the workdir (/dev/shm) and not somehow copy it back. One solution may be to save to the same directory as where the original input file was (i.e. set NEW_BUGS_SAVE_DIR to that and never proceed unless NEW_BUGS_SAVE_DIR is set, i.e. it cannot be empty, but may be autoset as such. To evaluate more once more runtime experience is present, though this may no longer be visible now that NEW_BUGS_COPY_DIR code was changed to NEW_BUGS_SAVE_DIR and a copy is only stored in the save dir and not the workdir by defauly anymore (due to /dev/shm space prevention measures).
    if [ -z "${NEW_BUGS_SAVE_DIR}" ]; then
      echo "Assert: SCAN_FOR_NEW_BUGS was set to 1, yet NEW_BUGS_SAVE_DIR is empty. Please set it to a target directory for the SQL testcases to be saved"
      echo "Terminating now."
      exit 1
    fi
    if [ ! -d "${NEW_BUGS_SAVE_DIR}" ]; then
      mkdir -p "${NEW_BUGS_SAVE_DIR}"
      if [ ! -d "${NEW_BUGS_SAVE_DIR}" ]; then
        echo "SCAN_FOR_NEW_BUGS was set to 1, and NEW_BUGS_SAVE_DIR was set to '${NEW_BUGS_SAVE_DIR}'. As this directory did not exist yet, this script tried to create it, and failed. Please check."
        echo "Terminating now."
        exit 1
      fi
    fi
    if [ "${USE_NEW_TEXT_STRING}" != "1" ]; then
      echoit "[Setup] SCAN_FOR_NEW_BUGS was set to 1, yet USE_NEW_TEXT_STRING is not set to 1 (set to '${USE_NEW_TEXT_STRING}'). This setup is not covered by this script yet. Ref inside reducer for more info. Automatically turning SCAN_FOR_NEW_BUGS off."
      # Reason is that the new text string script is used in conjunction with the new bugs string list. This could be expanded to include the older bugs string list also, but this would seem to be wasted effort as that list is no longer maintained inside MariaDB (the new unique bug id's are used instead and are much better/of much higher quality). Rather, and this is also provides additional ROI in other areas; update the new text string script to call the old script for any case where a new unique bug ID can not be obtained (quite limited limited amount of cases; usually only when incorrect core dumps (stack smashing, OOS, mariadbd/mysqld failed to create a coredump) are used.
      SCAN_FOR_NEW_BUGS=0
    fi
  fi
  export -n MYEXTRA=`echo ${MYEXTRA} | sed 's|[ \t]*--no-defaults[ \t]*||g'`  # Ensuring --no-defaults is no longer part of MYEXTRA. Reducer already sets this itself always.
}

remove_dropc(){
  if [ "$1" == "" ]; then
    echoit "Assert: no parameter was passed to the remove_dropc() function. This should not happen."
    exit 1
  fi
  # Loop through the top of the passed file (usually WORKT or WORKF) and remove all seen individual DROPC lines
  # Implenting things this way became necessary once individual lines were used for DROPC instead of just one long line
  # which could be grepped out with grep -v. The reason for having to use individual lines for DROPC is that pquery
  # will not process STATEMENT1;STATEMENT2; and this led to errors. This is only done for USE_PQUERY=1 runs to ensure
  # backwards compatibility (i.e. the mysql client will still use grep -v DROPC instead)
  while :; do
    DROPC_LINE_REMOVED=0
    if [[ "$(cat $1 | head -n1)" == *"DROP DATABASE transforms;"* ]]; then
      sed -i '1d' $1
      DROPC_LINE_REMOVED=1
    fi
    if [[ "$(cat $1 | head -n1)" == *"CREATE DATABASE transforms;"* ]]; then
      sed -i '1d' $1
      DROPC_LINE_REMOVED=1
    fi
    if [[ "$(cat $1 | head -n1)" == *"DROP DATABASE test;"* ]]; then
      sed -i '1d' $1
      DROPC_LINE_REMOVED=1
    fi
    if [[ "$(cat $1 | head -n1)" == *"CREATE DATABASE test;"* ]]; then
      sed -i '1d' $1
      DROPC_LINE_REMOVED=1
    fi
    if [[ "$(cat $1 | head -n1)" == *"USE test;"* ]]; then
      sed -i '1d' $1
      DROPC_LINE_REMOVED=1
    fi
    if [ $DROPC_LINE_REMOVED -eq 0 ]; then
      break
    fi
  done
}

set_internal_options(){  # Internal options: do not modify!
  # Try and raise max user processes limit (please also preset the soft/hard nproc settings in /etc/security/limits.conf (Centos), both to at least 20480 - see mariadb-qa/setup_server.sh for an example)
  #ulimit -u 4000  2>/dev/null
  # ^ This was removed, because it was causing the system to run out of available file descriptors. i.e. while ulimit -n may be set to a maximum of 1048576, and whilst that limit may never be reached, a system would still run into "fork: retry: Resource temporarily unavailable" issues. Ref https://askubuntu.com/questions/1236454
  # Unless core files are specifically requested (--core-file or --core option passed to mariadbd/mysqld via MYEXTRA), disable all core file generation (OS+mariadbd/mysqld)
  if [ "${PAUSE_AFTER_EACH_OCCURRENCE}" -eq 1 ]; then
    MYEXTRA="${MYEXTRA} --core-file"  # Enable core file generation if PAUSE_AFTER_EACH_OCCURRENCE is set, as this option is commonly used to debug cores directly after each issue occurrence happens. Also, do not disable core file generation (ref elif)
  elif [ "${USE_NEW_TEXT_STRING}" != "1" ]; then  # Also do not disable core file generation if we need it for the 'new text string' binary (as specified by TEXT_STRING_LOC), which uses core files to generate UniqueID bug strings
    # It would be good if we could disable OS core file generation without disabling mariadbd/mysqld core file generation, but for the moment it looks like
    # ulimit -c 0 disables ALL core file generation, both OS and mariadbd/mysqld, so instead, ftm, reducer checks for "CORE" in MYEXTRA (uppercase-ed via ^^)
    # and if present reducer does not disable core file generation (OS nor mariadbd/mysqld)
    if [[ "${MYEXTRA^^}" != *"CORE"* ]]; then  # ^^ = Uppercase MYEXTRA contents before compare
      ulimit -c 0 >/dev/null
    fi
  fi
  # Runmode (whetter subreducers will be used in MULTI or FIREWORKS run modes) 
  RUNMODE='MULTI'
  if [ "${FIREWORKS}" == "1" ]; then
    RUNMODE='FIREWORKS'
  fi
  sleep 0.1$RANDOM  # Subreducer OS slicing
  WHOAMI=$(whoami)
  if [ "$MULTI_REDUCER" != "1" ]; then  # This is the main reducer. For subreducers, EPOCH, SKIPV, SPORADIC is set in #VARMOD#
    EPOCH=$(date +%s%N)  # Used for /dev/shm work directory name and WORK_INIT, WORK_START etc. file names
    SKIPV=0
    SPORADIC=0
    MYUSER=$(whoami)
  else
    if [ "${EPOCH}" == "" ];    then echo "Assert: \$EPOCH is empty inside a subreducer! Check $(cd $(dirname $0) && pwd)/$0"; exit 1; fi
    if [ "${SKIPV}" == "" ];    then echo "Assert: \$SKIPV is empty inside a subreducer! Check $(cd $(dirname $0) && pwd)/$0"; exit 1; fi
    if [ "${SPORADIC}" == "" ]; then echo "Assert: \$SPORADIC is empty inside a subreducer! Check $(cd $(dirname $0) && pwd)/$0"; exit 1; fi
    if [ "${MYUSER}" == "" ];   then echo "Assert: \$MYUSER is empty inside a subreducer! Check $(cd $(dirname $0) && pwd)/$0"; exit 1; fi
  fi
  trap abort SIGINT  # Requires ${EPOCH} to be set already
  # Even if RQG is no longer used, the next line (i.e. including 'transforms') should NOT be modified. It provides backwards compatibility with RQG (given the 'transforms' database creation)
  DROPC="DROP DATABASE transforms;CREATE DATABASE transforms;DROP DATABASE test;CREATE DATABASE test;USE test;"
  STARTUPCOUNT=0
  ATLEASTONCE="[]"
  TRIAL=1
  STAGE='0'
  STUCKTRIAL=0
  NOISSUEFLOW=0
  CHUNK_LOOPS_DONE=99999999999   # Has to be exactly 99999999999 to ensure that determine_chunk() at least runs once
  C_COL_COUNTER=1
  TS_ELIMINATED_THREAD_COUNT=0
  TS_ORIG_VARS_FLAG=0
  TS_DEBUG_SYNC_REQUIRED_FLAG=0  # Untill proven otherwise
  TS_TE_DIR_SWAP_DONE=0
  NR_OF_NEWBUGS=0
}

kill_multi_reducer(){
  PS_CMD="ps -def | grep --binary-files=text 'subreducer' | grep --binary-files=text ${WHOAMI} | grep --binary-files=text ${EPOCH} | grep --binary-files=text 'grep' | awk '{print \$2}'"
  if [ $(eval ${PS_CMD} | wc -l) -ge 1 ]; then
    PIDS_TO_TERMINATE=$(eval ${PS_CMD} | sort -u | tr '\n' ' ')
    echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] Terminating these PID's: $PIDS_TO_TERMINATE"
    while [ $(eval ${PS_CMD} | wc -l) -ge 1 ]; do
      for t in $(eval ${PS_CMD} | sort -u); do
        ( sleep 0.01; kill -9 $t >/dev/null 2>&1; timeout -k4 -s9 4s wait $t >/dev/null 2>&1; ) >/dev/null 2>&1
        timeout -k5 -s9 5s wait $t >/dev/null 2>&1
      done
      sync; sleep 3
      if [ $(eval ${PS_CMD} | wc -l) -ge 1 ]; then
        sync; sleep 20  # Extended wait for processes to terminate
        if [ $(eval ${PS_CMD} | wc -l) -ge 1 ]; then
          echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] WARNING: $(eval ${PS_CMD} | wc -l) subreducer processes still exists after they were killed, re-attempting kill"
        fi
      fi
    done
  fi
  PS_CMD=
}

multi_reducer(){
  if [ ! -d "${WORKD}" ]; then abort; fi
  MULTI_FOUND=0
  # This function handles starting and checking subreducer threads used for verification AND simplification of sporadic issues (as such it is the parent
  # function watching over multiple [seperately started] subreducer threads, each child containing the written MULTI_REDUCER=1 setting set in #VARMOD# -
  # thereby telling reducer it is a child process)
  # This function does not need to know if reducer is reducing a single or multi-threaded testcase and what MODE is used as all these options are passed
  # verbatim to the child (all settings are copied into the child process below)
  if [ $REDUCE_GLIBC_OR_SS_CRASHES -gt 0 ]; then
    echoit "ASSERT: REDUCE_GLIBC_OR_SS_CRASHES is active, and we ended up in multi_reducer() function. This should not be possible as REDUCE_GLIBC_OR_SS_CRASHES uses a single thread only."
  fi

  echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] Terminating any dangling subreducer processes"  # Cleanup, necessary, do not remove
  kill_multi_reducer  # Cleanup, necessary, do not remove

  if [ "$STAGE" = "V" ]; then
    echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] Starting $MULTI_THREADS verification subreducer threads to verify if the issue is sporadic ($WORKD/subreducer/)"
    SKIPV=0
    SPORADIC=0 # This will quickly be overwritten by the line "SPORADIC=1  # Sporadic unless proven otherwise" below. So, need to check if this is needed here (may be needed for ifthen statements using this variable. Needs research and/or testing.
  else
    if [ "${FIREWORKS}" != "1" ]; then
      echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] Starting $MULTI_THREADS simplification subreducer threads to reduce the issue ($WORKD/subreducer/)"
    else
      echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] Starting $MULTI_THREADS subreducer threads to find new bugs ($WORKD/subreducer/)"
    fi
    SKIPV=1 # For subreducers started for simplification (STAGE1+), verify/initial simplification should be skipped as this was done already by the parent/main reducer (i.e. just above)
  fi

  # Create (or remove/create) main multi-reducer path
  rm -Rf $WORKD/subreducer/
  sync; sleep 0.5
  if [ -d "$WORKD/subreducer/" ]; then
    echoit "ASSERT: $WORKD/subreducer/ still exists after it has been deleted"
    echo "Terminating now."
    exit 1
  fi
  mkdir $WORKD/subreducer/

  TXT_OUT="$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] Forking subreducer threads [PIDs]:"
  for t in $(eval echo {1..$MULTI_THREADS}); do
    # Create individual subreducer paths
    export WORKD$t="$WORKD/subreducer/$t"
    export MULTI_WORKD=$(eval echo $(echo '$WORKD'"$t"))
    mkdir $MULTI_WORKD

    FIXED_TEXT="$(echo "$TEXT" | sed "s|:|\\\:|g;s|&|\\\&|g")"  # Correctly escape : and &
    cat $0 \
      | sed "0,/#VARMOD#/s:#VARMOD#:MULTI_REDUCER=1\n#VARMOD#:" \
      | sed "0,/#VARMOD#/s:#VARMOD#:EPOCH=$EPOCH\n#VARMOD#:" \
      | sed "0,/#VARMOD#/s:#VARMOD#:MODE=$MODE\n#VARMOD#:" \
      | sed "0,/#VARMOD#/s:#VARMOD#:TEXT=\"$FIXED_TEXT\"\n#VARMOD#:" \
      | sed "0,/#VARMOD#/s:#VARMOD#:MODE5_COUNTTEXT=$MODE5_COUNTTEXT\n#VARMOD#:" \
      | sed "0,/#VARMOD#/s:#VARMOD#:SKIPV=$SKIPV\n#VARMOD#:" \
      | sed "0,/#VARMOD#/s:#VARMOD#:SPORADIC=$SPORADIC\n#VARMOD#:" \
      | sed "0,/#VARMOD#/s:#VARMOD#:PQUERY_MULTI_CLIENT_THREADS=$PQUERY_MULTI_CLIENT_THREADS\n#VARMOD#:" \
      | sed "0,/#VARMOD#/s:#VARMOD#:PQUERY_MULTI_QUERIES=$PQUERY_MULTI_QUERIES\n#VARMOD#:" \
      | sed "0,/#VARMOD#/s:#VARMOD#:TS_TRXS_SETS=$TS_TRXS_SETS\n#VARMOD#:" \
      | sed "0,/#VARMOD#/s:#VARMOD#:TS_DBG_CLI_OUTPUT=$TS_DBG_CLI_OUTPUT\n#VARMOD#:" \
      | sed "0,/#VARMOD#/s:#VARMOD#:PAUSE_AFTER_EACH_OCCURRENCE=\"$PAUSE_AFTER_EACH_OCCURRENCE\"\n#VARMOD#:" \
      | sed "0,/#VARMOD#/s:#VARMOD#:BASEDIR=\"$BASEDIR\"\n#VARMOD#:" \
      | sed "0,/#VARMOD#/s:#VARMOD#:MYUSER=\"$MYUSER\"\n#VARMOD#:" > $MULTI_WORKD/subreducer

    chmod +x $MULTI_WORKD/subreducer
    sleep 0.2  # To avoid "InnoDB: Error: pthread_create returned 11" collisions/overloads
    $($MULTI_WORKD/subreducer $1 >/dev/null 2>/dev/null) >/dev/null 2>/dev/null &
    PID=$!
    export MULTI_PID$t=$PID
    TXT_OUT="$TXT_OUT #$t [$PID]"
  done
  echoit "$TXT_OUT"

  if [ "$STAGE" = "V" ]; then
    # Wait for forked processes to terminate
    echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] Waiting for all forked verification subreducer threads to finish/terminate"
    TXT_OUT="$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] Finished/Terminated verification subreducer threads:"
    for t in $(eval echo {1..$MULTI_THREADS}); do
      while true; do  # Wait for subreducer to naturally finish, or check if it has a failed server start issue
        SUBREDUCER_CHECK_PID="$(eval echo $(echo '$MULTI_PID'"$t"))"
        if ! kill -0 ${SUBREDUCER_CHECK_PID} 2>/dev/null; then
          break
        fi
        SUBREDUCER_LOGFILE="$(ps -ef | grep --binary-files=text ${SUBREDUCER_CHECK_PID} | grep --binary-files=text -v 'grep' | grep --binary-files=text -o 'error=/.*subreducer/[0-9]/' | sed 's|^error=||;s|$|reducer.log|' | head -n1)"  # TODO: Perhaps there is a better way to get to the subreducer reducer log file without using the PID directly, though it is not clear how, as in this loop all we seem to have is the subreducer PID
        if [ -f "${SUBREDUCER_LOGFILE}" -a -r "${SUBREDUCER_LOGFILE}" ]; then
          if grep -Eqi --binary-files=text 'Failed to start the.*server' "${SUBREDUCER_LOGFILE}"; then
            kill -9 ${SUBREDUCER_CHECK_PID}  # Ensure the subreducer is terminated immediately. Defensive as a later process cleanup will likely catch it as well
            break
          fi
          sleep 0.25  # Do not query the disk too often
        fi
        sleep 0.25  # ps re-check delay
      done
      SUBREDUCER_CHECK_PID=;SUBREDUCER_LOGFILE=
      TXT_OUT="$TXT_OUT #$t"
      echoit_overwrite "$TXT_OUT"
      if [ $t -eq 20 -a $MULTI_THREADS -gt 20 ]; then
        echoit "$TXT_OUT"
        TXT_OUT="$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] Finished/Terminated verification subreducer threads:"
      fi
    done
    echoit "$TXT_OUT"
    echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] All verification subreducer threads have finished/terminated"
  else
    # Wait for one of the forked processes to succeed to:
    # Without FIREWORKS: find a better reduction file
    # With FIREWORKS: to find a new bug
    # Note that the term/file '/VERIFIED' is used for both instances/occurrences
    if [ "${FIREWORKS}" != "1" ]; then
      echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] Waiting for any forked simplifation subreducer threads to find a shorter file (Issue is deemed or assumed to be sporadic: this may take time)"
    else
      echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] Waiting for any forked subreducer threads to find a new bug"
    fi
    FOUND_VERIFIED=0
    while [ $FOUND_VERIFIED -eq 0 ]; do
      for t in $(eval echo {1..$MULTI_THREADS}); do
        export MULTI_WORKD=$(eval echo $(echo '$WORKD'"$t"))
        # Check if issue was found (i.e. $MULTI_WORKD/VERIFIED file is present). End both loops (while+for) if so
        if [ -s $MULTI_WORKD/VERIFIED ]; then
          sleep 1.5  # Give subreducer script time to write out the file fully
          if [ "${FIREWORKS}" != "1" ]; then
            echoit_overwrite "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] Terminating simplification subreducer threads..."
          else
            echoit_overwrite "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] Terminating subreducer threads..."
          fi
          # Kill subreducers explicitly
          ps -ef | grep 'subreducer' | grep -v grep | grep $EPOCH | awk '{print $2}' | xargs kill -9 > /dev/null 2>&1
          sleep 1
          ps -ef | grep 'subreducer' | grep -v grep | grep $EPOCH | awk '{print $2}' | xargs kill -9 > /dev/null 2>&1
          sleep 2
          if [ "${FIREWORKS}" != "1" ]; then
            echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] Terminating simplification subreducer threads... done"
          else
            echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] Terminating subreducer threads... done"
          fi
          # The subshell in the following line simply retrieves the WORKO output file from the subreducer Then, the grep -v removes any mariadbd/mysqld option line before copying the file to the new/next WORKF for the next trial If this step was not done, the new/next WORKF testcase would always be +1 line longer. The way this would show for example in SKIPV mode is that the main reducer would indicate that it had found a shorter testcase (-1 line for example) whereas the next trial would start with the same line number (as +1 line was re-added). This is not so clear when large chunks are removed at the time, but it becomes very clear when only ~5-15 lines are left. This was fixed and the line below does not suffer from said problem
          grep -E --binary-files=text -v "^# mysqld options required for replay:" $(cat $MULTI_WORKD/VERIFIED | grep -E --binary-files=text "WORKO" | sed -e 's/^.*://' -e 's/[ ]*//g') > $WORKF
          if [ "${FIREWORKS}" != "1" ]; then
            if [ -r "$WORKO" ]; then  # Avoid first occurrence when there is no $WORKO yet
              if [[ ${RR_TRACING} -eq 1 ]]; then
                if [[ ${RR_SAVE_ALL_TRACES} -eq 1 ]]; then
                  save_rr_trace "${WORK_BUG_DIR}/rr/${STAGE}_${TRIAL}_rr_trace"
                  echoit "$ATLEASTONCE [Stage $STAGE] [Trial ${TRIAL}] Saved RR trace in ${WORK_BUG_DIR}/rr/${STAGE}_${TRIAL}_rr_trace"
                fi
              fi
              cp -f $WORKO ${WORKO}.prev
              # Save a testcase backup (this is useful if [oddly] the issue now fails to reproduce)
              echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] Previous good testcase backed up as $WORKO.prev"
            fi
          fi
          cp -f $WORKF $WORKO
          cp -f $WORKO $WORK_OUT
          ATLEASTONCE="[*]"  # The issue was seen at least once, or FIREWORKS detected at least one newbug
          if [ "${FIREWORKS}" != "1" ]; then
            echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] Thread #$t reproduced the issue: testcase saved in $WORKO"
          else
            NR_OF_NEWBUGS=$[ ${NR_OF_NEWBUGS} + 1 ]
            echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] [${NR_OF_NEWBUGS} New Bugs Found] Thread #$t found a new unseen bug: $(cat $MULTI_WORKD/MYBUG.FOUND | head -n1)"
          fi
          FOUND_VERIFIED=1  # Outer loop terminate setup
          if [ "${PAUSE_AFTER_EACH_OCCURRENCE}" == "1" ]; then
            echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] PAUSE_AFTER_EACH_OCCURRENCE is active: reducer is pausing as the issue occured. Press 'Enter' twice to continue..."
            read -p ''
            read -p ''
          fi
          break  # Inner loop terminate
        fi
        # Check if this subreducer ($MULTI_PID$t) is still running. For more info, see "However, ..." in few lines of comments above.a
        RESTART_WORKD=
        PID_TO_CHECK=$(eval echo $(echo '$MULTI_PID'"$t"))
        if [ "$(ps -p$PID_TO_CHECK | grep -E --binary-files=text -o $PID_TO_CHECK)" != "$PID_TO_CHECK" ]; then
          RESTART_WORKD=$(eval echo $(echo '$WORKD'"$t"))
          SUBR_SVR_START_FAILURE=0
          if grep -Eqi --binary-files=text "Failed to start the.*server" $RESTART_WORKD/reducer.log 2>/dev/null; then  # Check if this was a subreducer who's mariadbd/mysqld failed to start
            SUBR_SVR_START_FAILURE=1
            TMP_RND_FILENAME="err_$(echo $RANDOM$RANDOM$RANDOM | sed 's/..\(......\).*/\1/').txt"  # Subshell creates random number with 6 digits
            cp $RESTART_WORKD/log/master.err /tmp/${TMP_RND_FILENAME}  # Copy the mariadbd/mysqld error log from the subreducer run which had a failed startup to /tmp for research
            if [ -r $RESTART_WORKD/log/slave.err ]; then
              cp $RESTART_WORKD/log/slave.err /tmp/${TMP_RND_FILENAME}.slave
            fi
          fi
          if [ "${FIREWORKS}" != "1" ]; then  # We do not want to spam FireWorks mode output
            if grep -E --binary-files=text "Do you already have another.*running|Got error: 98" $RESTART_WORKD/log/*.err 2>/dev/null; then  # A server likely crashed on a different bug
              echoit "$ATLEASTONCE [Stage $STAGE] [WARNING] this script tried to restart the thread with PID #$(eval echo $(echo '$MULTI_PID'"$t")), but failed due to a TCP/IP port address already in use error, which can be seen in $RESTART_WORKD/log/*.err - The most likely reason for this is that this thread previously crashed on another crash then the one specified in TEXT. It is highly unlikely that this script ran into an actual duplicate port issue due to the advanced checking for the same in multi_reducer(). If this message is looping, you want to:  tail -n5 $(echo "${RESTART_WORKD}" | sed 's|/$||;s|/[^/]\+$|/*/log/*.err|')  repeatadely untill you see a crash, followed by actually checking (i.e. vi) the error log quickly (to avoid overwrite) once you see a crash, to see which crash is being generated, and then stop reducer and modify the search TEXT text or make other required changes (like updating MYEXTRA) to find the original bug being looked for. It may work out better to first reduce for the new issue seen; it is likely the same bug. Alternatively, set this reducer to MODE=4 to look for any crash (provided you are reducing for a crash), with the caveat that if the SQL is capable of introducing two different crashes (and it looks like it is), you may end up with the wrong crash reduced. In that case, try again, or research the crash seen as described using the tail command. This script will now attempt to terminate and restart the thread."
            fi
          fi
          # Ensure RESTART_WORKD is actually set
          if [ -z "${RESTART_WORKD}" ]; then echo "Assert: RESTART_WORKD is empty."; exit 1; fi
          # Ensure previous server is gone (new code 24-08-2020 to better deal with assert above)
          if [ ! -z "$(ps -def | grep -E "$RESTART_WORKD/log/master.err|$RESTART_WORKD/log/slave.err")" ]; then
            for i in $(seq 1 3); do
              ( kill -9 $(ps -def | grep "$RESTART_WORKD/log/master.err|$RESTART_WORKD/log/slave.err" | grep -v grep | awk '{print $2}' | tr '\n' ' ') >/dev/null 2>&1; ) >/dev/null 2>&1
            done
          fi
          # Remove all files, except for subreducer script
          rm -Rf $RESTART_WORKD/[^s]*
          rm -Rf $RESTART_WORKD/socket*
          # Restart subreducer and capture PID
          $($RESTART_WORKD/subreducer $1 >/dev/null 2>/dev/null) >/dev/null 2>/dev/null &
          export MULTI_PID$t=$!
          INIT_FILE_USED=
          if [[ "${MEXTRA}" == *"init[-_]file"* ]]; then INIT_FILE_USED="or any file(s) called using --init-file which is present in \$MYEXTRA, "; fi
          if [ ${SUBR_SVR_START_FAILURE} -eq 1 ]; then
            # Check if we ran out of disk space
            if [ ! -r /tmp/$TMP_RND_FILENAME ]; then
              echoit "Assert: /tmp/$TMP_RND_FILENAME not found or not readable! Did the volume hosting /tmp run out of space?"
              echoit "Will try and continue assuming this is a recoverable situation, though it may not be"
            fi
            if egrep --binary-files=text -qi "device full error|no space left on device|errno[:]* enospc|can't write.*bytes|errno[:]* 28|disk full|waiting for someone to free some space|out of disk space|innodb: error while writing|bytes should have been written|error number[:]* 28|error[:]* 28|Disk is full writing|Errcode: 28|No space left on device|Waiting for someone to free space|up to 60 secs delay for server to continue after freeing disk space" /tmp/$TMP_RND_FILENAME*; then
              echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] [OOS] Thread #$t disappeared (mariadbd/mysqld start failed) due to running out of diskspace. Restarted thread with PID #$(eval echo $(echo '$MULTI_PID'"$t"))."
              #echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] [OOS] Copied the last mariadbd/mysqld error log to /tmp/$TMP_RND_FILENAME (and /tmp/$TMP_RND_FILENAME.slave if a started slave was present) for review. Otherwise, please ignore the \"check...\" message just above; the files are no longer there given the restart above)"
            else
              if [ "${FIREWORKS}" != "1" ]; then  # Only show the full output in non-fireworks mode
                echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] Thread #$t disappeared due to a failed start of mariadbd/mysqld inside a subreducer thread, restarted the subreducer thread with PID #$(eval echo $(echo '$MULTI_PID'"$t")) (This will happen irregularly on busy servers OR when there is not sufficient diskspace). If the message is repeating continuously, please investigate. reducer has also copied the last mariadbd/mysqld error log to /tmp/$TMP_RND_FILENAME (and /tmp/$TMP_RND_FILENAME.slave if a started slave was present) for review, though an out of diskpace may not show in there.)"  # This may happen irregularly due to mariadbd/mysqld startup timeouts etc. | Check the last few lines of the subreducer log to find reason (you may need a pause above before the thread is restarted!)
              else
                echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] Thread #$t disappeared. Thread restarted (PID #$(eval echo $(echo '$MULTI_PID'"$t")))"
              fi
            fi
          else
            if [ "${FIREWORKS}" == "1" ]; then
              echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] Thread #$t ended. Thread restarted (PID #$(eval echo $(echo '$MULTI_PID'"$t")))"
            else
              # Only show this in non-fireworks mode. In fireworks mode, this outcome is expected.
              # TODO: The following can be improved much further: this script can actually check for 1) self-existence, 2) workdir existence, 3) any --init-file called SQL files existence, 4) check for for "Access denied for user 'root'" in or "user specified as.*does not exist" (i.e. [ERROR] Event Scheduler: [..@..][test.t1] The user specified as a definer ('..'@'..') does not exist) in log/master.err or log/slave.err and in log/mysqld.out. And if 1/2/3/4 are handled as such, the error message below can be made much nicer and shorter. For example "ERROR: This script (./reducer<nr>.sh) was deleted! Terminating." etc. Make sure that any terminates of scripts are done properly, i.e. if possible still report last optimized file etc.
              if grep -qi 'Access denied for user detected' /dev/shm/$EPOCH/subreducer/*/reducer.log 2>/dev/null; then
                echoit "Assert: Access denied for user detected in at least one of the subreducers. Check:  grep -i 'Access denied for user detected' /dev/shm/$EPOCH/subreducer/*/reducer.log  # This issue may be hard to recover from"
              else
                echo -e "$(date +'%F %T') $ATLEASTONCE [Stage $STAGE] [${RUNMODE}] [WARNING] An issue happened during reduction.\n\nThis can happen on busy servers. This issue can also happen due to any of the following reasons:\n\n1) (Most likely): The storage location you are using (${WORKD}) has run out of space [temporarily]\n2) Another server running on the same port: check the error logs:\n  grep 'already in use' /dev/shm/$EPOCH/subreducer/*/log/*.err\n3) mariadbd/mysqld startup timeouts or failures.\n4) somewhere in the original input file (which may now have been reduced further; i.e. you may start to see this issue only at some part during a run when the flow of SQL changed towards this issue) it may have had a DROP USER root or similar, disallowing access to mariadb-admin/mysqladmin shutdown, causing 'port in use' errors. You can verify this by doing;\n  grep -E 'Access denied for user|Доступ закрыт для пользователя|user specified as.*does not exist' /dev/shm/$EPOCH/subreducer/*/log/*.err\n, or similar. A workaround, for most MODE's (though not MODE=0 / timeout / shutdown based issues), is to use/set FORCE_KILL=1 which avoids using mariadb-admin/mysqladmin shutdown. Another workaround (for advanced users) could be to set PQUERY_REVERSE_NOSHUFFLE_OPT=1 whilst PQUERY_MULTI remains 0 (rearranges SQL; slower but additional reproduction possibility) combined with a higher number (i.e. 30 orso) for MULTI_THREADS. Another possible can be to 'just let it run', hoping that the chuncking elimination will sooner or later remove the failing SQL and that the issue is still reproducible without it.\n5) Somehow ~/mariadb-qa is no longer available (deleted/moved/...) and for example new_text_string.sh cannot be reached.\n6) the server is crashing, _but not_ on the specific text being searched for - try MODE=4.\n7) The base directory (${BASEDIR} was removed/moved/deleted. (Common)\n\nYou may also want to checkout the last few lines of the subreducer log which often help to find the specific issue:\n  tail -n5 /dev/shm/$EPOCH/subreducer/*/reducer.log\nas well as these:\n  tail -n5 /dev/shm/$EPOCH/subreducer/*/log/*.err\n  tail -n5 /dev/shm/$EPOCH/log/mysql*.out /dev/shm/$EPOCH/subreducer/*/log/mysql*.out\nto find out what the issue may be" > /dev/shm/$EPOCH/debug.aid  # TODO: for item #3 for example, this script can parse the log and check for this itself and give a better output here (and simply kill the process intead of attempting mariadb-admin/mysqladmin shutdown, which would better). Another oddity is this; if kill is attempted by default after myaladmin shutdown attempt, then why is there a 'port in use' error at all? That should not happen. Verfied that FORCE_KILL=1 does resolve the port in use issue. # No longer a valid reason; 'did you accidentally delete and/or recreate this script, it's working directory, or the mysql base directory ${INIT_FILE_USED} while this script was running' as we now check file existence and show that immediately rather than this message.
              fi
              echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] [WARNING] Issue detected. Debug info: cat /dev/shm/$EPOCH/debug.aid"
              # TODO: Reason 1 does happen. Observed:
              # 2020-08-24  9:55:45 0 [ERROR] Can't start server: Bind on TCP/IP port. Got error: 98: Address already in use
              # 2020-08-24  9:55:45 0 [ERROR] Do you already have another mysqld server running on port: 49504 ?
              # 2020-08-24  9:55:45 0 [ERROR] Aborting
              # But it should not (and reducer does check for duplicate port use). One (unlikely) reason may be that the server crashed on a bug not-being-looked for and then restarted or something. Not sure what is causing this, needs work. Only very minor incovience in runs as happens infrequently and reducer does handle the restart correctly.
              # Also search for 'A server likely crashed on a different bug' for additional related code. Also odd is that that other code is before this one; why did that code not pickup the 'already in use' before being caught here?
              ### Disabled the sleep here as at times reducer is still able to continue/resume once this is seen (confirmed 12/12/21). An additional reason to disable the sleep is that, to debug, it's often best to repeatedly run things like tail -n5 /dev/shm/$EPOCH/subreducer/*/..., rather than pause and check given that that may not be the correct point-in-time capture (not confirmed).
              ### echoit "Pausing 10 seconds, you may want to press CTRL+Z to pause for longer, and allow you to debug this further. You can always restart the process with 'fg' if it makes sense to to so after analysis."
              ### sleep 10
            fi
          fi
        fi
        sleep 1  # Hasten slowly, server already busy with subreducers
      done
    done
    echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] All subreducer threads have finished/terminated"
  fi

  if [ "$STAGE" = "V" ]; then
    # Check thread outcomes
    TXT_OUT=
    for t in $(eval echo {1..$MULTI_THREADS}); do
      export MULTI_WORKD=$(eval echo $(echo '$WORKD'"$t"))
      if [ -s $MULTI_WORKD/VERIFIED ]; then
        ATLEASTONCE="[*]"  # The issue was seen at least once
        if [ "${PAUSE_AFTER_EACH_OCCURRENCE}" -eq 1 ]; then
          echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] Thread $t reproduced the issue. As PAUSE_AFTER_EACH_OCCURRENCE is set, pausing for analysis. Press enter twice to continue. Directory: ${MULTI_WORKD}"
          if [ -r "${TEXT_STRING_LOC}" ]; then  # Attempt to give more information
            cd $MULTI_WORKD
            if [ "${MULTI_WORKD}" != "${PWD}" ]; then
              echoit "Assert: cd ${MULTI_WORKD} before NEW_TEXT_STRING parsing failed. Terminating."
              exit 1
            fi
            if [ $MDG -eq 1 ]; then
              export GALERA_ERROR_LOG=$WORKD/node${GALERA_NODE}/node${GALERA_NODE}.err
              export GALERA_CORE_LOC=$WORKD/node${GALERA_NODE}/*core*
            fi
            MYBUGFOUND="$(${TEXT_STRING_LOC} "${BIN}" 2>/dev/null)"
            cd - >/dev/null
            echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] NEW_TEXT_STRING Output: ${MYBUGFOUND}"
            MYBUGFOUND=
          fi
          read -p ''
          read -p ''
        fi
        MULTI_FOUND=$[$MULTI_FOUND+1]
        TXT_OUT="$TXT_OUT #$t"
      fi
    done
    # Report on outcomes
    SPORADIC=1  # Sporadic unless proven otherwise (set below)
    if [ $MULTI_FOUND -eq 0 ]; then
      echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] Threads which reproduced the issue: <none>"
    elif [ $MULTI_FOUND -eq $MULTI_THREADS ]; then
      echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] Threads which reproduced the issue:$TXT_OUT"
      if [ $FORCE_SPORADIC -gt 0 ]; then
        echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] All threads reproduced the issue: this issue is not considered sporadic"
        echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] However, as the FORCE_SPORADIC is on, sporadic testcase reduction will commence"
      else
        echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] All threads reproduced the issue: this issue is not sporadic"
        echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] Note: if this issue proves sporadic in actual reduction (slow/stalling reduction), use the FORCE_SPORADIC=1 setting"
        SPORADIC=0
      fi
      if [ $MODE -lt 6 ]; then
        echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] Ensuring any rogue subreducer processes are terminated"
        kill_multi_reducer
      fi
    elif [ $MULTI_FOUND -lt $MULTI_THREADS ]; then
      echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] Threads which reproduced the issue:$TXT_OUT"
      echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] Only $MULTI_FOUND out of $MULTI_THREADS threads reproduced the issue: this issue is sporadic"
      # Do not enable SLOW_DOWN_CHUNK_SCALING=1 here! It is not suited for MULTI mode, as subreducers will then have a fully-static chunck size because of the main reducer.sh keeping the same chunk size, and the subreducers initially take a copy, and instead of scaling their chunks, they keep the chunks from the main one... or something. The visual effect of enabling this here is that x in "Remaining number of lines in input file: x" remains static, acrross many "Thread #y reproduced the issue" trials.
    fi
    return $MULTI_FOUND
  fi
}

multi_reducer_decide_input(){
  echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] Deciding which verified output file to keep out of $MULTI_FOUND threads"
  # This function, based on checking the outcome of the various threads started in multi_reducer() decides which verified input file (from the various
  # subreducer threads) will be kept. It would be best to keep a file with TRIAL=1 (obviously from a succesful verification thread) since such a file
  # would have had maximum simplification applied. As soon such a file is found, reducer can use that one and stop searching.
  LOWEST_TRIAL_LEVEL_SEEN=100
  for t in $(eval echo {1..$MULTI_THREADS}); do
    export MULTI_WORKD=$(eval echo $(echo '$WORKD'"$t"))
    if [ -s $MULTI_WORKD/VERIFIED ]; then
      TRIAL_LEVEL=$(cat $MULTI_WORKD/VERIFIED | grep -E --binary-files=text "TRIAL" | sed -e 's/^.*://' -e 's/[ ]*//g')
      if [ $TRIAL_LEVEL -eq 1 ]; then
        # Highest optimization possible, use file and exit
        cp -f $(cat $MULTI_WORKD/VERIFIED | grep -E --binary-files=text "WORKO" | sed -e 's/^.*://' -e 's/[ ]*//g') $WORKF
        echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] Found verified, maximum initial simplification file, at thread #$t: Using it as new input file"
        if [ -r $MULTI_WORKD/MYEXTRA ]; then
          MYEXTRA=$(cat $MULTI_WORKD/MYEXTRA)
        fi
        break
      elif [ $TRIAL_LEVEL -lt $LOWEST_TRIAL_LEVEL_SEEN ]; then
        LOWEST_TRIAL_LEVEL_SEEN=$TRIAL_LEVEL
        cp -f $(cat $MULTI_WORKD/VERIFIED | grep -E --binary-files=text "WORKO" | sed -e 's/^.*://' -e 's/[ ]*//g') $WORKF
        echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] Found verified, level $TRIAL_LEVEL simplification file, at thread #$t: Using it as new input file, unless better is found"
        if [ -r $MULTI_WORKD/MYEXTRA ]; then
          MYEXTRA=$(cat $MULTI_WORKD/MYEXTRA)
        fi
      fi
    fi
  done
  echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] Removing verify stage subreducer directory"
  rm -Rf $WORKD/subreducer/  # It should be fine to remove this verify stage subreducer directory here, and save space, but this needs over-time confirmation. Added RV 25-10-2016
}

TS_init_all_sql_files(){
  # DATA thread (Single threaded init by RQG - saved as CT[0-9].sql, usually CT2.sql or CT3.sql)
  TSDATA_COUNT=$(ls --color=never $TS_INPUTDIR/CT[0-9]*.sql | wc -l | tr -d '[\t\n ]*')
  if [ $TSDATA_COUNT -eq 1 ]; then
    TS_DATAINPUTFILE=$(ls --color=never $TS_INPUTDIR/CT[0-9]*.sql)
  else
    echo 'ASSERT: do not know how to handle more than one ThreadSync data input file [yet].'
    echo "Terminating now."
    exit 1
  fi

  # SQL threads (Multi-threaded SQL run by RQG - saved as C[0-9]*T[0-9]*.sql)
  TS_REAL_THREAD=0
  for TSSQL in $(ls --color=never $TS_INPUTDIR/C[0-9]*T[0-9]*.sql | sort); do
    TS_REAL_THREAD=$[$TS_REAL_THREAD+1]
    export TS_SQLINPUTFILE$TS_REAL_THREAD=$TSSQL
  done
  if [ ! $TS_REAL_THREAD -eq $TS_THREADS ]; then
    echo 'ASSERT: $TS_REAL_THREAD != $TS_THREADS: '"$TS_REAL_THREAD != $TS_THREADS"
    echo "Terminating now."
    exit 1
  fi
  if [ $TS_ORIG_VARS_FLAG -eq 0 ]; then
    TS_ORIG_DATAINPUTFILE=$TS_DATAINPUTFILE
    TS_ORIG_THREADS=$TS_THREADS
    TS_ORIG_VARS_FLAG=1
  fi
  echoit "[Init] Input directory: $TS_INPUTDIR/"
  echoit "[Init] Input files: Data: $TS_DATAINPUTFILE"
  for t in $(eval echo {1..$TS_THREADS}); do
    export WORKF$t="$WORKD/in$t.sql"
    export WORKT$t="$WORKD/in$t.tmp"
    export WORKO$t=$(eval echo $(echo '$TS_SQLINPUTFILE'"$t") | sed 's/$/_out/' | sed "s/^.*\//$(echo $WORKD | sed 's/\//\\\//g')\/out\//")
    TS_FILE_NAME=$(eval echo $(echo '$TS_SQLINPUTFILE'"$t"))
    echoit "[Init] Input files: Thread $t: $TS_FILE_NAME"
  done
  # Copy of INPUTFILE to WORKF files
  # DDL data thread load is done in run_sql_code. Here reducer handles the SQL threads
  for t in $(eval echo {1..$TS_THREADS}); do
    cat $(eval echo $(echo '$TS_SQLINPUTFILE'"$t")) > $(eval echo $(echo '$WORKF'"$t"))
  done
}

# Find empty port
init_empty_port(){
  # Choose a random port number in 13-47K range, with triple check to confirm it is free
  # Note that reducer.sh uses a 13-47K port range, whereas init_empty_port.sh uses 10-13K to further avoid conflicts
  NEWPORT=$((13001 + ((RANDOM << 15) | RANDOM) % 34001))  # 'RANDOM << 15': 1st $RANDOM is bit-shifted left by 15 places (i.e. * 2^15), '| RANDOM': Bitwise OR operation with a 2nd $RANDOM, which fills the lower 15 bits with a new random number. Result: 30-bit random integer
  DOUBLE_CHECK=0
  while :; do
    # Check if the port is free in four different ways
    ISPORTFREE1="$(netstat -an | tr '\t' ' ' | grep -E --binary-files=text "[ :]${NEWPORT} " | wc -l)"
    ISPORTFREE2="$(ps -ef | grep --binary-files=text "port=${NEWPORT}" | grep --binary-files=text -v 'grep')"
    ISPORTFREE3="$(grep --binary-files=text -o "port=${NEWPORT}" /test/*/start 2>/dev/null | wc -l)"
    ISPORTFREE4="$(netstat -tuln | grep :${NEWPORT})"
    if [ "${ISPORTFREE1}" -eq 0 -a -z "${ISPORTFREE2}" -a "${ISPORTFREE3}" -eq 0 -a -z "${ISPORTFREE4}" ]; then
      if [ "${DOUBLE_CHECK}" -eq 2 ]; then  # If true, then the port was triple checked (to avoid races) to be free
        break  # Suitable free port number found
      else
        DOUBLE_CHECK=$[ ${DOUBLE_CHECK} + 1 ]
        sleep 0.0${RANDOM}  # Random Microsleep to further avoid races
        continue  # Loop the check
      fi
    else
      NEWPORT=$((13001 + ((RANDOM << 15) | RANDOM) % 34001))  # Try a new port
      DOUBLE_CHECK=0  # Reset the double check
      continue  # Recheck the new port
    fi
  done
}

init_workdir_and_files(){
  # Make sure that the directory does not exist yet
  while :; do
    if [ "$MULTI_REDUCER" == "1" ]; then  # This is a subreducer
      WORKD="$(dirname $0)"
      break
    fi
    # Make sure that tmp has enough free space (some minor temporary files are stored there)
    if [ $(df -k -P /tmp | grep -E --binary-files=text -v "Mounted" | awk '{print $4}') -lt 400000 ]; then
      echo 'Error: /tmp does not have enough free space (400Mb free space required for temporary files and any ongoing programs)'
      echo "Terminating now."
      exit 1
    fi
    if [ $WORKDIR_LOCATION -eq 3 ]; then
      if ! [ -d "$WORKDIR_M3_DIRECTORY/" -a -x "$WORKDIR_M3_DIRECTORY/" ]; then
        echo 'Error: WORKDIR_LOCATION=3 (a specific storage location) is set, yet WORKDIR_M3_DIRECTORY (set to $WORKDIR_M3_DIRECTORY) does not exist, or could not be read.'
        echo "Terminating now."
        exit 1
      fi
      if [ $(df -k -P 2>&1 | grep -E --binary-files=text -v "docker.devicemapper" | grep -E --binary-files=text "$WORKDIR_M3_DIRECTORY" | awk '{print $4}') -lt 3500000 ]; then
        echo "Error: $WORKDIR_M3_DIRECTORY does not have enough free space (3.5Gb free space required)"
        echo "Terminating now."
        exit 1
      fi
      WORKD="$WORKDIR_M3_DIRECTORY/$EPOCH"
    elif [ $WORKDIR_LOCATION -eq 2 ]; then
      if ! [ -d "/mnt/ram/" -a -x "/mnt/ram/" ]; then
        echo 'Error: ramfs storage usage was specified (WORKDIR_LOCATION=2), yet /mnt/ram/ does not exist, or could not be read.'
        echo 'Suggestion: setup a ram drive using the following commands at your shell prompt:'
        echo 'sudo mkdir -p /mnt/ram; sudo mount -t ramfs -o size=4g ramfs /mnt/ram; sudo chmod -R 777 /mnt/ram;'
        echo "Terminating now."
        exit 1
      fi
      if [ $(df -k -P 2>&1 | grep -E --binary-files=text -v "docker/devicemapper.*Permission denied" | grep -E --binary-files=text "/mnt/ram$" | awk '{print $4}' | grep -E --binary-files=text -v 'docker.devicemapper') -lt 3500000 ]; then
        echo 'Error: /mnt/ram/ does not have enough free space (3.5Gb free space required)'
        echo "Terminating now."
        exit 1
      fi
      WORKD="/mnt/ram/$EPOCH"
    elif [ $WORKDIR_LOCATION -eq 1 ]; then
      if ! [ -d "/dev/shm/" -a -x "/dev/shm/" ]; then
        echo 'Error: tmpfs storage usage was specified (WORKDIR_LOCATION=1), yet /dev/shm/ does not exist, or could not be read.'
        echo 'Suggestion: check the location of tmpfs using the 'df -h' command at your shell prompt and change the script to match'
        echo "Terminating now."
        exit 1
      fi
      if [ $(df -k -P 2>&1 | grep -E --binary-files=text -v "docker/devicemapper.*Permission denied" | grep -E --binary-files=text "/dev/shm$" | awk '{print $4}' | grep -E --binary-files=text -v 'docker.devicemapper') -lt 3500000 ]; then
        echo 'Error: /dev/shm/ does not have enough free space (3.5Gb free space required)'
        echo "Terminating now."
        exit 1
      fi
      WORKD="/dev/shm/$EPOCH"
    else
      if ! [ -d "/tmp/" -a -x "/tmp/" ]; then
        echo 'Error: /tmp/ storage usage was specified (WORKDIR_LOCATION=0), yet /tmp/ does not exist, or could not be read.'
        echo "Terminating now."
        exit 1
      fi
      if [ $(df -k -P 2>&1 | grep -E --binary-files=text -v "docker/devicemapper.*Permission denied" | grep -E --binary-files=text "[ \t]/$" | awk '{print $4}' | grep -E --binary-files=text -v 'docker.devicemapper') -lt 3500000 ]; then
        echo 'Error: The drive mounted as / does not have enough free space (3.5Gb free space required)'
        echo "Terminating now."
        exit 1
      fi
      WORKD="/tmp/$EPOCH"
    fi
    if [ -d "$WORKD" ]; then
      EPOCH=$[EPOCH-1]
    else
      break
    fi
  done
  if [ "$MULTI_REDUCER" != "1" ]; then  # This is the main reducer
    if [ -d $WORKD ]; then
      echo "Assert: $WORKD already exists? This should not happen (race condition in script or the surrounding setup/environment). Start by reviewing how this script was called."  # EPOCH setup was also changed from date +%s to date +%s%N + this assert was added, both to prevent 'mkdir: cannot create directory ...: File exists' like issues, mainly seen on xargs calls of a large amount of reducer scripts, with or without -P and with or without awk pause attempts (https://stackoverflow.com/a/15159993/1208218). This issue should not happen anymore. If it does, it's serious as it may indicate a race condition in reducer, perhaps in interaction with subreducers or similar, or in the surrounding framework/setup/environment (how was the script called?)
      exit 1
    fi
    mkdir $WORKD
  fi
  if [ $MDG -eq 0 ]; then
    if [ $REPLICATION -eq 1 ]; then
      mkdir $WORKD/data $WORKD/data_slave $WORKD/tmp $WORKD/tmp_slave $WORKD/log  # $WORKD/log contains both master.err and slave.err
    else
      mkdir $WORKD/data $WORKD/tmp $WORKD/log
    fi
  fi
  chmod -R 777 $WORKD
  touch $WORKD/reducer.log
  echoit "[Init] Reducer: $(cd "`dirname $0`" && pwd)/$(basename "$0")"  # With thanks (basename), https://stackoverflow.com/a/192337/1208218
  echoit "[Init] Reducer PID: $$"
  export TMP=$WORKD/tmp
  if [ $REDUCE_GLIBC_OR_SS_CRASHES -gt 0 ]; then echoit "[Init] Console typescript log for REDUCE_GLIBC_OR_SS_CRASHES: /tmp/reducer_typescript${TYPESCRIPT_UNIQUE_FILESUFFIX}.log"; fi
  # jemalloc configuration for TokuDB plugin
  JE1="if [ \"\${JEMALLOC}\" != \"\" -a -r \"\${JEMALLOC}\" ]; then export LD_PRELOAD=\${JEMALLOC}"
  #JE2=" elif [ -r /usr/lib64/libjemalloc.so.1 ]; then export LD_PRELOAD=/usr/lib64/libjemalloc.so.1"
  #JE3=" elif [ -r /usr/lib/x86_64-linux-gnu/libjemalloc.so.1 ]; then export LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.1"
  JE2=" elif [ -r \`sudo find /usr/*lib*/ -name libjemalloc.so.1 | head -n1\` ]; then export LD_PRELOAD=\`sudo find /usr/*lib*/ -name libjemalloc.so.1 | head -n1\`"
  JE3=" elif [ -r \${BASEDIR}/lib/mysql/libjemalloc.so.1 ]; then export LD_PRELOAD=\${BASEDIR}/lib/mysql/libjemalloc.so.1"
  JE4=" else echo 'Warning: jemalloc was not loaded as it was not found (this is fine for MS, but do check ./${EPOCH}_mybase to set correct jemalloc location for PS)'; fi"

  WORK_BUG_DIR=$(echo $INPUTFILE | sed "s|/[^/]\+$||;s|/$||")  # i.e. the directory in which the original $INPUTFILE resides
  if [ "${WORK_BUG_DIR}" == "${INPUTFILE}" -o "${WORK_BUG_DIR}" == "./${INPUTFILE}" ]; then
    WORK_BUG_DIR=${PWD}
  fi
  WORKF="$WORKD/in.sql"
  WORKT="$WORKD/in.tmp"
  WORK_BASEDIR=$(echo $INPUTFILE | sed "s|/[^/]\+$|/|;s|$|${EPOCH}_mybase|")
  WORK_INIT=$(echo $INPUTFILE | sed "s|/[^/]\+$|/|;s|$|${EPOCH}_init|")
  WORK_START=$(echo $INPUTFILE | sed "s|/[^/]\+$|/|;s|$|${EPOCH}_start|")
  WORK_START_VALGRIND=$(echo $INPUTFILE | sed "s|/[^/]\+$|/|;s|$|${EPOCH}_start_valgrind|")
  WORK_STOP=$(echo $INPUTFILE | sed "s|/[^/]\+$|/|;s|$|${EPOCH}_stop|")
  WORK_RUN=$(echo $INPUTFILE | sed "s|/[^/]\+$|/|;s|$|${EPOCH}_run|")
  WORK_GDB=$(echo $INPUTFILE | sed "s|/[^/]\+$|/|;s|$|${EPOCH}_gdb|")
  WORK_PARSE_CORE=$(echo $INPUTFILE | sed "s|/[^/]\+$|/|;s|$|${EPOCH}_parse_core|")
  WORK_HOW_TO_USE=$(echo $INPUTFILE | sed "s|/[^/]\+$|/|;s|$|${EPOCH}_how_to_use.txt|")
  if [ $USE_PQUERY -eq 1 ]; then
    WORK_RUN_PQUERY=$(echo $INPUTFILE | sed "s|/[^/]\+$|/|;s|$|${EPOCH}_run_pquery|")
    WORK_PQUERY_BIN=$(echo $INPUTFILE | sed "s|/[^/]\+$|/|;s|$|${EPOCH}_|" | sed "s|$|$(echo $PQUERY_LOC | sed 's|.*/||')|")
  fi
  WORK_CL=$(echo $INPUTFILE | sed "s|/[^/]\+$|/|;s|$|${EPOCH}_cl|")
  WORK_OUT=$(echo $INPUTFILE | sed "s|/[^/]\+$|/|;s|$|${EPOCH}.sql|")
  if [ $MODE -ge 6 ]; then
    mkdir $WORKD/out
    mkdir $WORKD/log
    TS_init_all_sql_files
  else
    if [ "$MULTI_REDUCER" != "1" ]; then  # This is the parent/main reducer
      WORKO="$(echo $INPUTFILE | sed 's/$/_out/')"
    else
      WORKO="$(echo $INPUTFILE | sed 's/$/_out/' | sed "s/^.*\//$(echo $WORKD | sed 's/\//\\\//g')\//")"  # Save output file in individual workdirs
    fi
    echoit "[Init] Input file: $INPUTFILE"
    if [ "${FIREWORKS}" == "1" ]; then
      echoit "[Init] Output dir (FIREWORKS mode): ${NEW_BUGS_SAVE_DIR}"
    else
      if [ "${WORK_BUG_DIR}" == "${INPUTFULE}" ]; then
        echoit "[Init] Output dir: $PWD"
      else
        echoit "[Init] Output dir: $WORK_BUG_DIR"
      fi
    fi
    # Initial INPUTFILE to WORKF copy
    if [ "${FIREWORKS}" != "1" ]; then  # In fireworks mode, we do not need a WORKF file (ref cut_fireworks_chunk_and_shuffle and note ${INPUTFILE} is used instead. The reason for setting it up this way is 1) it greatly improves /dev/shm diskspace as WORKF is not created per-thread, thereby saving let's say 450MB for a standard SQL input file, per-thread, 2) There is no need to maintain a working file (WORKF) as the input is never changed/reduced. INPUTFILE is shuffled and chuncked (as per FIREWORKS_LINES setting) and saved as in.tmp, and if a new bug is found, that file is copied to NEW_BUGS_SAVE_DIR.
      if [ "$MULTI_REDUCER" != "1" -a $FORCE_SKIPV -gt 0 ]; then  # This is the parent/main reducer and verify stage is being skipped, add dropc. If the verify stage is not being skipped (FORCE_SKIPV=0) then the 'else' clause will apply and the verify stage will handle the dropc addition or not (depending on how much initial simplification in the verify stage is possible). Note that FORCE_SKIPV check is defensive programming and not needed atm; the actual call within the verify() uses multi_reducer $1 - i.e. the original input file is used, not the here-modified WORKF file.
        if [ $USE_PQUERY -eq 0 ]; then  # Standard mysql client is used; DROPC can be on a single line
          #Improvement made on 25/01/2021 RV: the original line was seen producing 'ignoring null byte in input'. I am not 100% confident on this change as testing went into the original line construction many years ago. Monitor results over time. This code was also changed elsewhere in reducer.sh, search for 'DROPC can be on a single line'.
          #echo "$(echo "$DROPC";cat $INPUTFILE | grep -E --binary-files=text -v "$DROPC")" > $WORKF
          echo "$DROPC" > $WORKF
          grep -E --binary-files=text -v "$DROPC" $INPUTFILE >> $WORKF
        else  # pquery is used; use a multi-line format for DROPC
          cp $INPUTFILE $WORKF
          # Clean any DROPC statements from WORKT (similar to the grep -v above but for multiple lines instead)
          remove_dropc $WORKF
          # Re-setup DROPC using multiple lines (ref remove_dropc() for more information)
          DROPC_UNIQUE_FILESUFFIX=$RANDOM$RANDOM
          echo "$(echo "$DROPC" | sed 's|;|;\n|g' | grep --binary-files=text -vE '^$')" > /tmp/WORKF_${DROPC_UNIQUE_FILESUFFIX}.tmp
          cat $WORKF >> /tmp/WORKF_${DROPC_UNIQUE_FILESUFFIX}.tmp
          rm -f $WORKF
          mv /tmp/WORKF_${DROPC_UNIQUE_FILESUFFIX}.tmp $WORKF
        fi
      else  # This is a subreducer, or a normal run with FORCE_SKIPV=0, thus do not remove/add dropc again (i.e. do not modify what the main reducer has passed)
        cp $INPUTFILE $WORKF
      fi
      # If QC we don't need queries after first difference found
      if [ ! -z "$QCTEXT" ]; then
        sed -i "/$QCTEXT/q" $WORKF
      fi
    fi
  fi
  echoit "[Init] Base dir: $BASEDIR"
  echoit "[Init] Work dir: $WORKD"
  echoit "[Init] EPOCH ID: $EPOCH (used for various file and directory names)"
  if [ $MDG -eq 1 ]; then
    for i in $(seq 1 "${NR_OF_NODES}"); do
      echoit "[Init] MDG Node #${i} Client: $BASEDIR/bin/mysql -uroot -S$WORKD/node${i}/node${i}_socket.sock"
    done
  elif [ $GRP_RPL -eq 1 ]; then
    echoit "[Init] Group Replication Node #1 Client: $BASEDIR/bin/mysql -uroot -S$WORKD/node1/node1_socket.sock"
    echoit "[Init] Group Replication Node #2 Client: $BASEDIR/bin/mysql -uroot -S$WORKD/node2/node2_socket.sock"
    echoit "[Init] Group Replication Node #3 Client: $BASEDIR/bin/mysql -uroot -S$WORKD/node3/node3_socket.sock"
  elif [ $REPLICATION -eq 1 ]; then
    echoit "[Init] Standard Master/Slave replication is active"
    echoit "[Init] Replication Master Client (When MULTI mode is not active): $BASEDIR/bin/mysql -uroot -S$WORKD/socket.sock"
    echoit "[Init] Replication Slave Client (When MULTI mode is not active): $BASEDIR/bin/mysql -uroot -S$WORKD/slave_socket.sock"
    echoit "[Init] Replication Master Client example for subreducers (MULTI): $BASEDIR/bin/mysql -uroot -S$WORKD/subreducer/1/socket.sock"
    echoit "[Init] Replication Slave Client example for subreducers (MULTI): $BASEDIR/bin/mysql -uroot -S$WORKD/subreducer/1/slave_socket.sock"
  else
    echoit "[Init] Server: ${BIN} (as $MYUSER)"
    if [ $REDUCE_GLIBC_OR_SS_CRASHES -gt 0 ]; then
      echoit "[Init] Client: $BASEDIR/bin/mysql -uroot -S$WORKD/socket.sock"
    else
      if [ "${FIREWORKS}" != "1" ]; then
        echoit "[Init] Client (When MULTI mode is not active): $BASEDIR/bin/mysql -uroot -S$WORKD/socket.sock"
        echoit "[Init] Client example for subreducers (MULTI): $BASEDIR/bin/mysql -uroot -S$WORKD/subreducer/1/socket.sock"
      else
        echoit "[Init] Client example: $BASEDIR/bin/mysql -uroot -S$WORKD/subreducer/1/socket.sock"
      fi
    fi
  fi
  if [ $MDG -eq 1 ]; then
    echoit "[Init] Galera Cluster Temporary directories (TMP Variable) set to $WORKD/tmp[1-$NR_OF_NODES]"
  else
    echoit "[Init] Temporary directory (TMP Variable) set to $TMP"
  fi
  if [ $SKIPSTAGEBELOW -gt 0 ]; then echoit "[Init] SKIPSTAGEBELOW active. Stages up to and including $SKIPSTAGEBELOW are skipped"; fi
  if [ $SKIPSTAGEABOVE -lt 9 ]; then echoit "[Init] SKIPSTAGEABOVE active. Stages above and including $SKIPSTAGEABOVE are skipped"; fi
  if [ $PQUERY_MULTI -gt 0 ]; then
    echoit "[Init] PQUERY_MULTI mode active, so automatically set USE_PQUERY=1: testcase reduction will be done using pquery"
    if [ $PQUERY_REVERSE_NOSHUFFLE_OPT -gt 0 ]; then
      echoit "[Init] PQUERY_MULTI mode active, PQUERY_REVERSE_NOSHUFFLE_OPT on: Semi-true multi-threaded testcase reduction using pquery sequential replay commencing";
    else
      echoit "[Init] PQUERY_MULTI mode active, PQUERY_REVERSE_NOSHUFFLE_OPT off: True multi-threaded testcase reduction using pquery random replay commencing";
    fi
  else
    if [ $PQUERY_REVERSE_NOSHUFFLE_OPT -gt 0 ]; then
      if [ $FORCE_SKIPV -gt 0 -a $FORCE_SPORADIC -gt 0 ]; then
        echoit "[Init] PQUERY_REVERSE_NOSHUFFLE_OPT turned on. Replay will be random instead of sequential (whilst still using a single thread client per mariadbd/mysqld)"
      else
        echoit "[Init] PQUERY_REVERSE_NOSHUFFLE_OPT turned on. Replay will be random instead of sequential (whilst still using a single thread client per mariadbd/mysqld). This setting is best combined with FORCE_SKIPV=1 and FORCE_SPORADIC=1 ! Please edit the settings, unless you know what you're doing"
      fi
    fi
  fi
  if [ $FORCE_SKIPV -gt 0 -a "${FIREWORKS}" != "1" ]; then
    if [ "$MULTI_REDUCER" != "1" -a "$SKIPSTAGEBELOW" -lt 2 ]; then  # This is the main reducer and we're in stage < 2
      echoit "[Init] FORCE_SKIPV active. Verify stage skipped, and immediately commencing multi threaded simplification"
    else  # This is a subreducer (i.e. not multi-threaded), or a main reducer in stage >= 2 (later stages are not multi-threaded)
      echoit "[Init] FORCE_SKIPV active. Verify stage skipped, and immediately commencing simplification"
    fi
  fi
  if [ $FORCE_SKIPV -gt 0 -a $FORCE_SPORADIC -gt 0 -a "${FIREWORKS}" != "1" ]; then echoit "[Init] FORCE_SKIPV active, so FORCE_SPORADIC is automatically set active also" ; fi
  if [ $REDUCE_GLIBC_OR_SS_CRASHES -gt 0 ]; then
    if [ $FORCE_SKIPV -gt 0 ]; then
      echoit "[Init] REDUCE_GLIBC_OR_SS_CRASHES active, so automatically skipping VERIFY mode as GLIBC crashes may be sporadic more often (this happens irrespective of FORCE_SKIPV=1)"
    else
      echoit "[Init] REDUCE_GLIBC_OR_SS_CRASHES active, so automatically skipping VERIFY mode as GLIBC crashes may be sporadic more often"
    fi
    echoit "[Init] REDUCE_GLIBC_OR_SS_CRASHES active, so automatically set SLOW_DOWN_CHUNK_SCALING=1 to slow down chunk size scaling (both for chunk reductions and increases)"
    if [ $FORCE_SPORADIC -gt 0 ]; then
      echoit "[Info] FORCE_SPORADIC active, issue is assumed to be sporadic"
      echoit "[Init] FORCE_SPORADIC active: STAGE1_LINES variable was overwritten and set to $STAGE1_LINES to match"
    fi
    if [ $MODE -eq 3 ]; then
      echoit "[WARNING] ---------------------"
      echoit "[WARNING] REDUCE_GLIBC_OR_SS_CRASHES active and MODE=3. Have you updated the TEXT=\"...\" to a search string matching the console (on-screen) output of a GLIBC crash instead of using some text from the error log (which is not scanned now)? The output of a GLIBC crash is on the main console stdout, so a copy/paste of a suitable search string may be made directly from the console. A GLIBC crash looks similar to this: *** Error in \`/sda/PS180516-percona-server-5.6.30-76.3-linux-x86_64-debug/bin/mysqld': corrupted double-linked list: 0x00007feb2c0011e0 ***. For the TEXT search string, do not use the hex address but instead, for example, 'corrupted double-linked list', or a specfic frame from the stack trace which is normally shown below this intro line. Note that the message can also look like this (on Ubuntu); *** stack smashing detected ***: /your_basedir/bin/mysqld terminated. The best way to find out what the message is on your system is to run reducer first normally (without REDUCE_GLIBC_OR_SS_CRASHES set, and check what the output is. Alternatively, set MODE=4 to look for any GLIBC crash. If this reducer.sh was generated by pquery-prep-red.sh, then note that TEXT would have been automatically set to content from the error log, or to a more generic MODE=4, but neither of these will reduce for GLIBC crashes (is MODE=3 this is because the error log is not scanned, and in MODE=4 this is because the GLIBC crash (or stack smash) may be offset/different from any crash in the error log). Instead, set the TEXT string to a GLIBC specific string as described."
      echoit "[WARNING] ---------------------"
    fi
  else
    if [ $FORCE_SPORADIC -gt 0 -a "${FIREWORKS}" != "1" ]; then
      if [ $FORCE_SKIPV -gt 0 ]; then
        echoit "[Init] FORCE_SPORADIC active. Issue is assumed to be sporadic"
      else
        echoit "[Init] FORCE_SPORADIC active. Issue is assumed to be sporadic, even if verify stage shows otherwise"
      fi
      # TODO: this is shown, but no actual change is made and the output shown matches the original setting. Thus the output is invalid. Removed ftm. RV 19/06/2020
      # echoit "[Init] FORCE_SPORADIC, FORCE_SKIPV and/or PQUERY_MULTI active: STAGE1_LINES variable was overwritten and set to $STAGE1_LINES to match"
    fi
  fi
  if [ $FORCE_SPORADIC -gt 0 ]; then
    if [ "${FIREWORKS}" != "1" ]; then  # Does not make much/any sense to show this when FIREWORKS mode is enabled
      echoit "[Init] FORCE_SPORADIC active, so automatically enabled SLOW_DOWN_CHUNK_SCALING to speed up testcase reduction (SLOW_DOWN_CHUNK_SCALING_NR is set to $SLOW_DOWN_CHUNK_SCALING_NR)"
    fi
  fi
  if [ "${PAUSE_AFTER_EACH_OCCURRENCE}" == "1" ]; then
    echoit "[Init] PAUSE_AFTER_EACH_OCCURRENCE active, so reducer will pause after each occurrence of the issue"
  fi
  if [ ${REDUCE_STARTUP_ISSUES} -eq 1 ]; then
    echoit "[Init] REDUCE_STARTUP_ISSUES active. Issue is assumed to be a startup issue"
    echoit "[Info] Note: REDUCE_STARTUP_ISSUES is normally used for debugging mariadbd/mysqld startup issues only; for example caused by a misbehaving --option to mariadbd/mysqld. You may want to make the SQL input file really small (for example 'SELECT 1;' only) to ensure that when the particular issue being debugged is not seen, reducer will not spent a long time on executing SQL unrelated to the real issue, i.e. failing mariadbd/mysqld startup"
  fi
  if [ $ENABLE_QUERYTIMEOUT -gt 0 ]; then
    echoit "[Init] Querytimeout: ${QUERYTIMEOUT}s (For RQG-originating testcase reductions, ensure this is at least 1.5x what was set in RQG using the --querytimeout option)"
  fi
  if [ "${FIREWORKS}" == "1" ]; then
    echoit "[Init] FIREWORKS Mode active. Newly discovered bugs will be saved to ${NEW_BUGS_SAVE_DIR}"
  elif [ "${SCAN_FOR_NEW_BUGS}" == "1" ]; then
    echoit "[Init] SCAN_FOR_NEW_BUGS active. Newly discovered bugs will be saved to ${NEW_BUGS_SAVE_DIR}"
  fi
  if [ $USE_PQUERY -eq 0 ]; then
    if   [ ${CLI_MODE} -eq 0 ]; then echoit "[Init] Using the mysql client for SQL replay. CLI_MODE: 0 (cat input.sql | mysql)";
    elif [ ${CLI_MODE} -eq 1 ]; then echoit "[Init] Using the mysql client for SQL replay. CLI_MODE: 1 (mysql --execute='SOURCE input.sql')";  # input.sql is not the actual name, it is just use here for brevity/clarification purposes
      # TODO: Remove this additional output once #81782 is fixed and --binary-mode is added elsewhere in this script (both in the actual replay module as well as in the WORK_RUN file creation)
      echoit "[Warning] Please note CLI_MODE=1 is currently not recommended for use, due to MySQL Bug #81782"
      echoit "[Warning] If your issue fails to reproduce, is is recommended to parse the input file as follows:"
      echoit "[Warning]   cat yourinputfile.sql | tr -d '\\0' > newinputfile.sql  # Then use newinputfile.sql instead"
      echoit "[Warning] before using this CLI mode - to avoid the SOURCE replay terminating early on a NULL character"
      echoit "[Warning] Once bug #81782 is fixed, --binary-mode can be used instead as CLI_MODE 0 and 2 currently use"
      echoit "[Warning] Note however that removing NULL characters from the input may reduce reproducibility"
      echoit "[Warning] In summary, please consider using CLI_MODE=0 or CLI_MODE=2 instead of CLI_MODE=1"
    elif [ ${CLI_MODE} -eq 2 ]; then echoit "[Init] Using the mysql client for SQL replay. CLI_MODE: 2 (mysql < input.sql)";
    else echo "Error: CLI_MODE!=0,1,2: CLI_MODE=${CLI_MODE}"; exit 1; fi
  else
    echoit "[Init] Using the pquery client for SQL replay"
    if [ ${PQUERY_MULTI} -eq 0 ]; then
      if [ ${PQUERY_REVERSE_NOSHUFFLE_OPT} -eq 0 ]; then
        echoit "[Init] Using sequential (non-shuffled) single-thread replay"
      else
        echoit "[Init] Using shuffled (random/non-sequential) single-thread replay"
      fi
    else
      if [ ${PQUERY_REVERSE_NOSHUFFLE_OPT} -eq 1 ]; then
        echoit "[Init] Using sequential (non-shuffled) multi-threaded replay"
      else
        echoit "[Init] Using shuffled (random/non-sequential) multi-threaded replay"
      fi
    fi
  fi
  if [ ${NR_OF_TRIAL_REPEATS} -gt 1 ]; then
    echoit "[Init] Number of times each individual trial will be attempted: ${NR_OF_TRIAL_REPEATS}x"
  fi
  if [ ${NR_OF_TRIAL_REPEATS} -gt 50 ]; then
    echoit "[Init] Note: NR_OF_TRIAL_REPEATS is set larger than 50. This will take a long time."
  fi
  if [ ${NR_OF_TRIAL_REPEATS} -gt 1 -a ${SKIPSTAGEBELOW} -eq 0 ]; then
    # As NR_OF_TRIAL_REPEATS is set >1, reducer sets SKIPSTAGEBELOW to 1 to avoid stage 1 single-threaded reduction attempts (with block chuncks, and without trial repeats) in the case where STAGE1_LINES was set to a number less than the (restructured) testcase. This is the most straightforward and best approach to negate this possibility.
    echoit "[Init] NR_OF_TRIAL_REPEATS>1: setting SKIPSTAGEBELOW=1, ensuring repeated line-by-line reduction trials"
    export -n SKIPSTAGEBELOW=1
  fi
  if [ -n "$MYEXTRA" -o -n "$SPECIAL_MYEXTRA_OPTIONS" ]; then echoit "[Init] Passing the following additional options to mariadbd/mysqld: $SPECIAL_MYEXTRA_OPTIONS $MYEXTRA"; fi
  if [ "$MYINIT" != "" ]; then echoit "[Init] Passing the following additional options to mariadbd/mysqld initialization: $MYINIT"; fi
  if [ $MODE -ge 6 ]; then
    if [ $TS_TRXS_SETS -eq 1 ]; then echoit "[Init] ThreadSync: using last transaction set (accross threads) only"; fi
    if [ $TS_TRXS_SETS -gt 1 ]; then echoit "[Init] ThreadSync: using last $TS_TRXS_SETS transaction sets (accross threads) only"; fi
    if [ $TS_TRXS_SETS -eq 0 ]; then echoit "[Init] ThreadSync: using complete input files (you may want to set TS_DS_TIMEOUT=10 [seconds] or less)"; fi
    if [ $TS_VARIABILITY_SLEEP -gt 0 ]; then echoit "[Init] ThreadSync: will wait $TS_VARIABILITY_SLEEP seconds before each new transaction set is processed"; fi
    echoit "[Init] ThreadSync: default DEBUG_SYNC timeout (TS_DS_TIMEOUT): $TS_DS_TIMEOUT seconds"
    if [ $TS_DBG_CLI_OUTPUT -eq 1 ]; then
      echoit "[Init] ThreadSync: using debug (-vvv) mysql CLI output logging"
      echoit "[Warning] ThreadSync: ONLY use -vvv logging for debugging, as this *will* cause issue non-reproducilbity due to excessive disk logging!"
    fi
  fi
  if [ $MDG -gt 0 ]; then
    echoit "[Init] MDG active, so automatically set USE_PQUERY=1: MariaDB Galera Cluster testcase reduction is currently supported with pquery only"
    if [ $MODE -eq 5 -o $MODE -eq 3 ]; then
      echoit "[Warning] MODE=$MODE is set, as well as MDG mode active. This combination will likely work, but has not been tested yet. Please remove this warning (for MODE=$MODE only please) when it was tested succesfully"
    fi
    if [ $MODE -eq 4 ]; then
      if [ $MDG_ISSUE_NODE -eq 0 ]; then
        echoit "[Info] All MDG nodes will be checked for the issue. As long as one node reproduces, testcase reduction will continue (MDG_ISSUE_NODE=0)"
      fi
      for i in $(seq 1 ${NR_OF_NODES}); do
       echoit "[Info] Important: MDG_ISSUE_NODE is set to ${i}, so only MDG node ${i} will be checked for the presence of the issue"
      done
    fi
  fi
  if [ $GRP_RPL -gt 0 ]; then
    echoit "[Init] GRP_RPL active, so automatically set USE_PQUERY=1: Group Replication Cluster testcase reduction is currently supported only with pquery"
    if [ $MODE -eq 5 -o $MODE -eq 3 ]; then
      echoit "[Warning] MODE=$MODE is set, as well as Group Replication mode active. This combination will likely work, but has not been tested yet. Please remove this warning (for MODE=$MODE only please) when it was tested succesfully"
    fi
    if [ $MODE -eq 4 ]; then
      if [ $GRP_RPL_ISSUE_NODE -eq 0 ]; then
        echoit "[Info] All Group Replication nodes will be checked for the issue. As long as one node reproduces, testcase reduction will continue (GRP_RPL_ISSUE_NODE=0)"
      elif [ $GRP_RPL_ISSUE_NODE -eq 1 ]; then
        echoit "[Info] Important: GRP_RPL_ISSUE_NODE is set to 1, so only MDG node 1 will be checked for the presence of the issue"
      elif [ $GRP_RPL_ISSUE_NODE -eq 2 ]; then
        echoit "[Info] Important: GRP_RPL_ISSUE_NODE is set to 2, so only MDG node 2 will be checked for the presence of the issue"
      elif [ $GRP_RPL_ISSUE_NODE -eq 3 ]; then
        echoit "[Info] Important: GRP_RPL_ISSUE_NODE is set to 3, so only MDG node 3 will be checked for the presence of the issue"
      fi
    fi
  fi
  if [ "$MULTI_REDUCER" != "1" ]; then  # This is a parent/main reducer
    # Get version specific options
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
      INIT_TOOL="${BASEDIR}/scripts/mysql_install_db"
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
      echo "WARNING: mariadbd/mysqld (${BIN}) version detection failed. This is likely caused by using this script with a non-supported distribution or version of mariadbd/mysqld. Please expand this script to handle (which shoud be easy to do). Even so, the scipt will now try and continue as-is, but this may fail."
    fi
    if [[ $MDG -ne 1 && $GRP_RPL -ne 1 ]]; then
      echoit "[Init] Setting up standard data directory working template (without using MYEXTRA options)"
      generate_run_scripts
      ${INIT_TOOL} ${INIT_OPT} --basedir=$BASEDIR --datadir=$WORKD/data ${MID_OPTIONS} --user=$MYUSER > $WORKD/init.log 2>&1
      if [ ! -d "$WORKD/data" ]; then
        echoit "$ATLEASTONCE [Stage $STAGE] [ERROR] data directory at $WORKD/data does not exist... check $WORKD/log/mysqld.out, $WORKD/log/*.err and $WORKD/init.log"
        echo "Terminating now."
        exit 1
      else
        # Note that 'mv data data.init' needs to come BEFORE first mariadbd/mysqld startup attempt, to not pollute the template with an actual mariadbd/mysqld startup (think --init-file, tokudb, and the reduction of startup options in STAGE8)
        if [ ! -d "${WORKD}" ]; then abort; fi
        mv ${WORKD}/data ${WORKD}/data.init
        mkdir -p ${WORKD}/data
        cp -a ${WORKD}/data.init/* ${WORKD}/data/  # We need this for the first mariadbd/mysqld startup attempt just below
        if [ "${REPLICATION}" -eq 1 ]; then
          mkdir -p ${WORKD}/data_slave
          cp -a ${WORKD}/data.init/* ${WORKD}/data_slave/
        fi
        chmod -R 777 ${WORKD}
      fi
      if [ "$(du -sc $WORKD/data.init | grep -v 'total' | awk '{print $1}')" == "0" ]; then
        echoit "$ATLEASTONCE [Stage $STAGE] [ERROR] data directory at $WORKD/data.init is 0 bytes. The volume likely ran out of space"
        echo "Terminating now."
        exit 1
      fi
      if [ "${REPLICATION}" -ne 1 ]; then
        echoit "[Init] Attempting first mariadbd/mysqld startup with all MYEXTRA options passed"
      else
        echoit "[Init] Attempting first mariadbd/mysqld startups (master & slave) with all MYEXTRA* options passed"
      fi
      FIRST_MYSQLD_START_FLAG=1
      if [ $MODE -ne 1 -a $MODE -ne 6 ]; then start_mysqld_main; else start_valgrind_mysqld_main; fi
      ADMIN_BIN_TO_USE="${BASEDIR}/bin/mariadb-admin"
      if [ ! -r "${ADMIN_BIN_TO_USE}" ]; then ADMIN_BIN_TO_USE="${BASEDIR}/bin/mysqladmin"; fi
      if ! ${ADMIN_BIN_TO_USE} -uroot -S$WORKD/socket.sock ping > /dev/null 2>&1; then
        if [ ${REDUCE_STARTUP_ISSUES} -eq 1 ]; then
          echoit "[Init] [NOTE] Failed to cleanly start mariadbd/mysqld server (This was the 1st startup attempt with all MYEXTRA options passed to mariadbd/mysqld). Normally this would cause reducer.sh to halt here (and advice you to check $WORKD/log/mysqld.out, $WORKD/log/*.err, $WORKD/init.log and maybe $WORKD/data/error.log + check that there is plenty of space on the device being used). However, because REDUCE_STARTUP_ISSUES is set to 1, we continue this reducer run. See above for more info on the REDUCE_STARTUP_ISSUES setting"
        else
          echoit "[Init] [ERROR] Failed to start the mariadbd/mysqld server (This was the 1st startup attempt with all MYEXTRA options passed to mariadbd/mysqld), check $WORKD/log/mysqld.out, $WORKD/log/*.err, $WORKD/init.log and maybe $WORKD/data/error.log. Also check that there is plenty of space on the device being used"  # Do not change the text 'Failed to start the.*server' without updating it everwhere else in this script, including the place where reducer checks whether subreducers having run into this error!
          echoit "[Init] [INFO] If however you want to debug a mariadbd/mysqld startup issue, for example caused by a misbehaving --option to mariadbd/mysqld, set REDUCE_STARTUP_ISSUES=1 and restart reducer.sh"
          echo "Terminating now."
          exit 1
        fi
      else
        echoit "[Init] First mariadbd/mysqld startup with all MYEXTRA options passed to mariadbd/mysqld successful"
      fi
      ADMIN_BIN_TO_USE=
      if [ $LOAD_TIMEZONE_DATA -gt 0 ]; then
        echoit "[Init] Loading timezone data into mysql database"
        # echoit "[Info] You may safely ignore any 'Warning: Unable to load...' messages, unless there are very many (Ref. BUG#13563952)"
        # The ones listed in BUG#13563952 are now filterered out to make output nicer
        $BASEDIR/bin/mysql_tzinfo_to_sql /usr/share/zoneinfo > $WORKD/timezone.init 2> $WORKD/timezone.err
        grep -E --binary-files=text -v "Riyadh8[789]'|zoneinfo/iso3166.tab|zoneinfo/zone.tab" $WORKD/timezone.err > $WORKD/timezone.err.tmp
        for A in $(cat $WORKD/timezone.err.tmp|sed 's/ /=DUMMY=/g'); do
          echoit "$(echo "[Warning from mysql_tzinfo_to_sql] $A" | sed 's/=DUMMY=/ /g')"
        done
        echoit "[Info] If you see a [GLIBC] crash above, change reducer to use a non-Valgrind-instrumented build of mysql_tzinfo_to_sql (Ref. BUG#13498842)"
        $BASEDIR/bin/mysql -uroot -S$WORKD/socket.sock --force mysql < $WORKD/timezone.init
      fi
      stop_mysqld_or_mdg
    elif [[ $MDG -eq 1 ]]; then
      echoit "[Init] Setting up standard MDG data directory working template (without using MYEXTRA options)"
      for i in $(seq 1 ${NR_OF_NODES}); do
        node="${WORKD}/node${i}"
        ${INIT_TOOL} ${INIT_OPT} --basedir=$BASEDIR ${MID_OPTIONS} --user=$MYUSER --datadir=$node  > ${WORKD}/startup_node${i}_error.log 2>&1
        mkdir $WORKD/node${i}.init
        cp -a $WORKD/node${i}/* $WORKD/node${i}.init/
      done
    elif [[ $GRP_RPL -eq 1 ]]; then
      echoit "[Init] Setting up standard Group Replication data directory working template (without using MYEXTRA options)"
      BIN_TO_USE="${BASEDIR}/bin/mariadbd"
      if [ ! -r "${BIN_TO_USE}" ]; then BIN_TO_USE="${BASEDIR}/bin/mysqld"; fi
      MID="${BIN_TO_USE} --no-defaults --initialize-insecure ${MYINIT} --basedir=${BASEDIR}"
      BIN_TO_USE=
      node1="${WORKD}/node1"
      node2="${WORKD}/node2"
      node3="${WORKD}/node3"
      ${MID} --datadir=$node1  > ${WORKD}/startup_node1_error.log 2>&1 || exit 1;
      ${MID} --datadir=$node2  > ${WORKD}/startup_node2_error.log 2>&1 || exit 1;
      ${MID} --datadir=$node3  > ${WORKD}/startup_node3_error.log 2>&1 || exit 1;
      mkdir $WORKD/node1.init $WORKD/node2.init $WORKD/node3.init
      cp -a $WORKD/node1/* $WORKD/node1.init/
      cp -a $WORKD/node2/* $WORKD/node2.init/
      cp -a $WORKD/node3/* $WORKD/node3.init/
    fi
    FIRST_MYSQLD_START_FLAG=0  # From here onwards, FORCE_KILL can be used if used if it set enabled (set to 1)
  else
    if [[ $MDG -eq 1 ]]; then
      echoit "[Init] This is a subreducer process; using initialization data template from the main process ($WORKD/../../node*.init)"
    else
      echoit "[Init] This is a subreducer process; using initialization data template from the main process ($WORKD/../../data.init)"
    fi
  fi
}

generate_run_scripts(){
  if [ "${FIREWORKS}" == "1" ]; then  # No need to generate run sripts in FIREWORKS mode
    return 0
  fi
  # Add various scripts (with {epoch} prefix): _mybase (setup variables), _init (setup), _run (runs the sql), _cl (starts a client/CLI), _stop (stop mariadbd/mysqld). _start (starts mariadbd/mysqld)
  # (start_mysqld_main and start_valgrind_mysqld_main). Togheter these scripts can be used for executing the final testcase ($WORKO_start > $WORKO_run)
  if [[ ${MDG} -eq 1 ]]; then
    local EPOCH_SOCKET="/dev/shm/${EPOCH}/node${GALERA_NODE}/node${GALERA_NODE}_socket.sock"
    local EPOCH_ERROR_LOG="/dev/shm/${EPOCH}/node${GALERA_NODE}/node${GALERA_NODE}.err"
  else
    local EPOCH_SOCKET="/dev/shm/${EPOCH}/socket.sock"
    local EPOCH_ERROR_LOG="/dev/shm/${EPOCH}/log/master.err"
  fi
  echo "BASEDIR=$BASEDIR" | sed 's|^[ \t]*||;s|[ \t]*$||;s|/$||' > $WORK_BASEDIR
  echo "SOURCE_DIR=\$BASEDIR  # Only required to be set if make_binary_distrubtion script was NOT used to build MySQL" | sed 's|^[ \t]*||;s|[ \t]*$||;s|/$||' >> $WORK_BASEDIR
  echo "JEMALLOC=~/libjemalloc.so.1  # Only required for Percona Server with TokuDB. Can be completely ignored otherwise. This can be changed to a custom path to use a custom jemalloc. If this file is not present, the standard OS locations for jemalloc will be checked" >> $WORK_BASEDIR
  echo "#!/bin/bash" > $WORK_INIT
  echo "SCRIPT_DIR=\$(cd \$(dirname \$0) && pwd)" >> $WORK_INIT
  echo ". \$SCRIPT_DIR/${EPOCH}_mybase" >> $WORK_INIT
  echo "echo \"Attempting to prepare mariadbd/mysqld environment at /dev/shm/${EPOCH}...\"" >> $WORK_INIT
  echo "rm -Rf /dev/shm/${EPOCH}" >> $WORK_INIT
  if [[ ${MDG} -eq 0 ]]; then
    echo "mkdir -p /dev/shm/${EPOCH}/tmp /dev/shm/${EPOCH}/log" >> $WORK_INIT
  fi
  echo "BIN=\`find -L \${BASEDIR} -maxdepth 2 -name mariadbd -type f -o -name mysqld -type f -o -name mysqld-debug -type f -o -name mysqld -type l -o -name mysqld-debug -type l | head -1\`" >> $WORK_INIT
  echo "if [ -n \"\$BIN\" ]; then" >> $WORK_INIT
  echo "  if [ \"\$BIN\" != \"\${BASEDIR}/bin/mysqld\" -a \"\$BIN\" != \"\${BASEDIR}/bin/mysqld-debug\" ];then" >> $WORK_INIT
  echo "    if [ ! -h \${BASEDIR}/bin/mysqld -o ! -f \${BASEDIR}/bin/mysqld ]; then mkdir -p \${BASEDIR}/bin; ln -s \$BIN \${BASEDIR}/bin/mysqld; fi" >> $WORK_INIT
  echo "    if [ ! -h \${BASEDIR}/bin/mysql -o ! -f \${BASEDIR}/bin/mysql ]; then ln -s \${BASEDIR}/client/mysql \${BASEDIR}/bin/mysql ; fi" >> $WORK_INIT
  echo "    if [ ! -h \${BASEDIR}/share -o ! -f \${BASEDIR}/share ]; then ln -s \${SOURCE_DIR}/scripts \${BASEDIR}/share ; fi" >> $WORK_INIT
  echo -e "    if [ ! -h \${BASEDIR}/share/errmsg.sys -o ! -f \${BASEDIR}/share/errmsg.sys ]; then ln -s \${BASEDIR}/sql/share/english/errmsg.sys \${BASEDIR}/share/errmsg.sys ; fi;\n  fi\nelse" >> $WORK_INIT
  echo -e "  echo \"Assert! mysqld binary '\$BIN' could not be read\";exit 1;\nfi" >> $WORK_INIT
  echo "MID=\`find \${BASEDIR} -maxdepth 2 -name mariadb-install-db -o -name mysql_install_db | head -n1\`" >> $WORK_INIT
  echo "VERSION=\"\`\$BIN --version | grep -E --binary-files=text -oe '[58]\.[15670]' | head -n1\`\"" >> $WORK_INIT
  echo "VERSION2=\"\`\$BIN --version | grep --binary-files=text -i 'MariaDB' | grep -oe '10\.[1-9][0-9]*' | head -n1\`\"" >> $WORK_INIT
  echo "if [ \"\$VERSION\" == \"5.7\" -o \"\$VERSION\" == \"8.0\" ]; then MID_OPTIONS='--no-defaults --initialize-insecure ${MYINIT}'; elif [ \"\$VERSION\" == \"5.6\" ]; then MID_OPTIONS='--no-defaults --force ${MYINIT}'; elif [ \"\${VERSION}\" == \"5.5\" ]; then MID_OPTIONS='--force ${MYINIT}';elif [ \"\${VERSION2}\" == \"10.1\" -o \"\${VERSION2}\" == \"10.2\" -o \"\${VERSION2}\" == \"10.3\" ]; then MID_OPTIONS='--no-defaults --force ${MYINIT}'; elif [ \"\${VERSION2}\" == \"10.4\" -o \"\${VERSION2}\" == \"10.5\" -o \"\${VERSION2}\" == \"10.6\" -o \"\${VERSION2}\" == \"10.7\" -o \"\${VERSION2}\" == \"10.8\" -o \"\${VERSION2}\" == \"10.9\" -o \"\${VERSION2}\" == \"10.10\" ]; then MID_OPTIONS='--no-defaults --force --auth-root-authentication-method=normal ${MYINIT}'; else MID_OPTIONS='${MYINIT}'; fi" >> $WORK_INIT
  if [[ ${MDG} -eq 1 ]]; then
    for i in $(seq 1 ${NR_OF_NODES}); do
      mkdir -p /dev/shm/${EPOCH}/tmp${i}
      echo "mkdir -p /dev/shm/${EPOCH}/tmp${i}" >> $WORK_INIT
      echo "\$MID \${MID_OPTIONS} --basedir=\${BASEDIR} --datadir=/dev/shm/${EPOCH}/node${i}" >> $WORK_INIT
    done
  else
    echo "if [ \"\$VERSION\" == \"5.7\" -o \"\$VERSION\" == \"8.0\" ]; then \$BIN \${MID_OPTIONS} --basedir=\${BASEDIR} --datadir=/dev/shm/${EPOCH}/data; else \$MID \${MID_OPTIONS} --basedir=\${BASEDIR} --datadir=/dev/shm/${EPOCH}/data; fi" >> $WORK_INIT
  fi
  if [ $MODE -ge 6 ]; then
    # This still needs implementation for MODE6 or higher ("else line" below simply assumes a single $WORKO atm, while MODE6 and higher has more then 1)
    echoit "[Not implemented yet] MODE6 or higher does not auto-generate a $WORK_RUN file yet"
    echo "Not implemented yet: MODE6 or higher does not auto-generate a $WORK_RUN file yet" > $WORK_RUN
    echo "#${BASEDIR}/bin/mysql -uroot -S${EPOCH_SOCKET} < INPUT_FILE_GOES_HERE (like $WORKO)" >> $WORK_RUN
    chmod +x $WORK_RUN
  else
    echo "SCRIPT_DIR=\$(cd \$(dirname \$0) && pwd)" > $WORK_RUN
    echo ". \$SCRIPT_DIR/${EPOCH}_mybase" >> $WORK_RUN
    echo "echo \"Executing testcase ./${EPOCH}.sql against mariadbd/mysqld with socket ${EPOCH_SOCKET} using the mysql CLI client...\"" >> $WORK_RUN
    if [ "$CLI_MODE" == "" ]; then CLI_MODE=99; fi  # Leads to assert below
    if [ ! -d "${WORKD}" ]; then abort; fi
    case $CLI_MODE in
      0) echo "cat ./${EPOCH}.sql | \${BASEDIR}/bin/mysql -uroot -S${EPOCH_SOCKET} --binary-mode --force test" >> $WORK_RUN ;;
      1) echo "\${BASEDIR}/bin/mysql -uroot -S${EPOCH_SOCKET} --execute=\"SOURCE ./${EPOCH}.sql;\" --force test" >> $WORK_RUN ;;  # TODO When http://bugs.mysql.com/bug.php?id=81782 is fixed, re-add --binary-mode to this command. Also note that due to http://bugs.mysql.com/bug.php?id=81784, the --force option has to be after the --execute option.
      2) echo "\${BASEDIR}/bin/mysql -uroot -S${EPOCH_SOCKET} --binary-mode --force test < ./${EPOCH}.sql" >> $WORK_RUN ;;
      *) echoit "Assert: default clause in CLI_MODE switchcase hit (in generate_run_scripts). This should not happen. CLI_MODE=${CLI_MODE}"; exit 1 ;;
    esac
    chmod +x $WORK_RUN
    if [ $USE_PQUERY -eq 1 ]; then
      cp $PQUERY_LOC $WORK_PQUERY_BIN  # Make a copy of the pquery binary for easy replay later (no need to download)
      echo "echo \"Executing testcase ./${EPOCH}.sql against mariadbd/mysqld with socket ${EPOCH_SOCKET} using pquery...\"" > $WORK_RUN_PQUERY
      echo "SCRIPT_DIR=\$(cd \$(dirname \$0) && pwd)" >> $WORK_RUN_PQUERY
      echo ". \$SCRIPT_DIR/${EPOCH}_mybase" >> $WORK_RUN_PQUERY
      echo "export LD_LIBRARY_PATH=\${BASEDIR}/lib" >> $WORK_RUN_PQUERY
      PQUERY_SHUFFLE=
      if [ $PQUERY_MULTI -eq 0 ]; then
        if [ $PQUERY_REVERSE_NOSHUFFLE_OPT -eq 0 ]; then
          PQUERY_SHUFFLE="--no-shuffle"
        else 
          echo "# RV 16/02/22: Preventing query count overrun of shuffled SQL replays. May need furher fine tuning. Ref https://jira.mariadb.org/browse/MDEV-27829" >> $WORK_RUN_PQUERY
          echo "SHUFFLE_OVERRUN_PREVENTION_MAX_LINES=\$[ \$[ \$(wc -l ./${EPOCH}.sql | awk '{print \$1}') * 13 / 10 ] + 100 ]" >> $WORK_RUN_PQUERY
          PQUERY_SHUFFLE="--queries-per-thread=\${SHUFFLE_OVERRUN_PREVENTION_MAX_LINES}"
        fi
        echo "$(echo $PQUERY_LOC | sed "s|.*/|./${EPOCH}_|") --database=test --infile=./${EPOCH}.sql $PQUERY_SHUFFLE --threads=1 --user=root --socket=${EPOCH_SOCKET} --logdir=$WORKD --log-all-queries --log-failed-queries $PQUERY_EXTRA_OPTIONS" >> $WORK_RUN_PQUERY
      else
        if [ $PQUERY_REVERSE_NOSHUFFLE_OPT -eq 1 ]; then 
          PQUERY_SHUFFLE="--no-shuffle"
        else 
          echo "# RV 16/02/22: Preventing query count overrun of shuffled SQL replays. May need furher fine tuning. Ref https://jira.mariadb.org/browse/MDEV-27829" >> $WORK_RUN_PQUERY
          echo "SHUFFLE_OVERRUN_PREVENTION_MAX_LINES=\$[ \$[ \$(wc -l ./${EPOCH}.sql | awk '{print \$1}') * 13 / 10 ] + 100 ]" >> $WORK_RUN_PQUERY
          PQUERY_SHUFFLE="--queries-per-thread=\${SHUFFLE_OVERRUN_PREVENTION_MAX_LINES}"
        fi
        # RV 09/04/22: Something may be amiss with the SHUFFLE_OVERRUN_PREVENTION_MAX_LINES code (i.e. the addition of --queries-per-thread=x in 3 places of the code), but only if true or semi-true multi-threaded reduction relies on ongoing queries to be sent to the server instance being tested, rather than a deterministic number (i.e. the ~lenght of the testcase). If so, that would mean that multi-threaded reduction no longer would function after https://github.com/mariadb-corporation/mariadb-qa/commit/9bc502e7edf2a12022e806e21839463b94f51e8c implementation. To be verified/checked. TODO
        echo "$(echo $PQUERY_LOC | sed "s|.*/|./${EPOCH}_|") --database=test --infile=./${EPOCH}.sql $PQUERY_SHUFFLE --threads=$PQUERY_MULTI_CLIENT_THREADS --queries=$PQUERY_MULTI_QUERIES --user=root --socket=${EPOCH_SOCKET} --logdir=$WORKD --log-all-queries --log-failed-queries $PQUERY_EXTRA_OPTIONS" >> $WORK_RUN_PQUERY
      fi
      chmod +x $WORK_RUN_PQUERY
    fi
  fi
  echo "SCRIPT_DIR=\$(cd \$(dirname \$0) && pwd)" > $WORK_GDB
  echo ". \$SCRIPT_DIR/${EPOCH}_mybase" >> $WORK_GDB
  BIN_TO_USE_SHORT="bin/mariadbd"
  if [ ! -r "${BASEDIR}/bin/mariadbd" ]; then BIN_TO_USE="bin/mysqld"; fi
  if [[ ${MDG} -eq 1 ]]; then
    echo "gdb \${BASEDIR}/${BIN_TO_USE_SHORT} \$(ls --color=never /dev/shm/${EPOCH}/node${GALERA_NODE}/core*)" >> $WORK_GDB
  else
    echo "gdb \${BASEDIR}/${BIN_TO_USE_SHORT} \$(ls --color=never /dev/shm/${EPOCH}/data*/core*)" >> $WORK_GDB
  fi
  echo "SCRIPT_DIR=\$(cd \$(dirname \$0) && pwd)" > $WORK_PARSE_CORE
  echo ". \$SCRIPT_DIR/${EPOCH}_mybase" >> $WORK_PARSE_CORE
  if [[ ${MDG} -eq 1 ]]; then
    echo "gdb \${BASEDIR}/${BIN_TO_USE_SHORT} \$(ls --color=never /dev/shm/${EPOCH}/node${GALERA_NODE}/core*) >/dev/null 2>&1 <<EOF" >> $WORK_PARSE_CORE
  else
    echo "gdb \${BASEDIR}/${BIN_TO_USE_SHORT} \$(ls --color=never /dev/shm/${EPOCH}/data/core*) >/dev/null 2>&1 <<EOF" >> $WORK_PARSE_CORE
  fi
  BIN_TO_USE_SHORT=
  echo -e "  set auto-load safe-path /\n  set libthread-db-search-path /usr/lib/\n  set trace-commands on\n  set pagination off\n  set print pretty on\n  set print array on\n  set print array-indexes on\n  set print elements 4096\n  set print frame-arguments all\n  set logging file ${EPOCH}_FULL.gdb\n  set logging enabled on\n  thread apply all bt full\n  set logging enabled off\n  set logging file ${EPOCH}_STD.gdb\n  set logging enabled on\n  thread apply all bt\n  set logging enabled off\n  quit\nEOF" >> $WORK_PARSE_CORE
  echo "SCRIPT_DIR=\$(cd \$(dirname \$0) && pwd)" > $WORK_STOP
  echo ". \$SCRIPT_DIR/${EPOCH}_mybase" >> $WORK_STOP
  echo "echo \"Attempting to shutdown mariadbd/mysqld with socket ${EPOCH_SOCKET}...\"" >> $WORK_STOP
  echo "MYADMIN=\`find -L \${BASEDIR} -maxdepth 2 -name mariadb-admin -type f -o -name mysqladmin -type f -o -name mysqladmin -type l \`" >> $WORK_STOP
  echo "\$MYADMIN -uroot -S${EPOCH_SOCKET} shutdown" >> $WORK_STOP
  echo "SCRIPT_DIR=\$(cd \$(dirname \$0) && pwd)" > $WORK_CL
  echo ". \$SCRIPT_DIR/${EPOCH}_mybase" >> $WORK_CL
  echo "echo \"Connecting to mariadbd/mysqld with socket -S${EPOCH_SOCKET} test using the mysql CLI client...\"" >> $WORK_CL
  if [[ ${MDG} -eq 1 ]]; then
    echo "\${BASEDIR}/bin/mysql -uroot -S${EPOCH_SOCKET} \$(ls --color=never -d /dev/shm/${EPOCH}/node1/test 2>/dev/null | grep -o 'test')" >> $WORK_CL
  else
    echo "\${BASEDIR}/bin/mysql -uroot -S${EPOCH_SOCKET} \$(ls --color=never -d /dev/shm/${EPOCH}/data/test 2>/dev/null | grep -o 'test')" >> $WORK_CL
  fi
  echo -e "To replay, the attached tarball (${EPOCH}_bug_bundle.tar.gz) gives the testcase as an exact match of our system, including some handy utilities\n" > $WORK_HOW_TO_USE
  echo "$ vi ${EPOCH}_mybase         # STEP1: Update the base path in this file (usually the only change required!). If you use a non-binary distribution, please update SOURCE_DIR location also" >> $WORK_HOW_TO_USE
  echo "$ ./${EPOCH}_init            # STEP2: Initializes the data dir" >> $WORK_HOW_TO_USE
  if [ $MODE -eq 1 -o $MODE -eq 6 ]; then
    echo "$ ./${EPOCH}_start_valgrind  # STEP3: Starts mariadbd/mysqld under Valgrind (make sure to use a Valgrind instrumented build) (note: this can easily take 20-30 seconds or more)" >> $WORK_HOW_TO_USE
  else
    echo "$ ./${EPOCH}_start           # STEP3: Starts mariadbd/mysqld" >> $WORK_HOW_TO_USE
  fi
  echo "$ ./${EPOCH}_cl              # STEP4: To check mariadbd/mysqld is up (repeat if necessary)" >> $WORK_HOW_TO_USE
  if [ $USE_PQUERY -eq 1 ]; then
    echo "$ ./${EPOCH}_run_pquery      # STEP5: Run the testcase with the pquery binary" >> $WORK_HOW_TO_USE
    echo "$ ./${EPOCH}_run             # OPTIONAL: Run the testcase with the mysql CLI (may not reproduce the issue, as the pquery binary was used for the original testcase reduction)" >> $WORK_HOW_TO_USE
    if [ $MODE -eq 1 -o $MODE -eq 6 ]; then
      echo "$ ./${EPOCH}_stop            # STEP6: Stop mariadbd/mysqld (and wait for Valgrind to write end-of-Valgrind-run details to the mariadbd/mysqld error log)" >> $WORK_HOW_TO_USE
    fi
  else
    echo "$ ./${EPOCH}_run             # STEP5: Run the testcase with the mysql CLI" >> $WORK_HOW_TO_USE
    if [ $MODE -eq 1 -o $MODE -eq 6 ]; then
      echo "$ ./${EPOCH}_stop            # STEP6: Stop mariadbd/mysqld (and wait for Valgrind to write end-of-Valgrind-run details to the mariadbd/mysqld error log)" >> $WORK_HOW_TO_USE
    fi
  fi
  if [ $MODE -eq 1 -o $MODE -eq 6 ]; then
    echo "$ vi ${EPOCH_ERROR_LOG}  # STEP7: Verify the error log" >> $WORK_HOW_TO_USE
  else
    echo "$ vi ${EPOCH_ERROR_LOG}  # STEP6: Verify the error log" >> $WORK_HOW_TO_USE
  fi
  echo "$ ./${EPOCH}_gdb             # OPTIONAL: Brings you to a gdb prompt with gdb attached to the used mariadbd/mysqld and attached to the generated core" >> $WORK_HOW_TO_USE
  echo "$ ./${EPOCH}_parse_core      # OPTIONAL: Creates ${EPOCH}_STD.gdb and ${EPOCH}_FULL.gdb; standard and full variables gdb stack traces" >> $WORK_HOW_TO_USE
  chmod +x $WORK_CL $WORK_STOP $WORK_GDB $WORK_PARSE_CORE $WORK_INIT
}

init_mysql_dir(){
  if [ ! -d "${WORKD}" ]; then abort; fi
  touch $WORKD
  if [[ $MDG -eq 1 ]] ; then
    for i in $(seq 1 ${NR_OF_NODES}); do
      sudo rm -Rf ${WORKD}/node${i}
      if [ "$MULTI_REDUCER" != "1" ]; then  # This is a parent/main reducer
        cp -a $WORKD/node${i}.init $WORKD/node${i}
      else
        mkdir ${WORKD}/node${i}
        cp -a $WORKD/../../node${i}.init/* $WORKD/node${i}/
      fi
    done
  elif [[ $GRP_RPL -eq 1 ]]; then
    sudo rm -Rf $WORKD/node1 $WORKD/node2 $WORKD/node3
    cp -a ${node1}.init ${node1}
    cp -a ${node2}.init ${node2}
    cp -a ${node3}.init ${node3}
  else
    rm -Rf $WORKD/data/* $WORKD/data_slave/* $WORKD/tmp/* $WORKD/tmp_slave/*
    rm -Rf $WORKD/data/.rocksdb
    if [ "$MULTI_REDUCER" != "1" ]; then  # This is a parent/main reducer
      cp -a $WORKD/data.init/* $WORKD/data/
      if [ "${REPLICATION}" -eq 1 ]; then
        cp -a ${WORKD}/data.init/* ${WORKD}/data_slave/
      fi
    else
      cp -a $WORKD/../../data.init/* $WORKD/data/
      if [ "${REPLICATION}" -eq 1 ]; then
        cp -a ${WORKD}/../../data.init/* ${WORKD}/data_slave/
      fi
    fi
  fi
  if [ $REDUCE_GLIBC_OR_SS_CRASHES -gt 0 ]; then
    echo "" > /tmp/reducer_typescript${TYPESCRIPT_UNIQUE_FILESUFFIX}.log
  fi
}

start_mysqld_or_valgrind_or_mdg(){
  init_mysql_dir
  if [ ! -d "${WORKD}" ]; then abort; fi
  touch $WORKD
  if [ $MDG -eq 1 ]; then
    start_mdg_main
  elif [ $GRP_RPL -eq 1 ]; then
    gr_start_main
  else
    # Pre-start cleanup
    if [ -f $WORKD/log/master.err ]; then mv -f $WORKD/log/master.err $WORKD/log/master.err.prev; fi  # mariadbd/mysqld error log (single server or master)
    if [ -f $WORKD/log/slave.err ]; then mv -f $WORKD/log/slave.err $WORKD/log/slave.err.prev; fi  # mariadbd/mysqld error log (slave)
    if [ -f $WORKD/log/mysqld.out ]; then mv -f $WORKD/log/mysqld.out $WORKD/mysqld.prev; fi  # mariadbd/mysqld stdout & stderr output, as well as some mariadb-admin/mysqladmin output (single server or master)
    if [ -f $WORKD/log/mysqld_slave.out ]; then mv -f $WORKD/log/mysqld_slave.out $WORKD/mysqld.prev; fi  # mariadbd/mysqld stdout & stderr output, as well as some mariadb-admin/mysqladmin output (slave)
    if [ -f $WORKD/log/mysql.out ]; then mv -f $WORKD/log/mysql.out $WORKD/mysql.prev; fi  # mysql client output (only applicable to single server or master)
    if [ -f $WORKD/log/default.node.tld_thread-0.out ]; then mv -f $WORKD/log/default.node.tld_thread-0.out $WORKD/log/default.node.tld_thread-0.prev; fi  # pquery client output
    if [ -f $WORKD/default.node.tld_thread-0.sql ]; then mv -f $WORKD/default.node.tld_thread-0.sql $WORKD/log/default.node.tld_thread-0.prevsql; fi
    # Start
    FAILURE_RETURN_CODE=
    if [ $MODE -ne 1 -a $MODE -ne 6 ]; then
      start_mysqld_main
      if [ "${?}" == "3" ]; then
        FAILURE_RETURN_CODE=3
      fi
    else
      start_valgrind_mysqld_main
      if [ "${?}" == "3" ]; then
        FAILURE_RETURN_CODE=3
      fi
    fi
    if [ ${REDUCE_STARTUP_ISSUES} -le 0 ]; then
      ADMIN_BIN_TO_USE="${BASEDIR}/bin/mariadb-admin"
      if [ ! -r "${ADMIN_BIN_TO_USE}" ]; then ADMIN_BIN_TO_USE="${BASEDIR}/bin/mysqladmin"; fi
      if ! ${ADMIN_BIN_TO_USE} -uroot -S$WORKD/socket.sock ping > /dev/null 2>&1; then
        if [ ${STAGE} -eq 8 -o ${STAGE} -eq 9 ]; then
          if [ ${STAGE} -eq 8 ]; then STAGE8_NOT_STARTED_CORRECTLY=1; fi
          if [ ${STAGE} -eq 9 ]; then STAGE9_NOT_STARTED_CORRECTLY=1; fi
          echoit "$ATLEASTONCE [Stage $STAGE] [Note] Assuming this option set is required as the server did not start"  # Do not use 'Failed to start the.*server' text here to avoid that being detected as a subreducer failure (for future use, as subreducers currently do not run STAGE8)
        else
          if [ "${FAILURE_RETURN_CODE}" == "3" ]; then  # Replication startup failure
            # There is no need to show the warning below here, as the code in start_mysqld_main already issues a similar warning when replication startup fail
            FAILURE_RETURN_CODE=
            return 3  # Return a replication-specific failure code (3)
          else
            echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [Warning] Failed to start the mariadbd/mysqld server, retrying by restarting the server. Possible reasons: overloaded server, OOS. If this message appears a few times, it is fine. If it is persistantly looping, it indicates a persistant problem that may require manual intervention. Logs: $WORKD/log/mysqld.out, $WORKD/log/*.err and $WORKD/init.log. Last good known testcase: $WORKO (provided the disk being used did not run out of space)"
            return 1  # Return a general startup failure
          fi 
        fi
      else
        # Ref discussion RV/RS 27 Nov 19 via 1:1 (RV;should be covered in SQL,RS;issue seen)
        # RV update 24-08-2020: Added back in to provision for using test db always in CLI/pquery startup
        CLIENT_BIN_TO_USE="${BASEDIR}/bin/mariadb"
        if [ ! -r "${CLIENT_BIN_TO_USE}" ]; then CLIENT_BIN_TO_USE="${BASEDIR}/bin/mysql"; fi
        ${CLIENT_BIN_TO_USE} -uroot -S$WORKD/socket.sock -e "create database if not exists test" > /dev/null 2>&1
        CLIENT_BIN_TO_USE=
      fi
      ADMIN_BIN_TO_USE=
    fi
  fi
  STARTUPCOUNT=$[$STARTUPCOUNT+1]
}

start_mdg_main(){
  if [ ! -d "${WORKD}" ]; then abort; fi
  touch $WORKD
  generate_run_scripts
  #clean existing processes
  (ps -def | grep -E 'n*.cnf' | grep $EPOCH | awk '{print $2}' | xargs -I{} kill -9 {} >/dev/null 2>&1; ) >/dev/null 2>&1
  sleep 2; sync
  SUSER=root
  SPASS=
  # Creating default my.cnf file
  rm -rf ${WORKD}/my.cnf
  echo "[mysqld]" > ${WORKD}/my.cnf
  echo "basedir=${BASEDIR}" >> ${WORKD}/my.cnf
  echo "innodb_file_per_table" >> ${WORKD}/my.cnf
  echo "innodb_autoinc_lock_mode=2" >> ${WORKD}/my.cnf
  echo "wsrep-provider=${BASEDIR}/lib/libgalera_smm.so" >> ${WORKD}/my.cnf
  echo "wsrep_sst_method=rsync" >> ${WORKD}/my.cnf
  echo "wsrep_sst_auth=$SUSER:$SPASS" >> ${WORKD}/my.cnf
  echo "binlog_format=ROW" >> ${WORKD}/my.cnf
  echo "core-file" >> ${WORKD}/my.cnf
  echo "log-output=none" >> ${WORKD}/my.cnf
  echo "wsrep_slave_threads=12" >> ${WORKD}/my.cnf
  echo "wsrep_on=1" >> ${WORKD}/my.cnf
  # TODO: Add encryption checks after implementing encryption functionalities in pquery-run.sh
  if [[ "$ENCRYPTION_RUN" == 1 ]]; then
    echo "encrypt_binlog=1" >> ${WORKD}/my.cnf
    echo "plugin_load_add=file_key_management" >> ${WORKD}/my.cnf
    echo "file_key_management_filename=${SCRIPT_PWD}/pquery/galera_encryption.key" >> ${WORKD}/my.cnf
    echo "file_key_management_encryption_algorithm=aes_cbc" >> ${WORKD}/my.cnf
    echo "innodb_encrypt_tables=ON" >> ${WORKD}/my.cnf
    echo "innodb_encryption_rotate_key_age=0" >> ${WORKD}/my.cnf
    echo "innodb_encrypt_log=ON" >> ${WORKD}/my.cnf
    echo "innodb_encryption_threads=4" >> ${WORKD}/my.cnf
    echo "innodb_encrypt_temporary_tables=ON" >> ${WORKD}/my.cnf
    echo "encrypt_tmp_disk_tables=1" >> ${WORKD}/my.cnf
    echo "encrypt_tmp_files=1" >> ${WORKD}/my.cnf
    echo "aria_encrypt_tables=ON" >> ${WORKD}/my.cnf
  fi
#  if [[ "$ENCRYPTION_RUN" == 1 ]]; then
#    echo "encrypt_binlog=ON" >> ${WORKD}/my.cnf
#    if [[ $WITH_KEYRING_VAULT -ne 1 ]]; then
#      echo "early-plugin-load=keyring_file.so" >> ${WORKD}/my.cnf
#      echo "keyring_file_data=keyring" >> ${WORKD}/my.cnf
#    fi
#  fi

  mdg_node_startup_status() {
    # ensure that node has started and has joined the group post SST
    ERROR_LOG=$1
    for X in $(seq 0 120); do
      sleep 1
      touch ${WORKD}  # Ensure that watchdog scripts like ~/ds do not think this directory no-longer-in-use
      if grep -E --binary-files=text -qi "Synchronized with group, ready for connections" $ERROR_LOG ; then
        break
      fi
      if [[ $X -eq 119 ]]; then
        echo "Error! server not started.. Terminating!"
        grep -E --binary-files=text -i "ERROR|ASSERTION" $ERROR_LOG
        echo "Terminating now."
        exit 1
      fi
    done
  }

  ADDR="127.0.0.1"
  rm -rf $WORKD/tmp*
  unset MDG_PORTS
  unset MDG_LADDRS
  MDG_PORTS=
  MDG_LADDRS=
  for i in $(seq 1 ${NR_OF_NODES}); do
    node=${WORKD}/node${i}
    mkdir -p $WORKD/tmp${i}
    init_empty_port
    RBASE=$NEWPORT
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
    cp ${WORKD}/my.cnf ${WORKD}/n${i}.cnf
    sed -i "2i server-id=10${i}" ${WORKD}/n${i}.cnf
    sed -i "2i wsrep_node_incoming_address=$ADDR" ${WORKD}/n${i}.cnf
    sed -i "2i wsrep_node_address=$ADDR" ${WORKD}/n${i}.cnf
    sed -i "2i wsrep_sst_receive_address=$SST_PORT" ${WORKD}/n${i}.cnf
    sed -i "2i log-error=$node/$node.err" ${WORKD}/n${i}.cnf
    sed -i "2i port=$RBASE" ${WORKD}/n${i}.cnf
    sed -i "2i datadir=$node" ${WORKD}/n${i}.cnf
    sed -i "2i socket=$node/node${i}_socket.sock" ${WORKD}/n${i}.cnf
    sed -i "2i tmpdir=$WORKD/tmp${i}" ${WORKD}/n${i}.cnf
    sed -i "2i wsrep_provider_options=\"gmcast.listen_addr=tcp://$LADDR;ist.recv_addr=$IST_PORT;$WSREP_PROVIDER_OPTIONS\"" ${WORKD}/n${i}.cnf
    # TODO: Add encryption checks after implementing encryption functionalities in pquery-run.sh
#    if [[ "$ENCRYPTION_RUN" != 1 ]]; then
#      sed -i "2i wsrep_provider_options=\"gmcast.listen_addr=tcp://$LADDR;$WSREP_PROVIDER_OPTIONS\"" ${WORKD}/n${i}.cnf
#    else
#      sed -i "2i wsrep_provider_options=\"gmcast.listen_addr=tcp://$LADDR;$WSREP_PROVIDER_OPTIONS;socket.ssl_key=${WORKD}/cert/server-key.pem;socket.ssl_cert=${WORKD}/cert/server-cert.pem;socket.ssl_ca=${WORKD}/cert/ca.pem\"" ${WORKD}/n${i}.cnf
#      echo "ssl-ca = ${WORKD}/cert/ca.pem" >> ${WORKD}/n${i}.cnf
#      echo "ssl-cert = ${WORKD}/cert/server-cert.pem" >> ${WORKD}/n${i}.cnf
#      echo "ssl-key = ${WORKD}/cert/server-key.pem" >> ${WORKD}/n${i}.cnf
#      echo "[client]" >> ${WORKD}/n${i}.cnf
#      echo "ssl-ca = ${WORKD}/cert/ca.pem" >> ${WORKD}/n${i}.cnf
#      echo "ssl-cert = ${WORKD}/cert/client-cert.pem" >> ${WORKD}/n${i}.cnf
#      echo "ssl-key = ${WORKD}/cert/client-key.pem" >> ${WORKD}/n${i}.cnf
#      echo "[sst]" >> ${WORKD}/n${i}.cnf
#      echo "encrypt = 4" >> ${WORKD}/n${i}.cnf
#      echo "ssl-ca = ${WORKD}/cert/ca.pem" >> ${WORKD}/n${i}.cnf
#      echo "ssl-cert = ${WORKD}/cert/server-cert.pem" >> ${WORKD}/n${i}.cnf
#      echo "ssl-key = ${WORKD}/cert/server-key.pem" >> ${WORKD}/n${i}.cnf
#    fi
  done

  echo "SCRIPT_DIR=\$(cd \$(dirname \$0) && pwd)" > $WORK_START
  echo ". \$SCRIPT_DIR/${EPOCH}_mybase" >> $WORK_START
  echo "BIN=\`find -L \${BASEDIR} -maxdepth 2 -name mariadbd -type f -o -name mysqld -type f -o -name mysqld-debug -type f -name mysqld -type l -o -name mysqld-debug -type l | head -1\`;if [ -z "\$BIN" ]; then echo \"Assert! mysqld binary '\$BIN' could not be read\";exit 1;fi" >> $WORK_START
  WSREP_CLUSTER_ADDRESS=$(printf "%s,"  "${MDG_LADDRS[@]}")
  if [[ ${RR_TRACING} -eq 1 ]]; then
    export _RR_TRACE_DIR="${WORKD}/rr"
    mkdir -p "${_RR_TRACE_DIR}"
  fi
  for j in $(seq 1 ${NR_OF_NODES}); do
    sed -i "2i wsrep_cluster_address=gcomm://${WSREP_CLUSTER_ADDRESS:1}" ${WORKD}/n${j}.cnf
    cp ${WORKD}/n${j}.cnf ${WORK_BUG_DIR}/${EPOCH}_n${j}.cnf
    if [ ${j} -eq 1 ]; then
      echo "echo \"Attempting to start Galera Cluster...\"" >> $WORK_START
      echo "${RR_OPTIONS} ${TIMEOUT_COMMAND} \$BIN --defaults-file=\$SCRIPT_DIR/${EPOCH}_n${j}.cnf $SPECIAL_MYEXTRA_OPTIONS $MYEXTRA --wsrep-new-cluster > $WORKD/node${j}/mysqld.out 2>&1 &" | sed 's/ \+/ /g' >> $WORK_START
      echo "sleep 10" >> $WORK_START
      BIN_TO_USE="${BASEDIR}/bin/mariadbd"
      if [ ! -r "${BIN_TO_USE}" ]; then BIN_TO_USE="${BASEDIR}/bin/mysqld"; fi
      ${RR_OPTIONS} ${BIN_TO_USE} --defaults-file=${WORKD}/n${j}.cnf $MYEXTRA --wsrep-new-cluster > ${WORKD}/node${j}/node${j}.err 2>&1 &
      BIN_TO_USE=
      mdg_node_startup_status ${WORKD}/node${j}/node${j}.err
    else
      echo "${TIMEOUT_COMMAND} \$BIN --defaults-file=\$SCRIPT_DIR/${EPOCH}_n${j}.cnf $SPECIAL_MYEXTRA_OPTIONS $MYEXTRA > $WORKD/node${j}/mysqld.out 2>&1 &" | sed 's/ \+/ /g' >> $WORK_START
      echo "sleep 60" >> $WORK_START
      BIN_TO_USE="${BASEDIR}/bin/mariadbd"
      if [ ! -r "${BIN_TO_USE}" ]; then BIN_TO_USE="${BASEDIR}/bin/mysqld"; fi
      ${BIN_TO_USE} --defaults-file=${WORKD}/n${j}.cnf $MYEXTRA > ${WORKD}/node${j}/node${j}.err 2>&1 &
      BIN_TO_USE=
      mdg_node_startup_status ${WORKD}/node${j}/node${j}.err
    fi
  done

  sed -i "s|$WORKD|/dev/shm/${EPOCH}|g" $WORK_START
  chmod +x $WORK_START
  # create test to run pquery command
  ${BASEDIR}/bin/mysql -uroot -S${WORKD}/node1/node1_socket.sock -e "create database if not exists test" > /dev/null 2>&1
}

gr_start_main(){
  if [ ! -d "${WORKD}" ]; then abort; fi
  touch $WORKD
  ADDR="127.0.0.1"
  init_empty_port
  RBASE1=$NEWPORT
  NEWPORT=
  init_empty_port
  RBASE2=$NEWPORT
  NEWPORT=
  init_empty_port
  RBASE3=$NEWPORT
  NEWPORT=
  init_empty_port
  LPORT1=$NEWPORT
  NEWPORT=
  init_empty_port
  LPORT2=$NEWPORT
  NEWPORT=
  init_empty_port
  LPORT3=$NEWPORT
  NEWPORT=
  LADDR1="$ADDR:${LPORT1}"
  LADDR2="$ADDR:${LPORT2}"
  LADDR3="$ADDR:${LPORT3}"

  gr_startup_chk(){
    ERROR_LOG=$1
    if grep -E --binary-files=text -qi "ERROR. Aborting" $ERROR_LOG ; then
      if grep -E --binary-files=text -qi "TCP.IP port.*Address already in use" $ERROR_LOG ; then
        echo "Assert! The text '[ERROR] Aborting' was found in the error log due to a IP port conflict (the port was already in use)"
      else
        echo "Assert! '[ERROR] Aborting' was found in the error log. This is likely an issue with one of the \$MYEXTRA (${MYEXTRA}) startup options. Saving trial for further analysis, and dumping error log here for quick analysis. Please check the output against these variables settings."
        grep -E --binary-files=text "ERROR" $ERROR_LOG
        exit 1
      fi
    fi
  }

  BIN_TO_USE="${BASEDIR}/bin/mariadbd"
  if [ ! -r "${BIN_TO_USE}" ]; then BIN_TO_USE="${BASEDIR}/bin/mysqld"; fi
  ${BIN_TO_USE} --no-defaults \
    --basedir=${BASEDIR} --datadir=$node1 \
    --innodb_file_per_table $MYEXTRA --innodb_autoinc_lock_mode=2 --innodb_locks_unsafe_for_binlog=1 \
    --server_id=1 --gtid_mode=ON --enforce_gtid_consistency=ON \
    --master_info_repository=TABLE --relay_log_info_repository=TABLE \
    --binlog_checksum=NONE --log_slave_updates=ON --log_bin=binlog \
    --binlog_format=ROW --innodb_flush_method=O_DIRECT \
    --core-file --sql-mode=no_engine_substitution \
    --loose-innodb --secure-file-priv= --loose-innodb-status-file=1 \
    --log-error=$node1/error.log \
    --socket=$node1/node1_socket.sock --log-output=none \
    --port=$RBASE1 --transaction_write_set_extraction=XXHASH64 \
    --loose-group_replication_group_name="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" \
    --loose-group_replication_start_on_boot=off --loose-group_replication_local_address="$LADDR1" \
    --loose-group_replication_group_seeds="$LADDR1,$LADDR2,$LADDR3" \
    --loose-group_replication_bootstrap_group=off --super_read_only=OFF > $node1/node1.err 2>&1 &
  BIN_TO_USE=

  ADMIN_BIN_TO_USE="${BASEDIR}/bin/mariadb-admin"
  if [ ! -r "${ADMIN_BIN_TO_USE}" ]; then ADMIN_BIN_TO_USE="${BASEDIR}/bin/mysqladmin"; fi
  for X in $(seq 0 200); do
    sleep 1
    if ${ADMIN_BIN_TO_USE} -uroot -S$node1/node1_socket.sock ping > /dev/null 2>&1; then
      sleep 2
      CLIENT_BIN_TO_USE="${BASEDIR}/bin/mariadb"
      if [ ! -r "${CLIENT_BIN_TO_USE}" ]; then CLIENT_BIN_TO_USE="${BASEDIR}/bin/mysql"; fi
      ${CLIENT_BIN_TO_USE} -uroot -S$node1/node1_socket.sock -Bse "create database if not exists test" > /dev/null 2>&1
      ${CLIENT_BIN_TO_USE} -uroot -S$node1/node1_socket.sock -Bse "SET SQL_LOG_BIN=0;CREATE USER rpl_user@'%';GRANT REPLICATION SLAVE ON *.* TO rpl_user@'%' IDENTIFIED BY 'rpl_pass';FLUSH PRIVILEGES;SET SQL_LOG_BIN=1;" > /dev/null 2>&1
      ${CLIENT_BIN_TO_USE} -uroot -S$node1/node1_socket.sock -Bse "CHANGE MASTER TO MASTER_USER='rpl_user', MASTER_PASSWORD='rpl_pass' FOR CHANNEL 'group_replication_recovery';" > /dev/null 2>&1
      ${CLIENT_BIN_TO_USE} -uroot -S$node1/node1_socket.sock -Bse "INSTALL PLUGIN group_replication SONAME 'group_replication.so';SET GLOBAL group_replication_bootstrap_group=ON;START GROUP_REPLICATION;SET GLOBAL group_replication_bootstrap_group=OFF;" > /dev/null 2>&1
      CLIENT_BIN_TO_USE=
      break
    fi
    gr_startup_chk $node1/node1.err
  done
  ADMIN_BIN_TO_USE=

  BIN_TO_USE="${BASEDIR}/bin/mariadbd"
  if [ ! -r "${BIN_TO_USE}" ]; then BIN_TO_USE="${BASEDIR}/bin/mysqld"; fi
  ${BIN_TO_USE} --no-defaults \
    --basedir=${BASEDIR} --datadir=$node2 \
    --innodb_file_per_table $MYEXTRA --innodb_autoinc_lock_mode=2 --innodb_locks_unsafe_for_binlog=1 \
    --server_id=1 --gtid_mode=ON --enforce_gtid_consistency=ON \
    --master_info_repository=TABLE --relay_log_info_repository=TABLE \
    --binlog_checksum=NONE --log_slave_updates=ON --log_bin=binlog \
    --binlog_format=ROW --innodb_flush_method=O_DIRECT \
    --core-file --sql-mode=no_engine_substitution \
    --loose-innodb --secure-file-priv= --loose-innodb-status-file=1 \
    --log-error=$node2/error.log \
    --socket=$node2/node2_socket.sock --log-output=none \
    --port=$RBASE2 --transaction_write_set_extraction=XXHASH64 \
    --loose-group_replication_group_name="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" \
    --loose-group_replication_start_on_boot=off --loose-group_replication_local_address="$LADDR2" \
    --loose-group_replication_group_seeds="$LADDR1,$LADDR2,$LADDR3" \
    --loose-group_replication_bootstrap_group=off --super_read_only=OFF > $node2/node2.err 2>&1 &
  BIN_TO_USE=

  ADMIN_BIN_TO_USE="${BASEDIR}/bin/mariadb-admin"
  if [ ! -r "${ADMIN_BIN_TO_USE}" ]; then ADMIN_BIN_TO_USE="${BASEDIR}/bin/mysqladmin"; fi
  for X in $(seq 0 200); do
    sleep 1
    if ${ADMIN_BIN_TO_USE} -uroot -S$node2/node2_socket.sock ping > /dev/null 2>&1; then
      sleep 2
      CLIENT_BIN_TO_USE="${BASEDIR}/bin/mariadb"
      if [ ! -r "${CLIENT_BIN_TO_USE}" ]; then CLIENT_BIN_TO_USE="${BASEDIR}/bin/mysql"; fi
      ${CLIENT_BIN_TO_USE} -uroot -S$node2/node2_socket.sock -Bse "SET SQL_LOG_BIN=0;CREATE USER rpl_user@'%';GRANT REPLICATION SLAVE ON *.* TO rpl_user@'%' IDENTIFIED BY 'rpl_pass';FLUSH PRIVILEGES;SET SQL_LOG_BIN=1;" > /dev/null 2>&1
      ${CLIENT_BIN_TO_USE} -uroot -S$node2/node2_socket.sock -Bse "CHANGE MASTER TO MASTER_USER='rpl_user', MASTER_PASSWORD='rpl_pass' FOR CHANNEL 'group_replication_recovery';" > /dev/null 2>&1
      ${CLIENT_BIN_TO_USE} -uroot -S$node2/node2_socket.sock -Bse "INSTALL PLUGIN group_replication SONAME 'group_replication.so';START GROUP_REPLICATION;" > /dev/null 2>&1
      CLIENT_BIN_TO_USE=
      break
    fi
    gr_startup_chk $node2/node2.err
  done
  ADMIN_BIN_TO_USE=

  BIN_TO_USE="${BASEDIR}/bin/mariadbd"
  if [ ! -r "${BIN_TO_USE}" ]; then BIN_TO_USE="${BASEDIR}/bin/mysqld"; fi
  ${BIN_TO_USE} --no-defaults \
    --basedir=${BASEDIR} --datadir=$node3 \
    --innodb_file_per_table $MYEXTRA --innodb_autoinc_lock_mode=2 --innodb_locks_unsafe_for_binlog=1 \
    --server_id=1 --gtid_mode=ON --enforce_gtid_consistency=ON \
    --master_info_repository=TABLE --relay_log_info_repository=TABLE \
    --binlog_checksum=NONE --log_slave_updates=ON --log_bin=binlog \
    --binlog_format=ROW --innodb_flush_method=O_DIRECT \
    --core-file --sql-mode=no_engine_substitution \
    --loose-innodb --secure-file-priv= --loose-innodb-status-file=1 \
    --log-error=$node3/error.log \
    --socket=$node3/node3_socket.sock --log-output=none \
    --port=$RBASE3 --transaction_write_set_extraction=XXHASH64 \
    --loose-group_replication_group_name="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" \
    --loose-group_replication_start_on_boot=off --loose-group_replication_local_address="$LADDR3" \
    --loose-group_replication_group_seeds="$LADDR1,$LADDR2,$LADDR3" \
    --loose-group_replication_bootstrap_group=off --super_read_only=OFF > $node3/node3.err 2>&1 &
  BIN_TO_USE=

  ADMIN_BIN_TO_USE="${BASEDIR}/bin/mariadb-admin"
  if [ ! -r "${ADMIN_BIN_TO_USE}" ]; then ADMIN_BIN_TO_USE="${BASEDIR}/bin/mysqladmin"; fi
  for X in $(seq 0 200); do
    sleep 1
    if ${ADMIN_BIN_TO_USE} -uroot -S$node3/node3_socket.sock ping > /dev/null 2>&1; then
      sleep 2
      CLIENT_BIN_TO_USE="${BASEDIR}/bin/mariadb"
      if [ ! -r "${CLIENT_BIN_TO_USE}" ]; then CLIENT_BIN_TO_USE="${BASEDIR}/bin/mysql"; fi
      ${CLIENT_BIN_TO_USE} -uroot -S$node3/node3_socket.sock -Bse "SET SQL_LOG_BIN=0;CREATE USER rpl_user@'%';GRANT REPLICATION SLAVE ON *.* TO rpl_user@'%' IDENTIFIED BY 'rpl_pass';FLUSH PRIVILEGES;SET SQL_LOG_BIN=1;" > /dev/null 2>&1
      ${CLIENT_BIN_TO_USE} -uroot -S$node3/node3_socket.sock -Bse "CHANGE MASTER TO MASTER_USER='rpl_user', MASTER_PASSWORD='rpl_pass' FOR CHANNEL 'group_replication_recovery';" > /dev/null 2>&1
      ${CLIENT_BIN_TO_USE} -uroot -S$node3/node3_socket.sock -Bse "INSTALL PLUGIN group_replication SONAME 'group_replication.so';START GROUP_REPLICATION;" > /dev/null 2>&1
      CLIENT_BIN_TO_USE=
      break
    fi
    gr_startup_chk $node3/node3.err
  done
  ADMIN_BIN_TO_USE=
}

start_mysqld_main(){
  if [ ! -d "${WORKD}" ]; then abort; fi
  touch $WORKD
  if [ "$(du -sc $WORKD/data | grep -v 'total' | awk '{print $1}')" == "0" ]; then
    echoit "$ATLEASTONCE [Stage $STAGE] [ERROR] data directory at $WORKD/data is 0 bytes. The volume likely ran out of space"
    echo "Terminating now."
    exit 1
  fi
  echo "SCRIPT_DIR=\$(cd \$(dirname \$0) && pwd)" > $WORK_START
  echo ". \$SCRIPT_DIR/${EPOCH}_mybase" >> $WORK_START
  echo "echo \"Attempting to start mariadbd/mysqld (socket /dev/shm/${EPOCH}/socket.sock)...\"" >> $WORK_START
  #echo $JE1 >> $WORK_START; echo $JE2 >> $WORK_START; echo $JE3 >> $WORK_START; echo $JE4 >> $WORK_START;echo $JE5 >> $WORK_START
  echo $JE1 >> $WORK_START; echo $JE2 >> $WORK_START; echo $JE3 >> $WORK_START; echo $JE4 >> $WORK_START
  echo "BIN=\`find -L \${BASEDIR} -maxdepth 2 -name mariadbd -type f -o -name mysqld -type f -o -name mysqld-debug -type f -name mysqld -type l -o -name mysqld-debug -type l | head -1\`;if [ -z "\$BIN" ]; then echo \"Assert! mariadbd/mysqld binary '\$BIN' could not be read\";exit 1;fi" >> $WORK_START
  SCHEDULER_OR_NOT=
  if [ $ENABLE_QUERYTIMEOUT -gt 0 ]; then SCHEDULER_OR_NOT="--event-scheduler=ON "; fi
  CORE_FOR_NEW_TEXT_STRING=
  if [ $USE_NEW_TEXT_STRING -gt 0 ]; then CORE_FOR_NEW_TEXT_STRING="--core-file --core"; fi
  if [[ ${RR_TRACING} -eq 1 ]]; then
    export _RR_TRACE_DIR="${WORKD}/rr"
    mkdir -p "${_RR_TRACE_DIR}"
  fi
  # Change --port=$MYPORT to --skip-networking instead once BUG#13917335 is fixed and remove all MYPORT coding. Update: this can no longer be done even if that bug is fixed, as replication uses MYPORT. TODO: remove this comment once it was pushed once for history
  if [ $MODE -ge 6 -a $TS_DEBUG_SYNC_REQUIRED_FLAG -eq 1 ]; then
    if [ "${REPLICATION}" -eq 1 ]; then
      echoit "MODE=6, TS_DEBUG_SYNC_REQUIRED_FLAG=1. This combination does not support replication mode yet (REPLICATION=1). Please disable either MODE 6, TS_DEBUG_SYNC_REQUIRED_FLAG, or REPLICATION or extend the code"
      exit 1
    fi
    init_empty_port; MYPORT=$NEWPORT; NEWPORT=  # Obtain new empty port
    echo "${RR_OPTIONS} ${TIMEOUT_COMMAND} \$BIN --no-defaults --basedir=\${BASEDIR} --datadir=$WORKD/data --tmpdir=$WORKD/tmp --port=$MYPORT --pid-file=$WORKD/pid.pid --socket=$WORKD/socket.sock --loose-debug-sync-timeout=$TS_DS_TIMEOUT $SPECIAL_MYEXTRA_OPTIONS $MYEXTRA --log-error=$WORKD/log/master.err ${SCHEDULER_OR_NOT} > $WORKD/log/mysqld.out 2>&1 &" | sed 's/ \+/ /g' >> $WORK_START
    CMD="${RR_OPTIONS} ${TIMEOUT_COMMAND} ${BIN} --no-defaults --basedir=$BASEDIR --datadir=$WORKD/data --tmpdir=$WORKD/tmp --port=$MYPORT --pid-file=$WORKD/pid.pid --socket=$WORKD/socket.sock --loose-debug-sync-timeout=$TS_DS_TIMEOUT --user=$MYUSER $SPECIAL_MYEXTRA_OPTIONS $MYEXTRA --log-error=$WORKD/log/master.err ${SCHEDULER_OR_NOT} ${CORE_FOR_NEW_TEXT_STRING}"
    MYSQLD_START_TIME=$(date +'%s')
    $CMD > $WORKD/log/mysqld.out 2>&1 &
    PIDV="$!"
  else
    if [ "${REPLICATION}" -eq 1 ]; then
      # ---- Master
      init_empty_port; MYPORT=$NEWPORT; NEWPORT=  # Obtain new empty port
      echo "${RR_OPTIONS} ${TIMEOUT_COMMAND} \$BIN --no-defaults --basedir=\${BASEDIR} --datadir=$WORKD/data --tmpdir=$WORKD/tmp --port=$MYPORT --pid-file=$WORKD/pid.pid --socket=$WORKD/socket.sock $SPECIAL_MYEXTRA_OPTIONS $MYEXTRA $REPL_EXTRA $MASTER_EXTRA --log-error=$WORKD/log/master.err ${SCHEDULER_OR_NOT} > $WORKD/log/mysqld.out 2>&1 &" | sed 's/ \+/ /g' >> $WORK_START
      CMD="${RR_OPTIONS} ${TIMEOUT_COMMAND} ${BIN} --no-defaults --basedir=$BASEDIR --datadir=$WORKD/data --tmpdir=$WORKD/tmp --port=$MYPORT --pid-file=$WORKD/pid.pid --socket=$WORKD/socket.sock --user=$MYUSER $SPECIAL_MYEXTRA_OPTIONS $MYEXTRA $REPL_EXTRA $MASTER_EXTRA --log-error=$WORKD/log/master.err ${SCHEDULER_OR_NOT} ${CORE_FOR_NEW_TEXT_STRING}"
      MYSQLD_START_TIME=$(date +'%s')
      $CMD > $WORKD/log/mysqld.out 2>&1 &
      PIDV="$!"
      # ---- Slave
      init_empty_port; MYPORT_SLAVE=$NEWPORT; NEWPORT=  # Obtain new empty port
      echo "${RR_OPTIONS} ${TIMEOUT_COMMAND} \$BIN --no-defaults --basedir=\${BASEDIR} --datadir=$WORKD/data_slave --tmpdir=$WORKD/tmp_slave --port=$MYPORT_SLAVE --pid-file=$WORKD/slave_pid.pid --socket=$WORKD/slave_socket.sock $SPECIAL_MYEXTRA_OPTIONS $MYEXTRA $REPL_EXTRA $SLAVE_EXTRA --log-error=$WORKD/log/slave.err ${SCHEDULER_OR_NOT} > $WORKD/log/mysqld.out 2>&1 &" | sed 's/ \+/ /g' >> $WORK_START
      CMD="${RR_OPTIONS} ${TIMEOUT_COMMAND} ${BIN} --no-defaults --basedir=$BASEDIR --datadir=$WORKD/data_slave --tmpdir=$WORKD/tmp_slave --port=$MYPORT_SLAVE --pid-file=$WORKD/slave_pid.pid --socket=$WORKD/slave_socket.sock --user=$MYUSER $SPECIAL_MYEXTRA_OPTIONS $MYEXTRA $REPL_EXTRA $SLAVE_EXTRA --log-error=$WORKD/log/slave.err ${SCHEDULER_OR_NOT} ${CORE_FOR_NEW_TEXT_STRING}"
      MYSQLD_SLAVE_START_TIME=$(date +'%s')
      $CMD > $WORKD/log/mysqld_slave.out 2>&1 &
      PIDV_SLAVE="$!"
      # ---- Init replication
      # Ensure both servers are live
      MASTER_STARTUP_OK=0; SLAVE_STARTUP_OK=0
      ADMIN_BIN_TO_USE="${BASEDIR}/bin/mariadb-admin"
      if [ ! -r "${ADMIN_BIN_TO_USE}" ]; then ADMIN_BIN_TO_USE="${BASEDIR}/bin/mysqladmin"; fi
      for((delay=0;delay<75;delay++)); do  # 75 Second max master+slave startup (normally, only ~2 seconds are required, though on very busy servers it can take >60 seconds)
        sleep 1
        touch ${WORKD}  # Ensure that watchdog scripts like ~/ds do not think this directory is no longer in use
        touch ${WORKD}/reducer.log  # Idem
        if ${ADMIN_BIN_TO_USE} -uroot -S$WORKD/socket.sock ping > /dev/null 2>&1; then MASTER_STARTUP_OK=1; fi
        if ${ADMIN_BIN_TO_USE} -uroot -S$WORKD/slave_socket.sock ping > /dev/null 2>&1; then SLAVE_STARTUP_OK=1; fi
        if [ "${MASTER_STARTUP_OK}" -eq 1 -a "${SLAVE_STARTUP_OK}" -eq 1 ]; then break; fi
      done
      ADMIN_BIN_TO_USE=
      if [ "${MASTER_STARTUP_OK}" -ne 1 -o "${SLAVE_STARTUP_OK}" -ne 1 ]; then
        if [ ! -d "${WORKD}" ]; then abort; fi
        echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [Warning] MASTER_STARTUP_OK=${MASTER_STARTUP_OK}, SLAVE_STARTUP_OK=${SLAVE_STARTUP_OK}: not both 1, retrying by restarting both. Possible reasons: overloaded server, OOS. If this message appears a few times, it is fine. If it is persistantly looping, it indicates a persistant problem that may require manual intervention. Logs: $WORKD/log/mysqld.out, $WORKD/log/*.err and $WORKD/init.log. Last good known testcase: $WORKO (provided the disk being used did not run out of space)"
        PIDV=;PIDV_SLAVE=;MYSQLD_START_TIME=;MYSQLD_SLAVE_START_TIME=;MASTER_STARTUP_OK=;SLAVE_STARTUP_OK=;MYPORT=;
        if [ ! -z "${TRIAL}" ]; then
          if [ "${TRIAL}" -gt 1 ]; then
            TRIAL=$[ ${TRIAL} - 1 ]  # Repeat the trial
          fi
        fi
        return 3  # A mariadbd/mysqld startup issue happened: run_and_check() on receiving this 'return 3' special return code will return a '0', indicating that this trial did not reproduce the issue (hack; could use more permanent solution) TODO
      fi
      MASTER_STARTUP_OK=; SLAVE_STARTUP_OK=
      R_CLIENT_BIN_TO_USE="mysql"
      if [ -x ${BASEDIR}/bin/mariadb ]; then R_CLIENT_BIN_TO_USE="mariadb"; fi
      # Setup replication, master side
      ${BASEDIR}/bin/${R_CLIENT_BIN_TO_USE} -uroot -S$WORKD/socket.sock -e "DELETE FROM mysql.user WHERE user='';" 2>/dev/null
      ${BASEDIR}/bin/${R_CLIENT_BIN_TO_USE} -uroot -S$WORKD/socket.sock -e "GRANT REPLICATION SLAVE ON *.* TO 'repl_user'@'%' IDENTIFIED BY 'repl_pass'; FLUSH PRIVILEGES;" 2>/dev/null
      # Setup replication, slave side
      ${BASEDIR}/bin/${R_CLIENT_BIN_TO_USE} -uroot -S$WORKD/slave_socket.sock -e "CHANGE MASTER TO MASTER_HOST='127.0.0.1', MASTER_PORT=${MYPORT}, MASTER_USER='repl_user', MASTER_PASSWORD='repl_pass', MASTER_USE_GTID=slave_pos ; START SLAVE;" 2>/dev/null
      IO_AND_SQL_THREADS_RUNNING_COUNT=0
      for((delay=0;delay<25;delay++)); do  # Give replication up to 25 seconds to come up
        IO_AND_SQL_THREADS_RUNNING_COUNT="$(${BASEDIR}/bin/${R_CLIENT_BIN_TO_USE} -uroot -S$WORKD/slave_socket.sock -e 'SHOW SLAVE STATUS\G' | grep -o 'Slave_[SQLIO]\+_Running:.*' | grep ': Yes' | wc -l)"
        if [ "${IO_AND_SQL_THREADS_RUNNING_COUNT}" == "2" ]; then
          break
        fi
        sleep 1
      done
      if [ "${IO_AND_SQL_THREADS_RUNNING_COUNT}" != "2" ]; then
        EXTRA_SLAVE_DEBUG_OUTPUT="$(${BASEDIR}/bin/${R_CLIENT_BIN_TO_USE} -uroot -S$WORKD/slave_socket.sock -e 'SHOW SLAVE STATUS\G' | grep -o 'Slave_[SQLIO]\+_Running:.*' | grep ': Yes' | tr '\n' ' ' | sed 's| $||g')"
        echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [Warning] The IO and/or SQL threads failed to both start on the slave: ${EXTRA_SLAVE_DEBUG_OUTPUT}, retrying by restarting both. If this message appears a few times, it is fine. If it is persistantly looping, it indicates a persistant problem that may require manual intervention. Logs: $WORKD/log/mysqld.out, $WORKD/log/*.err and $WORKD/init.log. Last good known testcase: $WORKO (provided the disk being used did not run out of space)"
        PIDV=;PIDV_SLAVE=;MYSQLD_START_TIME=;MYSQLD_SLAVE_START_TIME=;MASTER_STARTUP_OK=;SLAVE_STARTUP_OK=;MYPORT=;IO_AND_SQL_THREADS_RUNNING_COUNT=;
        if [ ! -z "${TRIAL}" ]; then
          if [ "${TRIAL}" -gt 1 ]; then
            TRIAL=$[ ${TRIAL} - 1 ]  # Repeat the trial
          fi
        fi
        return 3  # A mariadbd/mysqld startup issue happened: run_and_check() on receiving this 'return 3' special return code will return a '0', indicating that this trial did not reproduce the issue (hack; could use more permanent solution) TODO
      fi
      R_CLIENT_BIN_TO_USE=
      IO_AND_SQL_THREADS_RUNNING_COUNT=
      echoit "[Info] Replication enabled between master and slave in ${WORKD} using port ${MYPORT}"
    else
      init_empty_port; MYPORT=$NEWPORT; NEWPORT=  # Obtain new empty port
      echo "${RR_OPTIONS} ${TIMEOUT_COMMAND} \$BIN --no-defaults --basedir=\${BASEDIR} --datadir=$WORKD/data --tmpdir=$WORKD/tmp --port=$MYPORT --pid-file=$WORKD/pid.pid --socket=$WORKD/socket.sock $SPECIAL_MYEXTRA_OPTIONS $MYEXTRA --log-error=$WORKD/log/master.err ${SCHEDULER_OR_NOT} > $WORKD/log/mysqld.out 2>&1 &" | sed 's/ \+/ /g' >> $WORK_START
      CMD="${RR_OPTIONS} ${TIMEOUT_COMMAND} ${BIN} --no-defaults --basedir=$BASEDIR --datadir=$WORKD/data --tmpdir=$WORKD/tmp --port=$MYPORT --pid-file=$WORKD/pid.pid --socket=$WORKD/socket.sock --user=$MYUSER $SPECIAL_MYEXTRA_OPTIONS $MYEXTRA --log-error=$WORKD/log/master.err ${SCHEDULER_OR_NOT} ${CORE_FOR_NEW_TEXT_STRING}"
      MYSQLD_START_TIME=$(date +'%s')
      $CMD > $WORKD/log/mysqld.out 2>&1 &
      PIDV="$!"
    fi
  fi
  sed -i "s|$WORKD|/dev/shm/${EPOCH}|g" $WORK_START
  # TODO: the next line used to contain only --core-file, but this led to MariaDB not always properly dumping a core file. Added --core to fix, but this may not be fully backward compatible, nor backward compatible forever. Also research why the --core is needed to start with (using 10.5.5 for this)
  sed -i "s|pid.pid|pid.pid --core-file --core|" $WORK_START
  # RV 04/05/17: The following sed line is causing issues with RocksDB, like this;
  # --plugin-load-add=RocksDB=ha_rocksdb.so\;rocksdb_cfstats=ha_rocksdb.so;rocks...
  # The adding of a \ (and especially a single one?!) does not make any sense atm, but there was highly like a historical reason
  # Disabling it for the moment. If any issues are seen, it can be reverted
  # sed -i "s|\.so\;|\.so\\\;|" $WORK_START
  chmod +x $WORK_START
  ADMIN_BIN_TO_USE="${BASEDIR}/bin/mariadb-admin"
  if [ ! -r "${ADMIN_BIN_TO_USE}" ]; then ADMIN_BIN_TO_USE="${BASEDIR}/bin/mysqladmin"; fi
  for X in $(seq 1 120); do
    sleep 1
    if ${ADMIN_BIN_TO_USE} -uroot -S$WORKD/socket.sock ping > /dev/null 2>&1; then break; fi
    # Check if the server crashed or shutdown, then there is no need to wait any longer (new beta feature as of 1 July 16)
    # RV fix made 10 Jan 17; if no log/master.err is created (for whatever reason) then 120x4 'not found' messages scroll on the screen: added '2>/dev/null'. The Reason for the missing log/master.err files in some circumstances needs to be found (seems to be related to bad startup options (usually in stage 8), but why is there no output at all?)
    if grep -E --binary-files=text -qi "identify the cause of the crash" $WORKD/log/*.err 2>/dev/null; then break; fi
    if grep -E --binary-files=text -qi "Writing a core file" $WORKD/log/*.err 2>/dev/null; then break; fi
    if grep -E --binary-files=text -qi "Core pattern" $WORKD/log/*.err 2>/dev/null; then break; fi
    if grep -E --binary-files=text -qi "terribly wrong" $WORKD/log/*.err 2>/dev/null; then break; fi
    if grep -E --binary-files=text -qi "Shutdown complete" $WORKD/log/*.err 2>/dev/null; then break; fi
  done
  ADMIN_BIN_TO_USE=
}

start_valgrind_mysqld_main(){
  if [ ! -d "${WORKD}" ]; then abort; fi
  touch $WORKD
  if [ "$(du -sc $WORKD/data | grep -v 'total' | awk '{print $1}')" == "0" ]; then
    echoit "$ATLEASTONCE [Stage $STAGE] [ERROR] data directory at $WORKD/data is 0 bytes. The volume likely ran out of space"
    echo "Terminating now."
    exit 1
  fi
  if [ -f $WORKD/valgrind.out ]; then mv -f $WORKD/valgrind.out $WORKD/valgrind.prev; fi
  SCHEDULER_OR_NOT=
  if [ $ENABLE_QUERYTIMEOUT -gt 0 ]; then SCHEDULER_OR_NOT="--event-scheduler=ON "; fi
  init_empty_port; MYPORT=$NEWPORT; NEWPORT=  # Obtain new empty port 
  CMD="${TIMEOUT_COMMAND} valgrind --suppressions=$BASEDIR/mysql-test/valgrind.supp --num-callers=40 --show-reachable=yes ${BIN} --basedir=${BASEDIR} --datadir=$WORKD/data --port=$MYPORT --tmpdir=$WORKD/tmp --pid-file=$WORKD/pid.pid --socket=$WORKD/socket.sock --user=$MYUSER $SPECIAL_MYEXTRA_OPTIONS $MYEXTRA --log-error=$WORKD/log/master.err ${SCHEDULER_OR_NOT}" # Workaround for BUG#12939557 (when old Valgrind version is used): --innodb_checksum_algorithm=none
  MYSQLD_START_TIME=$(date +'%s')
  $CMD > $WORKD/valgrind.out 2>&1 &
  PIDV="$!"; STARTUPCOUNT=$[$STARTUPCOUNT+1]
  echo "SCRIPT_DIR=\$(cd \$(dirname \$0) && pwd)" > $WORK_START_VALGRIND
  echo ". \$SCRIPT_DIR/${EPOCH}_mybase" >> $WORK_START_VALGRIND
  echo "echo \"Attempting to start mariadbd/mysqld under Valgrind (socket /dev/shm/${EPOCH}/socket.sock)...\"" >> $WORK_START_VALGRIND
  echo $JE1 >> $WORK_START_VALGRIND; echo $JE2 >> $WORK_START_VALGRIND; echo $JE3 >> $WORK_START_VALGRIND
  #echo $JE4 >> $WORK_START_VALGRIND; echo $JE5 >> $WORK_START_VALGRIND
  echo $JE4 >> $WORK_START_VALGRIND
  echo "BIN=\`find -L \${BASEDIR} -maxdepth 2 -name mariadbd -type f -o -name mysqld -type f -o -name mysqld-debug -type f -o -name mysqld -type l -o -name mysqld-debug -type l | head -1\`;if [ -z "\$BIN" ]; then echo \"Assert! mariadbd/mysqld binary '\$BIN' could not be read\";exit 1;fi" >> $WORK_START_VALGRIND
  echo "valgrind --suppressions=\${BASEDIR}/mysql-test/valgrind.supp --num-callers=40 --show-reachable=yes \$BIN --no-defaults --basedir=\${BASEDIR} --datadir=$WORKD/data --port=$MYPORT --tmpdir=$WORKD/tmp --pid-file=$WORKD/pid.pid --log-error=$WORKD/log/master.err --socket=$WORKD/socket.sock $SPECIAL_MYEXTRA_OPTIONS $MYEXTRA ${SCHEDULER_OR_NOT}>>$WORKD/log/master.err 2>&1 &" | sed 's/ \+/ /g' >> $WORK_START_VALGRIND
  sed -i "s|$WORKD|/dev/shm/${EPOCH}|g" $WORK_START_VALGRIND
  sed -i "s|pid.pid|pid.pid --core-file --core|" $WORK_START_VALGRIND
  sed -i "s|\.so\;|\.so\\\;|" $WORK_START_VALGRIND
  chmod +x $WORK_START_VALGRIND
  ADMIN_BIN_TO_USE="${BASEDIR}/bin/mariadb-admin"
  if [ ! -r "${ADMIN_BIN_TO_USE}" ]; then ADMIN_BIN_TO_USE="${BASEDIR}/bin/mysqladmin"; fi
  for X in $(seq 1 360); do
    sleep 1
    if ${ADMIN_BIN_TO_USE} -uroot -S$WORKD/socket.sock ping > /dev/null 2>&1; then
      break
    fi
  done
  if ! ${ADMIN_BIN_TO_USE} -uroot -S$WORKD/socket.sock ping > /dev/null 2>&1; then
    if [ "$MULTI_REDUCER" != "1" ]; then  # This is the main reducer. No point in displaying this for subreducers, as the said files will already have been replaced
      echoit "$ATLEASTONCE [Stage $STAGE] [ERROR] Failed to start the mariadbd/mysqld server under Valgrind, check $WORKD/log/mysqld.out, $WORKD/log/*.err, $WORKD/init.log and maybe $WORKD/data/error.log. Also check that there is plenty of space on the device being used"  # Do not change the text '[ERROR] Failed to start the mariadbd/mysqld server' without updating it everwhere else in this script, including the place where reducer checks whether subreducers having run into this error.
    fi
    echo "Terminating now."
    exit 1
  fi
  ADMIN_BIN_TO_USE=
}

determine_chunk(){
  if [ $NOISSUEFLOW -lt 0 ]; then NOISSUEFLOW=0; fi
  # Slow down chunk size scaling (both for CHUNK reductions and increases) by not modifying the chunk for SLOW_DOWN_CHUNK_SCALING_NR loops of determine_chunk() i.e. trials
  if [ $SLOW_DOWN_CHUNK_SCALING -gt 0 ]; then
    CHUNK_LOOPS_DONE=$[CHUNK_LOOPS_DONE+1]
    if [ $CHUNK_LOOPS_DONE -le $SLOW_DOWN_CHUNK_SCALING_NR ]; then  # Need to ensure we can exit determine_chunk() early (have had enough _NR rounds/loops)
      if [ $CHUNK_LOOPS_DONE -lt 99999999999 ]; then  # Need to ensure that this is not the very first loop (where first CHUNK determination) (see set_internal_options())
        if [ $CHUNK -lt $LINECOUNTF ]; then  # Need to ensure that CHUNK is less then the filesize (to avoid wiping the whole testcase away)
          if [ $NOISSUEFLOW -gt 0 ]; then  # Need to ensure we haven't just seen the issue (in which case new CHUNK determination is best)
            if [ $CHUNK -gt 0 ]; then  # Need to ensure we do not have a negative CHUNK size
              return;  # Exit determine_chunk() early to do another loop with the same pre-established CHUNK size (i.e. SLOW_DOWN_CHUNK_SCALING in action)
            fi
          fi
        fi
      fi
    fi
  fi
  CHUNK_LOOPS_DONE=1
  if [ $LINECOUNTF -ge 1000 ]; then
    if [ $NOISSUEFLOW -ge 20 ]; then CHUNK=0
    elif [ $NOISSUEFLOW -ge 18 ]; then CHUNK=$[$LINECOUNTF/500]
    elif [ $NOISSUEFLOW -ge 15 ]; then CHUNK=$[$LINECOUNTF/200]
    elif [ $NOISSUEFLOW -ge 14 ]; then CHUNK=$[$LINECOUNTF/100]    # 1%
    elif [ $NOISSUEFLOW -ge 12 ]; then CHUNK=$[$LINECOUNTF/50]     # 2%
    elif [ $NOISSUEFLOW -ge 10 ]; then CHUNK=$[$LINECOUNTF/25]     # 4%
    elif [ $NOISSUEFLOW -ge  8 ]; then CHUNK=$[$LINECOUNTF/12]     # 8%
    elif [ $NOISSUEFLOW -ge  6 ]; then CHUNK=$[$LINECOUNTF/8]      # 12%
    elif [ $NOISSUEFLOW -ge  5 ]; then CHUNK=$[$LINECOUNTF/6]      # 16%
    elif [ $NOISSUEFLOW -ge  4 ]; then CHUNK=$[$LINECOUNTF/4]      # 25%
    elif [ $NOISSUEFLOW -ge  3 ]; then CHUNK=$[$LINECOUNTF/3]      # 33%
    elif [ $NOISSUEFLOW -ge  2 ]; then CHUNK=$[$LINECOUNTF/2]      # 50%
    elif [ $NOISSUEFLOW -ge  1 ]; then CHUNK=$[$LINECOUNTF*65/100] # 65%
    else CHUNK=$[$LINECOUNTF*80/100]                               # 80% delete
    fi
  else
    if   [ $NOISSUEFLOW -ge 15 ]; then CHUNK=0
    elif [ $NOISSUEFLOW -ge 14 ]; then CHUNK=$[$LINECOUNTF/500]
    elif [ $NOISSUEFLOW -ge 12 ]; then CHUNK=$[$LINECOUNTF/200]
    elif [ $NOISSUEFLOW -ge 10 ]; then CHUNK=$[$LINECOUNTF/100]
    elif [ $NOISSUEFLOW -ge  8 ]; then CHUNK=$[$LINECOUNTF/75]
    elif [ $NOISSUEFLOW -ge  6 ]; then CHUNK=$[$LINECOUNTF/50]
    elif [ $NOISSUEFLOW -ge  5 ]; then CHUNK=$[$LINECOUNTF/40]
    elif [ $NOISSUEFLOW -ge  4 ]; then CHUNK=$[$LINECOUNTF/30]     # 3%
    elif [ $NOISSUEFLOW -ge  3 ]; then CHUNK=$[$LINECOUNTF/20]     # 5%
    elif [ $NOISSUEFLOW -ge  2 ]; then CHUNK=$[$LINECOUNTF/10]     # 10%
    elif [ $NOISSUEFLOW -ge  1 ]; then CHUNK=$[$LINECOUNTF/6]      # 16%
    else CHUNK=$[$LINECOUNTF/4]                                    # 25% delete
    fi
  fi
  # For issues which are sporadic, gradually reducing the CHUNK is ok, as long as reduction is done much slower (reducer should not end up with single
  # line removals per trial too quickly since this leads to very slow testcase reduction. So, a smarter algorithm can be used here based on the remaining
  # testcase size and a much slower/much less important $NOISSUEFLOW input ($NOISSUEFLOW 1/100th % input; if 50 no-issue-runs then reduce chunk by 50%)
  # The flow is different in subreducer: when an issue is found, all subreducers are terminated & restarted (with a new filesize and fresh/new chunksize)
  if [ $SPORADIC -eq 1 ]; then
    if   [ $LINECOUNTF -ge 10000 ]; then CHUNK=$[$LINECOUNTF/6];   # 16%
    elif [ $LINECOUNTF -ge 5000  ]; then CHUNK=$[$LINECOUNTF/7];   # 14%
    elif [ $LINECOUNTF -ge 2000  ]; then CHUNK=$[$LINECOUNTF/8];   # 12%
    elif [ $LINECOUNTF -ge 1000  ]; then CHUNK=$[$LINECOUNTF/9];   # 11%
    elif [ $LINECOUNTF -ge 500   ]; then CHUNK=$[$LINECOUNTF/10];  # 10%
    elif [ $LINECOUNTF -ge 200   ]; then CHUNK=$[$LINECOUNTF/12];  # 8%
    elif [ $LINECOUNTF -ge 100   ]; then CHUNK=$[$LINECOUNTF/15];  # 7%
    fi  # If $LINECOUNTF < 100 then the normal CHUNK size calculation above is fine.

    if [ $LINECOUNTF -ge 100 ]; then
      if [ $NOISSUEFLOW -lt 100 ]; then
        # Make chunk size (very) gradually smaller based on seeing issues or not
        CHUNK=$[($CHUNK*(((100*100)-($NOISSUEFLOW*100))/100))/100]  # As explained above. 100ths are used due to int limitation
      else
        CHUNK=$[$CHUNK/100]  # 1% of original chunk size
      fi
    fi
  fi
  # Protection against negative CHUNK size
  if [ $CHUNK -lt 0 ]; then CHUNK=0; fi  # CHUNK=0 is one line at the time
}

control_backtrack_flow(){
  if   [ $NOISSUEFLOW -ge 100 ]; then NOISSUEFLOW=$[$NOISSUEFLOW-60]
  elif [ $NOISSUEFLOW -ge  70 ]; then NOISSUEFLOW=$[$NOISSUEFLOW-40]
  elif [ $NOISSUEFLOW -ge  40 ]; then NOISSUEFLOW=$[$NOISSUEFLOW-20]
  elif [ $NOISSUEFLOW -ge  20 ]; then NOISSUEFLOW=$[$NOISSUEFLOW-8]
  elif [ $NOISSUEFLOW -ge  10 ]; then NOISSUEFLOW=$[$NOISSUEFLOW-3]
  elif [ $NOISSUEFLOW -ge   1 ]; then NOISSUEFLOW=$[$NOISSUEFLOW-1]
  fi
}

cut_random_chunk(){
  RANDLINE=-1  # Dummy start
  RLLOOPCOUNT=0
  if [ "${PQUERY_CONS_Q_FAIL}" -eq 0 ]; then  # Regular runs 
    #RANDLINE=$[ ( $RANDOM % ( $[ $LINECOUNTF - $CHUNK - 1 ] + 1 ) ) + 1 ]  # Old
    while [ "${RANDLINE}" -le 0 ]; do
      RANDLINE=$[ $RANDOM % ($[ $LINECOUNTF - $CHUNK ] + 1 ) ]  # New
      # Inf loop protection (can be removed in time if this assert never triggers)
      RLLOOPCOUNT=$[ ${RLLOOPCOUNT} + 1 ]
      if [ "${RLLOOPCOUNT}" -ge 1000 ]; then
        echo "Assert: RLLOOPCOUNT -ge 1000! Fix this"
        echo "Debug: RANDLINE: ${RANDLINE} | LINECOUNTF: ${LINECOUNTF} | CHUNK: ${CHUNK}"
        exit 1
      fi
    done
  else  # Special PQUERY_CONS_Q_FAIL chuncking algo which avoids using the last n (250 ftm) lines as those are required to trigger the 'Last [0-9]+ consecutive queries all failed' output in the pquery log (pquery.out).
    if [ $LINECOUNTF -eq 251 ]; then  # TODO: This code does not belong here, instead other areas of reducer need to become smarter about PQUERY_CONS_Q_FAIL handling with/given the required 250 lines at the end of the testcase
      echo "Assert: optimal testcase for PQUERY_CONS_Q_FAIL (251 queries) already achieved: nothing left todo"
      echo "Testcase: $WORKF"
      exit 1
    fi
    RANDLINEMIN250=$[ $LINECOUNTF - $CHUNK - 250 ]  # Ref explanation below
    while [ "${RANDLINEMIN250}" -lt 1 ]; do  # When getting close/closer to 250 lines, it is possible that the CHUNK is too large, vary CHUNK size  # TODO: this could be part of determine_chunk, i.e. if PQUERY_CONS_Q_FAIL=1 then reduce CHUNK by 250? etc
#251 lines left   251
      CHUNK=$[ $RANDOM % $[ $LINECOUNTF - 250 ] ]  # For example, 251 lines left: 251-250=1 and RANDOM%1 is 0 max, and CHUNK=0 means one line removal. Similarly 252 left: 252-250=2, RANDOM%2 is 1 max and CHUNK=1 (+1 in sed) is two lines removed
      RANDLINEMIN250=$[ $LINECOUNTF - $CHUNK - 250 ]  # For example, 251 lines left: 251-0-250=1 and line=1 is the only possible starting line in that case. Similarly 252 left: 252-1(max)-250=1 or 252-0(min)-250=2 and lines 1 and 2 are two viable options as the startline (RANDLINE, calculated below)
    done
    while [ "${RANDLINE}" -le 0 ]; do
      RANDLINE=$[ $RANDOM % ( ${RANDLINEMIN250} + 1 ) ]  # +1: RANDOM%nr requires nr to be nr+1 to be able to reach (max) nr, and we want to have line 1 or higher for the sed
      # Inf loop protection (can be removed in time if this assert never triggers)
      RLLOOPCOUNT=$[ ${RLLOOPCOUNT} + 1 ]
      if [ "${RLLOOPCOUNT}" -ge 1000 ]; then
        echo "Assert: RLLOOPCOUNT -ge 1000! Fix this"
        echo "Debug: RANDLINE: ${RANDLINE} | LINECOUNTF: ${LINECOUNTF} | CHUNK: ${CHUNK}"
        exit 1
      fi
    done
    RANDLINEMIN250=
  fi
  if [ $CHUNK -eq 0 -a $TRIAL -gt 5 ]; then STUCKTRIAL=$[ $STUCKTRIAL + 1 ]; fi
  if [ $CHUNK -eq 0 -a $STUCKTRIAL -gt 5 ]; then
    echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] Now filtering line $RANDLINE (Current chunk size: stuck at 1)"
    sed -n "$RANDLINE ! p" $WORKF > $WORKT  # Note that ,+$CHUNK i.e. ,+0 would have the same outcome
  else
    ENDLINE=$[$RANDLINE+$CHUNK]
    REALCHUNK=$[$CHUNK+1]
    if [ $SPORADIC -eq 1 -a $LINECOUNTF -lt 100 ]; then
      echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] Now filtering line(s) $RANDLINE to $ENDLINE (Current chunk size: $REALCHUNK: Sporadic issue; using a fixed % based chunk)"
    else
      echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] Now filtering line(s) $RANDLINE to $ENDLINE (Current chunk size: $REALCHUNK)"
    fi
    sed -n "$RANDLINE,+$CHUNK ! p" $WORKF > $WORKT  # RANDLINE: starting line (line 1=1), CHUNK: number of lines (1 line=+0)
  fi
}

cut_fireworks_chunk_and_shuffle(){
  echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [FIREWORKS] Chunking, shuffling and executing ${FIREWORKS_LINES} lines"  # The 'executing' is a bit premature (as it happens a bit later outside of this procedure), but the text makes sense here
  RANDOM=$(date +%s%N | cut -b10-19 | sed 's|^[0]\+||')  # Resetting random entropy to ensure highest quality entropy
  shuf -n${FIREWORKS_LINES} --random-source=/dev/urandom ${INPUTFILE} > ${WORKT}
}

cut_threadsync_chunk(){
  if [ $TS_TRXS_SETS -gt 0 ]; then
    echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] Now filtering out last $TS_TRXS_SETS command sets"
  fi
  for t in $(eval echo {1..$TS_THREADS}); do
    export TS_WORKF=$(eval echo $(echo '$WORKF'"$t"))
    export TS_WORKT=$(eval echo $(echo '$WORKT'"$t"))
    if [ $TS_TRXS_SETS -gt 0 ]; then
      FIRST_DS_OCCURRENCE=$(tac $TS_WORKF | grep -E --binary-files=text -v "^[\t ]*;[\t ]*$" | grep -E --binary-files=text -m1 -n "SET DEBUG_SYNC" | awk -F":" '{print $1}');
      if grep -E --binary-files=text -qi "SIGNAL GO_T2" $TS_WORKF; then
        # Control thread
        LAST_LINE=$( \
        if [ $FIRST_DS_OCCURRENCE -gt 1 ]; then \
          tac $TS_WORKF | awk '/now SIGNAL GO_T2/,/SET DEBUG_SYNC/ {print NR; i++; if (i>$TS_TRXS_SETS) nextfile}' | tail -n1; \
        else \
          tac $TS_WORKF | awk '/now SIGNAL GO_T2/,/SET DEBUG_SYNC/ {print NR; i++; if (i>1+$TS_TRXS_SETS) nextfile}' | tail -n1; \
        fi)
        if [ $TS_VARIABILITY_SLEEP -gt 0 ]; then
          tail -n$LAST_LINE $TS_WORKF | grep -E --binary-files=text -v "^[\t ]*;[\t ]*$" | \
            sed "s/SET DEBUG_SYNC\(.*\)now SIGNAL GO_T2/SELECT SLEEP($TS_VARIABILITY_SLEEP);SET DEBUG_SYNC\1now SIGNAL GO_T2/" > $TS_WORKT
        else
          tail -n$LAST_LINE $TS_WORKF | grep -E --binary-files=text -v "^[\t ]*;[\t ]*$" > $TS_WORKT
        fi
      else
        # Sub threads
        LAST_LINE=$( \
        if [ $FIRST_DS_OCCURRENCE -gt 1 ]; then \
          tac $TS_WORKF | awk '/now WAIT_FOR GO_T/,/SET DEBUG_SYNC/ {print NR; i++; if (i>$TS_TRXS_SETS) nextfile}' | tail -n1; \
        else \
          tac $TS_WORKF | awk '/now WAIT_FOR GO_T/,/SET DEBUG_SYNC/ {print NR; i++; if (i>1+$TS_TRXS_SETS) nextfile}' | tail -n1; \
        fi)
        if [ $TS_VARIABILITY_SLEEP -gt 0 ]; then
          TS_VARIABILITY_SLEEP_TENTH=$(echo "$TS_VARIABILITY_SLEEP / 10" | bc -l)
          tail -n$LAST_LINE $TS_WORKF | grep -E --binary-files=text -v "^[\t ]*;[\t ]*$" | \
            sed "s/SET DEBUG_SYNC/SELECT SLEEP($TS_VARIABILITY_SLEEP_TENTH);SET DEBUG_SYNC/" > $TS_WORKT
        else
          tail -n$LAST_LINE $TS_WORKF | grep -E --binary-files=text -v "^[\t ]*;[\t ]*$" > $TS_WORKT
        fi
      fi
    else
      cat $TS_WORKF > $TS_WORKT
    fi
  done
}

run_and_check(){
  start_mysqld_or_valgrind_or_mdg
  if [ ${?} -eq 3 ]; then stop_mysqld_or_mdg; return 0; fi  # Provision for various startup failures. The hack is to return 0 here, indicating that no reduction was succesful
  if [ ${?} -eq 1 ]; then stop_mysqld_or_mdg; echo 'RETURN CODE WAS 1'; return 0; fi  # Is this correct?
  run_sql_code
  if [ $MODE -eq 0 -o $MODE -eq 1 -o $MODE -eq 6 ]; then stop_mysqld_or_mdg; fi
  process_outcome
  OUTCOME="$?"
  if [ $MODE -ne 0 -a $MODE -ne 1 -a $MODE -ne 6 ]; then stop_mysqld_or_mdg; fi
  # Add error log from this trial to the overall run error log
  if [[ $MDG -eq 1 ]] ; then
    for i in $(seq 1 "${NR_OF_NODES}"); do
      cat $WORKD/node${i}/node${i}.err >> $WORKD/node${i}_error.log
    done
  elif [[ $GRP_RPL -eq 1 ]]; then
    sudo cat $WORKD/node1/error.log >> $WORKD/node1_error.log
    sudo cat $WORKD/node2/error.log >> $WORKD/node2_error.log
    sudo cat $WORKD/node3/error.log >> $WORKD/node3_error.log
  else
    cat $WORKD/log/master.err >> $WORKD/error.log
    rm -f $WORKD/log/master.err
    if [ -r $WORKD/log/slave.err ]; then
      cat $WORKD/log/slave.err >> $WORKD/error_slave.log
      rm -f $WORKD/log/slave.err
    fi
  fi
  return $OUTCOME
}

run_sql_code(){
  if [ $ENABLE_QUERYTIMEOUT -gt 0 ]; then
    # Setting up query timeouts using the MySQL Event Scheduler
    # Place event into the mysql db, not test db as the test db is dropped immediately
    SOCKET_TO_BE_USED=
    if [[ $MDG -eq 1 || $GRP_RPL -eq 1 ]]; then
      SOCKET_TO_BE_USED=${node1}/node1_socket.sock
    else
      SOCKET_TO_BE_USED=$WORKD/socket.sock
    fi
    $BASEDIR/bin/mysql -uroot -S${SOCKET_TO_BE_USED} --force mysql -e"
      DELIMITER ||
      CREATE EVENT querytimeout ON SCHEDULE EVERY 20 SECOND DO BEGIN
      SET @id:='';
      SET @id:=(SELECT id FROM INFORMATION_SCHEMA.PROCESSLIST WHERE ID<>CONNECTION_ID() AND STATE<>'killed' AND TIME>$QUERYTIMEOUT ORDER BY TIME DESC LIMIT 1);
      IF @id > 1 THEN KILL QUERY @id; END IF;
      END ||
      DELIMITER ;
    "
  fi
  #DEBUG
  #read -p "Go! (run_sql_code break)"
  if [ $MODE -ge 6 ]; then
    echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [DATA] Loading datafile before SQL threads replay"
    # Note that the two following grep -v solutions still work fine for DROPC removal as this is using the mysql cli which can handle multiple statements on one line and DROPC is NOT being changed into a multi-line statement. Search for 'DROPC' to learn more.
    if [ $TS_DBG_CLI_OUTPUT -eq 0 ]; then
      echo "$(echo "$DROPC";cat $TS_DATAINPUTFILE | grep -E --binary-files=text -v "$DROPC")" | $BASEDIR/bin/mysql -uroot -S$WORKD/socket.sock --force test > /dev/null 2>/dev/null
    else
      echo "$(echo "$DROPC";cat $TS_DATAINPUTFILE | grep -E --binary-files=text -v "$DROPC")" | $BASEDIR/bin/mysql -uroot -S$WORKD/socket.sock --force -vvv test > $WORKD/mysql_data.out 2>&1
    fi
    TXT_OUT="$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [SQL] Forking SQL threads [PIDs]:"
    for t in $(eval echo {1..$TS_THREADS}); do
      # Forking background threads by using bash fork implementation $() &
      export TS_WORKT=$(eval echo $(echo '$WORKT'"$t"))
      if [ $TS_DBG_CLI_OUTPUT -eq 0 ]; then
        $(cat $TS_WORKT | $BASEDIR/bin/mysql -uroot -S$WORKD/socket.sock --force test > /dev/null 2>/dev/null  ) &
      else
        $(cat $TS_WORKT | $BASEDIR/bin/mysql -uroot -S$WORKD/socket.sock --force -vvv test > $WORKD/mysql$t.out 2>&1 ) &
      fi
      PID=$!
      export TS_THREAD_PID$t=$PID
      TXT_OUT="$TXT_OUT #$t [$!]"
    done
    echoit "$TXT_OUT"
    # Wait for forked processes to terminate
    echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [SQL] Waiting for all forked SQL threads to finish/terminate"
    TXT_OUT="$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [SQL] Finished/Terminated SQL threads:"
    for t in $(eval echo {$TS_THREADS..1}); do  # Reverse: later threads are likely to finish earlier
      wait $(eval echo $(echo '$TS_THREAD_PID'"$t"))
      TXT_OUT="$TXT_OUT #$t"
      echoit_overwrite "$TXT_OUT"
      if [ $t -eq 20 -a $TS_THREADS -gt 20 ]; then
        echoit "$TXT_OUT"
        TXT_OUT="$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] Finished/Terminated subreducer threads:"
      fi
    done
    echoit "$TXT_OUT"
    echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [SQL] All SQL threads have finished/terminated"
  elif [ $MODE -eq 5 ]; then
    if [[ $MDG -eq 1 || $GRP_RPL -eq 1 ]]; then
      cat $WORKT | $BASEDIR/bin/mysql -uroot -S${node1}/node1_socket.sock -vvv --force test > $WORKD/log/mysql.out 2>&1
    else
      cat $WORKT | $BASEDIR/bin/mysql -uroot -S$WORKD/socket.sock -vvv --force test > $WORKD/log/mysql.out 2>&1
    fi
  else
    # Some general information on MODE=2 replay using either the mysql CLI or pquery: When using the mysql cli, a single or double quote in and by itself
    # (without a terminating one on the same line) will cause the query to be seen as multi-line. With pquery this is not the case because it is an API/C
    # driven per-query executor. If a query fails (one per line), that query alone will fail, not subsequent ones - which would fail in the mysql CLI client
    # because of such an "incorrect opening of a multi-line statement". Hence, the reproducibility of a testcase using another replay tool (pquery testcase
    # being replayed with mysql CLI or vice versa) may differ. Another difference is that the pquery replay output looks significantly different from the
    # client replay output. Thus, any TEXT="..." strings need to be matched to the specific output seen in the original trial's pquery or mysql CLI output.
    if [ $USE_PQUERY -eq 1 ]; then
      export LD_LIBRARY_PATH=${BASEDIR}/lib
      if [ -r $WORKD/pquery.out ]; then
        mv $WORKD/pquery.out $WORKD/pquery.prev
      fi
      USE_PQUERYE2_CLIENT_LOGGING=
      if [ $MODE -eq 2 ]; then
        USE_PQUERYE2_CLIENT_LOGGING="--log-all-queries --log-failed-queries"
      fi
      if [[ $MDG -eq 1 || $GRP_RPL -eq 1 ]]; then
        PQUERY_SHUFFLE=
        if [ $PQUERY_MULTI -eq 0 ]; then
          if [ $PQUERY_REVERSE_NOSHUFFLE_OPT -ge 0 ]; then 
            PQUERY_SHUFFLE="--no-shuffle"
          else
            # RV 16/02/22: Preventing query count overrun of shuffled SQL replays. May need furher fine tuning. Ref https://jira.mariadb.org/browse/MDEV-27829
            PQUERY_SHUFFLE="--queries-per-thread=$[ $[ $(wc -l ${WORKT} | awk '{print $1}') * 13 / 10 ] + 100 ]"
          fi
          $PQUERY_LOC --database=test --infile=$WORKT $PQUERY_SHUFFLE --threads=1 $USE_PQUERYE2_CLIENT_LOGGING --user=root --socket=${WORKD}/node1/node1_socket.sock --log-all-queries --log-failed-queries $PQUERY_EXTRA_OPTIONS > $WORKD/pquery.out 2>&1
        else
          if [ $PQUERY_REVERSE_NOSHUFFLE_OPT -eq 1 ]; then
            PQUERY_SHUFFLE="--no-shuffle"
          else
            # RV 16/02/22: Preventing query count overrun of shuffled SQL replays. May need furher fine tuning. Ref https://jira.mariadb.org/browse/MDEV-27829
            PQUERY_SHUFFLE="--queries-per-thread=$[ $[ $(wc -l ${WORKT} | awk '{print $1}') * 13 / 10 ] + 100 ]"
          fi
          # RV 09/04/22: Something may be amiss with the SHUFFLE_OVERRUN_PREVENTION_MAX_LINES code (i.e. the addition of --queries-per-thread=x in 3 places of the code), but only if true or semi-true multi-threaded reduction relies on ongoing queries to be sent to the server instance being tested, rather than a deterministic number (i.e. the ~lenght of the testcase). If so, that would mean that multi-threaded reduction no longer would function after https://github.com/mariadb-corporation/mariadb-qa/commit/9bc502e7edf2a12022e806e21839463b94f51e8c implementation. To be verified/checked. TODO
          $PQUERY_LOC --database=test --infile=$WORKT $PQUERY_SHUFFLE --threads=$PQUERY_MULTI_CLIENT_THREADS --queries=$PQUERY_MULTI_QUERIES $USE_PQUERYE2_CLIENT_LOGGING --user=root --socket=${WORKD}/node1/node1_socket.sock --log-all-queries --log-failed-queries $PQUERY_EXTRA_OPTIONS > $WORKD/pquery.out 2>&1
        fi
      else
        if [ $PQUERY_MULTI -eq 0 ]; then
          if [ $PQUERY_REVERSE_NOSHUFFLE_OPT -ge 0 ]; then
            PQUERY_SHUFFLE="--no-shuffle"
          else 
            # RV 16/02/22: Preventing query count overrun of shuffled SQL replays. May need furher fine tuning. Ref https://jira.mariadb.org/browse/MDEV-27829
            PQUERY_SHUFFLE="--queries-per-thread=$[ $[ $(wc -l ${WORKT} | awk '{print $1}') * 13 / 10 ] + 100 ]"
          fi
          $PQUERY_LOC --database=test --infile=$WORKT $PQUERY_SHUFFLE --threads=1 $USE_PQUERYE2_CLIENT_LOGGING --user=root --socket=$WORKD/socket.sock --logdir=$WORKD --log-all-queries --log-failed-queries $PQUERY_EXTRA_OPTIONS > $WORKD/pquery.out 2>&1
        else
          if [ $PQUERY_REVERSE_NOSHUFFLE_OPT -eq 1 ]; then
            PQUERY_SHUFFLE="--no-shuffle"
          else 
            # RV 16/02/22: Preventing query count overrun of shuffled SQL replays. May need furher fine tuning. Ref https://jira.mariadb.org/browse/MDEV-27829
            PQUERY_SHUFFLE="--queries-per-thread=$[ $[ $(wc -l ${WORKT} | awk '{print $1}') * 13 / 10 ] + 100 ]"
          fi
          # RV 09/04/22: Something may be amiss with the SHUFFLE_OVERRUN_PREVENTION_MAX_LINES code (i.e. the addition of --queries-per-thread=x in 3 places of the code), but only if true or semi-true multi-threaded reduction relies on ongoing queries to be sent to the server instance being tested, rather than a deterministic number (i.e. the ~lenght of the testcase). If so, that would mean that multi-threaded reduction no longer would function after https://github.com/mariadb-corporation/mariadb-qa/commit/9bc502e7edf2a12022e806e21839463b94f51e8c implementation. To be verified/checked. TODO
          $PQUERY_LOC --database=test --infile=$WORKT $PQUERY_SHUFFLE --threads=$PQUERY_MULTI_CLIENT_THREADS --queries=$PQUERY_MULTI_QUERIES $USE_PQUERYE2_CLIENT_LOGGING --user=root --socket=$WORKD/socket.sock --logdir=$WORKD --log-all-queries --log-failed-queries $PQUERY_EXTRA_OPTIONS > $WORKD/pquery.out 2>&1
        fi
      fi
    else
      if [ "$CLI_MODE" == "" ]; then CLI_MODE=99; fi  # Leads to assert below
      CLIENT_SOCKET=
      if [[ $MDG -eq 1 || $GRP_RPL -eq 1 ]]; then
        CLIENT_SOCKET=${WORKD}/node1/node1_socket.sock
      else
        CLIENT_SOCKET=$WORKD/socket.sock
      fi
      if [ ! -d "${WORKD}" ]; then abort; fi
      case $CLI_MODE in
        0) cat $WORKT | $BASEDIR/bin/mysql -uroot -S${CLIENT_SOCKET} --binary-mode --force test > $WORKD/log/mysql.out 2>&1 ;;
        1) $BASEDIR/bin/mysql -uroot -S${CLIENT_SOCKET} --execute="SOURCE ${WORKT};" --force test > $WORKD/log/mysql.out 2>&1 ;;  # When http://bugs.mysql.com/bug.php?id=81782 is fixed, re-add --binary-mode to this command. Also note that due to http://bugs.mysql.com/bug.php?id=81784, the --force option has to be after the --execute option.
        2) $BASEDIR/bin/mysql -uroot -S${CLIENT_SOCKET} --binary-mode --force test < ${WORKT} > $WORKD/log/mysql.out 2>&1 ;;
        *) echoit "Assert: default clause in CLI_MODE switchcase hit (in run_sql_code). This should not happen. CLI_MODE=${CLI_MODE}"; exit 1 ;;
      esac
    fi
  fi
  sleep 1
}

cleanup_and_save(){
  if [ $MODE -ge 6 ]; then
    if [ "$STAGE" = "T" ]; then rm -Rf $WORKD/log/*.sql; fi
    rm -Rf $WORKD/out/*.sql
    for t in $(eval echo {1..$TS_THREADS}); do
      export TS_WORKF=$(eval echo $(echo '$WORKF'"$t"))
      export TS_WORKT=$(eval echo $(echo '$WORKT'"$t"))
      export TS_WORKO=$(eval echo $(echo '$WORKO'"$t"))
      cp -f $TS_WORKT $TS_WORKF
      cp -f $TS_WORKT $TS_WORKO
      if [ "$STAGE" = "T" ]; then
        export TS_WORKO_TE_FILE=$(eval echo $(echo '$WORKO'"$t") | sed 's/_out//g;s/\/out/\/log/g')
        # Do not copy the eliminated thread
        if [ ! $t -eq $TS_ELIMINATION_THREAD_ID ]; then
          cp -f $TS_WORKO $TS_WORKO_TE_FILE
        fi
      fi
    done
    if [ "$STAGE" = "T" ]; then
      # Move workdir
      if [ $TS_TE_DIR_SWAP_DONE -eq 1 ]; then
        echoit "[Info] ThreadSync input directory now set to $WORKD/log after a thread was eliminated (Directory was re-initialized)"
      else
        echoit "[Info] ThreadSync input directory now set to $WORKD/log after a thread was eliminated"
        TS_TE_DIR_SWAP_DONE=1
      fi
      cp -f $TS_ORIG_DATAINPUTFILE $WORKD/log
      TS_THREADS=$[$TS_THREADS-1]
      TS_ELIMINATED_THREAD_COUNT=$[$TS_ELIMINATED_THREAD_COUNT+1]
      TS_INPUTDIR=$WORKD/log
      TS_init_all_sql_files
    fi
  else
    if [[ $MDG -eq 1 ]]; then
      ( ps -def | grep -E 'n*.cnf' | grep $EPOCH | awk '{print $2}' | xargs -I{} kill -9 {} >/dev/null 2>&1; ) >/dev/null 2>&1
      sleep 2; sync
    fi
    if [[ $GRP_RPL -eq 1 ]]; then
      ( ps -def | grep -E  'node1_socket|node2_socket|node3_socket' | grep $EPOCH | awk '{print $2}' | xargs -I{} kill -9 {} >/dev/null 2>&1; ) >/dev/null 2>&1
      sleep 2; sync
    fi
    cp -f $WORKT $WORKF
    if [ -r "$WORKO" ]; then
      if [[ ${RR_TRACING} -eq 1 ]]; then
        if [[ ${RR_SAVE_ALL_TRACES} -eq 1 ]]; then
          save_rr_trace "${WORK_BUG_DIR}/rr/${STAGE}_${TRIAL}_rr_trace"
          echoit "$ATLEASTONCE [Stage $STAGE] [Trial ${TRIAL}] Saved RR trace in ${WORK_BUG_DIR}/rr/${STAGE}_${TRIAL}_rr_trace"
        fi
      fi
      cp -f $WORKO ${WORKO}.prev
      # Save a testcase backup (this is useful if [oddly] the issue now fails to reproduce)
      echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] Previous good testcase backed up as $WORKO.prev"
    fi
    grep -E --binary-files=text -v "^# mysqld options required for replay:" $WORKT > $WORKO
    MYSQLD_OPTIONS_REQUIRED=$(echo "$SPECIAL_MYEXTRA_OPTIONS $MYEXTRA" | sed "s|[ \t]\+| |g;s|sql_mode=\([^ ]\)|sql_mode= \1|g;s|[ \t]\+| |g")
    if [ "$(echo "$MYSQLD_OPTIONS_REQUIRED" | sed 's| ||g')" != "" ]; then
      if [ -s $WORKO ]; then
        if [ "${MYINIT}" == "" ]; then
          sed -i "1 i\# mysqld options required for replay: $MYSQLD_OPTIONS_REQUIRED" $WORKO
        else
          sed -i "1 i\# mysqld options required for replay: $MYSQLD_OPTIONS_REQUIRED    mysqld initialization options required: ${MYINIT}" $WORKO
        fi
      else
        if [ "${MYINIT}" == "" ]; then
          echo "# mysqld options required for replay: $MYSQLD_OPTIONS_REQUIRED" > $WORKO
        else
          echo "# mysqld options required for replay: $MYSQLD_OPTIONS_REQUIRED    mysqld initialization options required: ${MYINIT}" > $WORKO
        fi
      fi
    elif [ "${MYINIT}" != "" ]; then
      if [ -s $WORKO ]; then
        sed -i "1 i\# mysqld initialization options required: ${MYINIT}" $WORKO
      else
        echo "# mysqld initialization options required: ${MYINIT}" > $WORKO
      fi
    #else here would only happen in the case that MYSQLD_OPTIONS_REQUIRED and MYINIT are both empty.
    fi
    MYSQLD_OPTIONS_REQUIRED=
    cp -f $WORKO $WORK_OUT
    # Save a tarball of full self-contained testcase on each successful reduction
    rm -f $WORK_BUG_DIR/${EPOCH}_bug_bundle.tar.gz
    $(cd $WORK_BUG_DIR; tar -zhcf ${EPOCH}_bug_bundle.tar.gz ${EPOCH}*)
  fi
  ATLEASTONCE="[*]"  # The issue was seen at least once (this is used to permanently mark lines with '[*]' suffix as soon as this happens)
  if [ ${STAGE} -eq 8 ]; then STAGE8_CHK=1; fi
  if [ ${STAGE} -eq 9 ]; then STAGE9_CHK=1; fi
  # VERFIED file creation + subreducer handling
  echo "TRIAL:$TRIAL" > $WORKD/VERIFIED
  echo "WORKO:$WORKO" >> $WORKD/VERIFIED
  if [ "$MULTI_REDUCER" == "1" ]; then  # This is a subreducer
    echo "# $ATLEASTONCE Issue was reproduced during this simplification subreducer." >> $WORKD/VERIFIED
    echoit "$ATLEASTONCE [Stage $STAGE] Issue was reproduced during this simplification subreducer. Terminating now."
    # This is a simplification subreducer started by a parent/main reducer, to simplify an issue. We terminate now after discovering the issue here.
    # We rely on the parent/main reducer to kill off mariadbd/mysqld processes (on the next multi_reducer() call - at the top of the function).
    finish $INPUTFILE
  else
    echo "# $ATLEASTONCE Issue was seen at least once during this run of reducer" >> $WORKD/VERIFIED
  fi
}

process_outcome(){
  if [ $NOISSUEFLOW -lt 0 ]; then NOISSUEFLOW=0; fi

  # MODE0: timeout/hang testing (SET TIMEOUT_CHECK)
  if [ $MODE -eq 0 ]; then
    if [ "${MYSQLD_START_TIME}" == '' ]; then
      echo "Assert: MYSQLD_START_TIME==''"
      echo "Terminating now."
      exit 1
    fi
    RUN_TIME=$[ $(date +'%s') - ${MYSQLD_START_TIME} ]
    if [ ${RUN_TIME} -ge ${TIMEOUT_CHECK_REAL} ]; then
      if [ ! "$STAGE" = "V" ]; then
        echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [*TimeoutBug*] [$NOISSUEFLOW] Swapping files & saving last known good timeout issue in $WORKO"
        control_backtrack_flow
      fi
      cleanup_and_save
      return 1
    else
      if [ ! "$STAGE" = "V" ]; then
        echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [NoTimeoutBug] [$NOISSUEFLOW] Kill server $NEXTACTION"
        NOISSUEFLOW=$[$NOISSUEFLOW+1]
      fi
      return 0
    fi

  # MODE1: Valgrind output testing (set TEXT)
  elif [ $MODE -eq 1 ]; then
    echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] Waiting for Valgrind to terminate analysis"
    while :; do
      sleep 1; sync
      if grep -E --binary-files=text -q "ERROR SUMMARY" $WORKD/valgrind.out; then break; fi
    done
    if grep -E --binary-files=text -iq "$TEXT" $WORKD/valgrind.out $WORKD/log/*.err; then
      if [ ! "$STAGE" = "V" ]; then
        echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [*ValgrindBug*] [$NOISSUEFLOW] Swapping files & saving last known good Valgrind issue in $WORKO"
        control_backtrack_flow
      fi
      cleanup_and_save
      return 1
    else
      if [ ! "$STAGE" = "V" ]; then
        echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [NoValgrindBug] [$NOISSUEFLOW] Kill server $NEXTACTION"
        NOISSUEFLOW=$[$NOISSUEFLOW+1]
      fi
      return 0
    fi

  # MODE2: mysql CLI/pquery client output testing (set TEXT)
  elif [ $MODE -eq 2 ]; then
    FILETOCHECK=
    # Check if this is a pquery client output testing run
    if [ $USE_PQUERY -eq 1 ]; then  # pquery client output testing run
      FILETOCHECK=$WORKD/log/default.node.tld_thread-0.out  # Could use improvement for multi-threaded runs
      FILETOCHECK2=$WORKD/default.node.tld_thread-0.sql
    else  # mysql CLI output testing run
      FILETOCHECK=$WORKD/log/mysql.out
    fi
    # TODO RV 21/07/2022: Found that QC was not implemented correctly previously (not implemented by me). Add variable QCTEXT 
    # (wich is used as a feature on/off flag apparently) to the main variable config and cleanup code. Fixed code below.
    NEWLINENUMBER=
    if [ ! -z "$QCTEXT" ]; then
      NEWLINENUMBER="$(grep -E --binary-files=text "$QCTEXT" $FILETOCHECK2|grep -E --binary-files=text -o "#[0-9]+$"|sed 's/#//g')"
    fi
    # TODO: Add check if same query has same output multiple times (add variable for number of occurrences)
    MODE2_OCCURRENCE=0
    if [ -z "$QCTEXT" ]; then  # Normal run, not QC
      if [ $USE_PQUERY -eq 1 ]; then  # pquery client output testing run, check both logs ftm (TODO: check if this is needed)
        if [ $(grep -E --binary-files=text -c "$TEXT" $FILETOCHECK $FILETOCHECK2 2>/dev/null) -gt 0 ]; then
          MODE2_OCCURRENCE=1
        fi
      else  # mysql CLI output testing run
        if [ $(grep -E --binary-files=text -c "$TEXT" $FILETOCHECK 2>/dev/null) -gt 0 ]; then
          MODE2_OCCURRENCE=1
        fi
      fi
    else  # QC  # TODO: RV 21/07/2022: It is not sure that the '$TEXT#$NEWLINENUMBER$' code is correct, it was what was here to start with. Test later when fixing up QC. Ref QC comment above. It may be that pquery vs CLI also needs to be split.
      if [ $(grep -E --binary-files=text -c "$TEXT#$NEWLINENUMBER$" $FILETOCHECK 2>/dev/null) -gt 0 ]; then
        MODE2_OCCURRENCE=1
      fi
    fi
    if [ $MODE2_OCCURRENCE -eq 1 ]; then
      if [ ! "$STAGE" = "V" ]; then
        echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [*ClientOutputBug*] [$NOISSUEFLOW] Swapping files & saving last known good client output issue in $WORKO"
        control_backtrack_flow
      fi
      cleanup_and_save
      MODE2_OCCURRENCE=
      return 1
    else
      if [ ! "$STAGE" = "V" ]; then
        echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [NoClientOutputBug] [$NOISSUEFLOW] Kill server $NEXTACTION"
        NOISSUEFLOW=$[$NOISSUEFLOW+1]
      fi
      MODE2_OCCURRENCE=
      return 0
    fi

  # MODE3: mariadbd/mysqld error output log testing (set TEXT)
  # When PQUERY_CONS_Q_FAIL=1 then the pquery log will be checked for 'Last [0-9]+ consecutive queries all failed' instead
  elif [ $MODE -eq 3 ]; then
    M3_ISSUE_FOUND=0
    SKIP_NEWBUG=0
    ERRORLOG=
    if [[ $MDG -eq 1 || $GRP_RPL -eq 1 ]]; then
      ERRORLOG=$WORKD/node${GALERA_NODE}/node${GALERA_NODE}.err
      sudo chmod 777 $ERRORLOG
    else
      ERRORLOG=$WORKD/log/*.err
    fi
    if [ $REDUCE_GLIBC_OR_SS_CRASHES -gt 0 ]; then
      M3_OUTPUT_TEXT="ConsoleTypescript"
      # A glibc crash looks similar to: *** Error in `/sda/PS180516-percona-server-5.6.30-76.3-linux-x86_64-debug/bin/mysqld': corrupted double-linked list: 0x00007feb2c0011e0 ***
      if grep -E --binary-files=text -iq '*** Error in' /tmp/reducer_typescript${TYPESCRIPT_UNIQUE_FILESUFFIX}.log; then
        if grep -E --binary-files=text -iq "$TEXT" /tmp/reducer_typescript${TYPESCRIPT_UNIQUE_FILESUFFIX}.log; then
          M3_ISSUE_FOUND=1
        fi
      fi
      # Stack smashing looks similar to: *** stack smashing detected ***: /sda/Percona-Server-5.7.13-6-Linux.x86_64.ssl101/bin/mysqld terminated
      if grep -E --binary-files=text -iq '*** stack smashing' /tmp/reducer_typescript${TYPESCRIPT_UNIQUE_FILESUFFIX}.log; then
        if grep -E --binary-files=text -iq "$TEXT" /tmp/reducer_typescript${TYPESCRIPT_UNIQUE_FILESUFFIX}.log; then
          M3_ISSUE_FOUND=1
        fi
      fi
    else
      if [ $PQUERY_CONS_Q_FAIL -eq 1 ]; then
        # Note that if PQUERY_CONS_Q_FAIL=1 then TEXT is always 'Last [0-9]+ consecutive queries all failed'
        M3_OUTPUT_TEXT="LastConsecutiveQueriesAllFailed"
        if grep -E --binary-files=text -iq "${TEXT}" $WORKD/pquery.out; then
          M3_ISSUE_FOUND=1
        fi
      elif [ $USE_NEW_TEXT_STRING -eq 1 ]; then
        M3_OUTPUT_TEXT="NewTextString"
        rm -f ${WORKD}/MYBUG.FOUND
        touch ${WORKD}/MYBUG.FOUND
        SAVEPATH="${PWD}"
        cd $WORKD
        if [ "${WORKD}" != "${PWD}" ]; then
          echoit "Assert: cd ${WORKD} before USE_NEW_TEXT_STRING parsing failed. Terminating."
          exit 1
        fi
        if [ $MDG -eq 1 ]; then
          export GALERA_ERROR_LOG=$WORKD/node${GALERA_NODE}/node${GALERA_NODE}.err
          export GALERA_CORE_LOC=$WORKD/node${GALERA_NODE}/*core*
        fi
        # If there are *SAN bugs, and if pquery-run.sh wrote a TOP_SAN_ISSUES_REMOVED for the trial, then delete any known ones from the top of the error log(s)
        if grep --binary-files=text -qiE "=ERROR:|runtime error:|AddressSanitizer:|ThreadSanitizer:|LeakSanitizer:|MemorySanitizer:" ${WORKD}/log/*.err; then
          if [ -r "$(echo "${INPUTFILE}" | sed 's|/default.node.tld.*|/TOP_SAN_ISSUES_REMOVED|')" ]; then
            echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] TOP_SAN_ISSUES_REMOVED flag file found: dropping any known *SAN bugs from the top of the error log, if any"
            # We are already in $WORKD so we can immediately execute drop_one_or_more_san_from_log.sh from here
            if [ -r ${SCRIPT_PWD}/drop_one_or_more_san_from_log.sh ]; then
              ${SCRIPT_PWD}/drop_one_or_more_san_from_log.sh  # Do not add any options to this script call as it will cause the top SAN issue to be deleted, irrespective of whetter an issue is known or not: we want only known issues to be removed
            elif [ -r ${HOME}/mariadb-qa/drop_one_or_more_san_from_log.sh ]; then  # This location is used for example when starting ./reducer_new_text_string.sh from within a BASEDIR (As created by startup.sh)
              ${HOME}/mariadb-qa/drop_one_or_more_san_from_log.sh  # Idem as above; do not add options
            else
              echo "Assert: ${SCRIPT_PWD}/drop_one_or_more_san_from_log.sh nor ${HOME}/mariadb-qa/drop_one_or_more_san_from_log.sh found - please check your setup"
              exit 1
            fi
          fi
        fi
        MYBUGFOUND="$(${TEXT_STRING_LOC} "${BIN}" 2>/dev/null)"
        NTSEXITCODE=${?}
        echo "${MYBUGFOUND}" >> ${WORKD}/MYBUG.FOUND
        echo ${NTSEXITCODE} > ${WORKD}/MYBUG.FOUND.EXITCODE
        if [ ${NTSEXITCODE} -ne 0 ]; then
          if grep --binary-files=text -qi 'no core file' ${WORKD}/MYBUG.FOUND; then
            # 'no core file' was seen in ${WORKD}/MYBUG.FOUND; this is definitely not a newbug
            SKIP_NEWBUG=1
          elif grep --binary-files=text -qi 'Assert: No parsable frames' ${WORKD}/MYBUG.FOUND; then
            # This is seen when no core was generated, i.e. the bug did not reproduce and there is definitely not a newbug
            # RV update 24-08-20: Is the above correct? No parsable frames may be OOS or a smashed stack, but in general this message would be only there IF a core was generated, but could somehow not be parsed. Disabled the next line to debug based on cases of it seen in the future.
            #SKIP_NEWBUG=1
            sleep 0.00001  # dummy sleep to allow leaving the IF active
          else
            echoit "Assert: exit code for $TEXT_STRING_LOC was not 0; this should not happen. Exitcode was ${NTSEXITCODE} and message was; '$(cat ${WORKD}/MYBUG.FOUND)'. Please check files in ${WORKD}. Terminating."
            SKIP_NEWBUG=1
            exit 1
          fi
        fi
        cd - >/dev/null
        if [ "${SAVEPATH}" != "${PWD}" ]; then
          echoit "Assert: cd - after USE_NEW_TEXT_STRING parsing failed. Retrying..."
          cd ${SAVEPATH}  # Second attempt
          if [ "${SAVEPATH}" != "${PWD}" ]; then
            echoit "Assert: cd ${SAVEPATH} after USE_NEW_TEXT_STRING parsing failed. Terminating."
            exit 1
          else
            echoit "> Second attempt using cd ${SAVEPATH} worked. Reducer can continue, but this is not normal, please check cause, especially if message is seen regularly during reducer runs or is looping."
          fi
        fi
        SAVEPATH=
        if [ "${MODE3_ANY_SIG}" != "1" ]; then
          FINDBUG="$(grep -Fi --binary-files=text "${TEXT}" ${WORKD}/MYBUG.FOUND)"  # Do not use "^${TEXT}", not only will this not work (the grep is not regex aware, nor can it be, due to the many special (regex-like) characters in the unique bug strings), but it is also not required here; we want to be able to search for part of the string, and the risk of an incorrect "more generic unique bug string with a more specific one being looked for" match is very low.
        else
          FINDBUG="$(grep -i --binary-files=text "^SIG" ${WORKD}/MYBUG.FOUND)"  # Search for any signal (SIGSEGV, SIGABRT, etc.) using regex "^SIG"
        fi
        if [ ! -z "${FINDBUG}" ]; then  # $TEXT_STRING_LOC yielded same bug as the one being reduced for
          M3_ISSUE_FOUND=1
          FINDBUG=
        else  # $TEXT_STRING_LOC yielded another output (error, or a different bug - new or already existing)
          FINDBUG=
          if [ ${SCAN_FOR_NEW_BUGS} -eq 1 -a ${SKIP_NEWBUG} -ne 1 ]; then
            if [ ${NTSEXITCODE} -eq 0 ]; then
              # If we received a 0 exit code, then a proper unique bug ID was returned by new_text_string.sh (or any other script as set in $TEXT_STRING_LOC) and this script can now scan known bugs and copy info if something new was found
              FINDBUG="$(grep -Fi --binary-files=text "${MYBUGFOUND}" ${KNOWN_BUGS_LOC} | head -n1)"
              if [[ "${FINDBUG}" == "#"* ]]; then FINDBUG=''; fi  # Bugs marked as fixed need to be excluded. This cannot be done by using "^${TEXT}" as the grep is not regex aware, nor can it be, due to the many special (regex-like) characters in the unique bug strings
              if [ -z "${FINDBUG}" ]; then  # Reducer found a new bug (nothing found in known bugs)
                # TODO: need some provision for when MYBUG.FOUND is empty (possibly due to top SAN issues being dropped?)
                echoit "[NewBug] Reducer located a new bug while reducing this issue: $(cat ${WORKD}/MYBUG.FOUND 2>/dev/null | head -n1)"
                EPOCH_RAN="$(date +%H%M%S%N)${RANDOM}"
                if [ ! -z "${NEW_BUGS_SAVE_DIR}" ]; then  # If set, we need to copy this new bug to the NEW_BUGS_SAVE_DIR
                  if [ ! -d "${NEW_BUGS_SAVE_DIR}" ]; then  # Leave this check, it re-checks if the [previously created, at the start of the script] NEW_BUGS_SAVE_DIR still exists
                    echo "Assert: SCAN_FOR_NEW_BUGS was set to 1, and NEW_BUGS_SAVE_DIR was set to '${NEW_BUGS_SAVE_DIR}'. This directory already existed, or was created succesfully at the start of this script run. However, it is not present anymore. Please check cause as this should not happen."
                    echo "Terminating now."
                    exit 1
                  fi
                  NEWBUGSO="${NEW_BUGS_SAVE_DIR}/newbug_${EPOCH_RAN}.sql"
                  NEWBUGTO="${NEW_BUGS_SAVE_DIR}/newbug_${EPOCH_RAN}.string"
                  NEWBUGRE="${NEW_BUGS_SAVE_DIR}/newbug_${EPOCH_RAN}.reducer.sh"
                  NEWBUGVM="${NEW_BUGS_SAVE_DIR}/newbug_${EPOCH_RAN}.varmod"
                else
                  NEWBUGSO="$(echo $INPUTFILE | sed "s|$|_newbug_${EPOCH_RAN}.sql|")"
                  NEWBUGTO="$(echo $INPUTFILE | sed "s|$|_newbug_${EPOCH_RAN}.string|")"
                  NEWBUGRE="$(echo $INPUTFILE | sed "s|$|_newbug_${EPOCH_RAN}.reducer.sh|")"
                  NEWBUGVM="$(echo $INPUTFILE | sed "s|$|_newbug_${EPOCH_RAN}.varmod|")"
                fi
                if [[ ${RR_TRACING} -eq 1 ]]; then
                  save_rr_trace "${NEW_BUGS_SAVE_DIR}/${EPOCH_RAN}_rr_trace"
                  echoit "[NewBug] Saved RR trace in ${NEW_BUGS_SAVE_DIR}/${EPOCH_RAN}_rr_trace"
                fi
                cp "${WORKT}" "${NEWBUGSO}"
                echoit "[NewBug] Saved the new testcase to: ${NEWBUGSO}"
                cp "${WORKD}/MYBUG.FOUND" "${NEWBUGTO}"
                echoit "[NewBug] Saved the Unique bug ID to: ${NEWBUGTO}"
                # The next line takes this file (i.e. the current running reducer) and removes the #VARMOD# section
                # if present (it will be present if the NEWBUG was found by a subreducer), thereby making it a main
                # reducer itself rather than a subreducer. None of the variables saved in the #VARMOD# section by the
                # main reducer and used by the subreducer are likely of any significance in reproduction, as they are
                # mostly copied from the main reducer. Still, to not loose any reproducibility (if any), the varmod
                # block is stored as a .varmod file along with the epoch .string, .sql, and .reducer.sh newbug files
                # The exact working is: when ^#VARMOD# is found print it once (as in the next command it is included in
                # the delete, yet it need to stay. Then (the next command), take from ^MULTI_REDUCER= to ^#VARMOD# and
                # delete it. For the .varmod creation command, it is the reverse: print that block, (d)elete the rest
                # Also, in the secondary sed, FIREWORKS is turned off for the newly created (for bug reducing) reducer
                sed '/^#VARMOD#/p;/^MULTI_REDUCER=/,/^#VARMOD#/d' "$(readlink -f ${BASH_SOURCE[0]})" | sed 's|^FIREWORKS=1|FIREWORKS=0|' > "${NEWBUGRE}"
                sed '/^MULTI_REDUCER=/,/^#VARMOD#/p;d' "$(readlink -f ${BASH_SOURCE[0]})" | grep -v "^#VARMOD#" > "${NEWBUGVM}"
                sed -i "s|^INPUTFILE=.*$|INPUTFILE=\"\$(ls --color=never -t ${NEW_BUGS_SAVE_DIR}/newbug_${EPOCH_RAN}.sql* \| grep --binary-files=text -vE \"backup\|failing\" \| head -n1)\"|" "${NEWBUGRE}"
                NEWBUGTEXT="$(cat "${NEWBUGTO}" | sed 's|"|\\\\"|g')" # The sed transforms " to \" to avoid TEXT containing doube quotes in reducer.sh. Potential TODO: when checking this manually, " was changed to \\" not \" so there may be a bug here in too many back slashes. If we run into that, update the sed to one less backslash.
                # This code is taken from pquery-prep-red.sh, if it is updated here, please also update it there and vice versa. Note that the code between this script and pquery-prep-red.sh significantly differs however. See the info/note in pquery-prep-red.sh.
                # HOWEVER, *** IMPORTANT NOTE ***, Note that here we have both '^   TEXT' and '^TEXT' instead of '^TEXT' only, as we are often using already-modified copied reducers, not the original reducer.sh, i.e. reducers which already use '^   TEXT'. So when copying this from another tool, remember to re-add the '^   TEXT' versions! If this is not done, then the result is that all NEWBUGS reducers will just have the original TEXT= and not the newly found bug, thereby defeating the purpose of 'NEWBUGS'.
                NEWBUGTEXT_FINAL=
                if [[ "${NEWBUGTEXT}" = *":"* ]]; then
                  if [[ "${NEWBUGTEXT}" = *"|"* ]]; then
                    if [[ "${NEWBUGTEXT}" = *"/"* ]]; then
                      if [[ "${NEWBUGTEXT}" = *"_"* ]]; then
                        if [[ "${NEWBUGTEXT}" = *"-"* ]]; then
                          if [[ "${NEWBUGTEXT}" = *"("* ]]; then
                            if [[ "${NEWBUGTEXT}" = *")"* ]]; then
                              if [[ "${NEWBUGTEXT}" = *"@"* ]]; then
                                if [[ "${NEWBUGTEXT}" = *"+"* ]]; then
                                  if [[ "${NEWBUGTEXT}" = *";"* ]]; then
                                    if [[ "${NEWBUGTEXT}" = *","* ]]; then
                                      if [[ "${NEWBUGTEXT}" = *">"* ]]; then
                                        echo "Assert (#1)! No suitable sed seperator found. NEWBUGTEXT (${NEWBUGTEXT}) contains all of the possibilities, add more!"
                                        NEWBUGTEXT_FINAL="ASSERT: No suitable sed seperator found in reducer.sh; add more!"
                                        sed -i "s|^   TEXT=.*|   TEXT=\"${NEWBUGTEXT_FINAL}\"|" "${NEWBUGRE}"
                                        sed -i "s|^TEXT=.*|TEXT=\"${NEWBUGTEXT_FINAL}\"|" "${NEWBUGRE}"
                                      else
                                        NEWBUGTEXT_FINAL="$(echo "$NEWBUGTEXT" | sed "s>&>\\\\\\&>g")"  # Escape '&' correctly
                                        sed -i "s>^   TEXT=.*>   TEXT=\"${NEWBUGTEXT_FINAL}\">" "${NEWBUGRE}"
                                        sed -i "s>^TEXT=.*>TEXT=\"${NEWBUGTEXT_FINAL}\">" "${NEWBUGRE}"
                                      fi
                                    else
                                      NEWBUGTEXT_FINAL="$(echo "$NEWBUGTEXT" | sed "s,&,\\\\\\&,g")"  # Escape '&' correctly
                                      sed -i "s,^   TEXT=.*,   TEXT=\"${NEWBUGTEXT_FINAL}\"," "${NEWBUGRE}"
                                      sed -i "s,^TEXT=.*,TEXT=\"${NEWBUGTEXT_FINAL}\"," "${NEWBUGRE}"
                                    fi
                                  else
                                    NEWBUGTEXT_FINAL="$(echo "$NEWBUGTEXT" | sed "s;&;\\\\\\&;g")"  # Escape '&' correctly
                                    sed -i "s;^   TEXT=.*;   TEXT=\"${NEWBUGTEXT_FINAL}\";" "${NEWBUGRE}"
                                    sed -i "s;^TEXT=.*;TEXT=\"${NEWBUGTEXT_FINAL}\";" "${NEWBUGRE}"
                                  fi
                                else
                                  NEWBUGTEXT_FINAL="$(echo "$NEWBUGTEXT" | sed "s+&+\\\\\\&+g")"  # Escape '&' correctly
                                  sed -i "s+^   TEXT=.*+   TEXT=\"${NEWBUGTEXT_FINAL}\"+" "${NEWBUGRE}"
                                  sed -i "s+^TEXT=.*+TEXT=\"${NEWBUGTEXT_FINAL}\"+" "${NEWBUGRE}"
                                fi
                              else
                                NEWBUGTEXT_FINAL="$(echo "$NEWBUGTEXT" | sed "s@&@\\\\\\&@g")"  # Escape '&' correctly
                                sed -i "s@^   TEXT=.*@   TEXT=\"${NEWBUGTEXT_FINAL}\"@" "${NEWBUGRE}"
                                sed -i "s@^TEXT=.*@TEXT=\"${NEWBUGTEXT_FINAL}\"@" "${NEWBUGRE}"
                              fi
                            else
                              NEWBUGTEXT_FINAL="$(echo "$NEWBUGTEXT" | sed "s)&)\\\\\\&)g")"  # Escape '&' correctly
                              sed -i "s)^   TEXT=.*)   TEXT=\"${NEWBUGTEXT_FINAL}\")" "${NEWBUGRE}"
                              sed -i "s)^TEXT=.*)TEXT=\"${NEWBUGTEXT_FINAL}\")" "${NEWBUGRE}"
                            fi
                          else
                            NEWBUGTEXT_FINAL="$(echo "$NEWBUGTEXT" | sed "s(&(\\\\\\&(g")"  # Escape '&' correctly
                            sed -i "s(^   TEXT=.*(   TEXT=\"${NEWBUGTEXT_FINAL}\"(" "${NEWBUGRE}"
                            sed -i "s(^TEXT=.*(TEXT=\"${NEWBUGTEXT_FINAL}\"(" "${NEWBUGRE}"
                          fi
                        else
                          NEWBUGTEXT_FINAL="$(echo "$NEWBUGTEXT" | sed "s-&-\\\\\\&-g")"  # Escape '&' correctly
                          sed -i "s-^   TEXT=.*-   TEXT=\"${NEWBUGTEXT_FINAL}\"-" "${NEWBUGRE}"
                          sed -i "s-^TEXT=.*-TEXT=\"${NEWBUGTEXT_FINAL}\"-" "${NEWBUGRE}"
                        fi
                      else
                        NEWBUGTEXT_FINAL="$(echo "$NEWBUGTEXT" | sed "s_&_\\\\\\&_g")"  # Escape '&' correctly
                        sed -i "s_^   TEXT=.*_   TEXT=\"${NEWBUGTEXT_FINAL}\"_" "${NEWBUGRE}"
                        sed -i "s_^TEXT=.*_TEXT=\"${NEWBUGTEXT_FINAL}\"_" "${NEWBUGRE}"
                      fi
                    else
                      NEWBUGTEXT_FINAL="$(echo "$NEWBUGTEXT" | sed "s/&/\\\\\\&/g")"  # Escape '&' correctly
                      sed -i "s/^   TEXT=.*/   TEXT=\"${NEWBUGTEXT_FINAL}\"/" "${NEWBUGRE}"
                      sed -i "s/^TEXT=.*/TEXT=\"${NEWBUGTEXT_FINAL}\"/" "${NEWBUGRE}"
                    fi
                  else
                    NEWBUGTEXT_FINAL="$(echo "$NEWBUGTEXT" | sed "s|&|\\\\\\&|g")"  # Escape '&' correctly
                    sed -i "s|^   TEXT=.*|   TEXT=\"${NEWBUGTEXT_FINAL}\"|" "${NEWBUGRE}"
                    sed -i "s|^TEXT=.*|TEXT=\"${NEWBUGTEXT_FINAL}\"|" "${NEWBUGRE}"
                  fi
                else
                  NEWBUGTEXT_FINAL="$(echo "$NEWBUGTEXT" | sed "s:&:\\\\\\&:g")"  # Escape '&' correctly
                  sed -i "s:^   TEXT=.*:   TEXT=\"${NEWBUGTEXT_FINAL}\":" "${NEWBUGRE}"
                  sed -i "s:^TEXT=.*:TEXT=\"${NEWBUGTEXT_FINAL}\":" "${NEWBUGRE}"
                fi
                NEWBUGTEXT_FINAL=
                NEWBUGTEXT=
                sed -i "s|^FORCE_SKIPV=.*|FORCE_SKIPV=0|" "${NEWBUGRE}"  # Do not skip verification (more handy when using large_newbug_run.sh)
                sed -i "s|^THREADS=.*|THREADS=3|" "${NEWBUGRE}"
                sed -i "s|^MULTI_THREADS_INCREASE=.*|MULTI_THREADS_INCREASE=1|" "${NEWBUGRE}"
                sed -i "s|^MULTI_THREADS_MAX=.*|MULTI_THREADS_MAX=5|" "${NEWBUGRE}"
                sed -i "s|^STAGE1_LINES=.*|STAGE1_LINES=15|" "${NEWBUGRE}"  # Leave at 15. 7 Proved too low for most issues (looping)
                sed -i "s|^BASEDIR=.*|BASEDIR=\"${BASEDIR}\"|" "${NEWBUGRE}"
                sed -i "s|^MYEXTRA=.*|MYEXTRA=\"--no-defaults ${MYEXTRA}\"|" "${NEWBUGRE}"  # TODO check this works correctly now
                sed -i "s|^REPLICATION=.*|REPLICATION=${REPLICATION}|" "${NEWBUGRE}"
                sed -i "s|^REPL_EXTRA=.*|REPL_EXTRA=\"${REPL_EXTRA}\"|" "${NEWBUGRE}"
                sed -i "s|^MASTER_EXTRA=.*|MASTER_EXTRA=\"${MASTER_EXTRA}\"|" "${NEWBUGRE}"
                sed -i "s|^SLAVE_EXTRA=.*|SLAVE_EXTRA=\"${SLAVE_EXTRA}\"|" "${NEWBUGRE}"
                chmod +x "${NEWBUGRE}"
                echoit "[NewBug] Saved the new bug reducer to: ${NEWBUGRE}"
                NEWBUGSO=
                NEWBUGTO=
                NEWBUGRE=
                NEWBUGVM=
                EPOCH_RAN=
              fi  # No else needed; if the bug was found, it means it was pre-exisiting AND not fixed yet (note the secondary if which excludes fixed bugs remarked with a leading '#' in the known bugs list file)
              FINDBUG=
            fi  # No else needed; if the exit code was 1, then either no issue was reproduced this trial, or there was some other issue (handled already above)
          fi
        fi
        MYBUGFOUND=
        NTSEXITCODE=
        FINDBUG=
      else
        M3_OUTPUT_TEXT="ErrorLog"
        if grep -E --binary-files=text -iq "$TEXT" $ERRORLOG; then M3_ISSUE_FOUND=1; fi
      fi
    fi
    if [ $M3_ISSUE_FOUND -eq 1 ]; then
      if [ ! "$STAGE" = "V" -a "${FIREWORKS}" != "1" ]; then
        echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [*${M3_OUTPUT_TEXT}OutputBug*] [$NOISSUEFLOW] Swapping files & saving last known good testcase in $WORKO"
        control_backtrack_flow
      fi
      sleep 2; sync
      cleanup_and_save
      if [ $MDG -eq 0 ]; then
        return 1
      fi
    else
      if [ ! "$STAGE" = "V" ]; then
        echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [No${M3_OUTPUT_TEXT}OutputBug] [$NOISSUEFLOW] Kill server $NEXTACTION"
        NOISSUEFLOW=$[$NOISSUEFLOW+1]
      fi
      return 0
    fi

  # MODE4: Crash testing
  elif [ $MODE -eq 4 ]; then
    ADMIN_BIN_TO_USE="${BASEDIR}/bin/mariadb-admin"
    if [ ! -r "${ADMIN_BIN_TO_USE}" ]; then ADMIN_BIN_TO_USE="${BASEDIR}/bin/mysqladmin"; fi
    M4_ISSUE_FOUND=0
    if [ $MDG -eq 1 ]; then
      for i in $(seq 1 ${NR_OF_NODES}); do
        if [ $MDG_ISSUE_NODE -eq 0 -o $MDG_ISSUE_NODE -eq ${i} ]; then
          if ! ${ADMIN_BIN_TO_USE} -uroot --socket=$WORKD/node${i}/node${i}_socket.sock ping > /dev/null 2>&1; then M4_ISSUE_FOUND=1; fi
        fi
      done
    elif [ $GRP_RPL -eq 1 ]; then
      if [ $GRP_RPL_ISSUE_NODE -eq 0 -o $GRP_RPL_ISSUE_NODE -eq 1 ]; then
        if ! ${ADMIN_BIN_TO_USE} -uroot --socket=${node1}/node1_socket.sock ping > /dev/null 2>&1; then M4_ISSUE_FOUND=1; fi
      fi
      if [ $GRP_RPL_ISSUE_NODE -eq 0 -o $GRP_RPL_ISSUE_NODE -eq 2 ]; then
        if ! ${ADMIN_BIN_TO_USE} -uroot --socket=${node2}/node2_socket.sock ping > /dev/null 2>&1; then M4_ISSUE_FOUND=1; fi
      fi
      if [ $GRP_RPL_ISSUE_NODE -eq 0 -o $GRP_RPL_ISSUE_NODE -eq 3 ]; then
        if ! ${ADMIN_BIN_TO_USE} -uroot --socket=${node3}/node3_socket.sock ping > /dev/null 2>&1; then M4_ISSUE_FOUND=1; fi
      fi
    else
      if [ $REDUCE_GLIBC_OR_SS_CRASHES -gt 0 ]; then
        # A glibc crash looks similar to: *** Error in `/sda/PS180516-percona-server-5.6.30-76.3-linux-x86_64-debug/bin/mysqld': corrupted double-linked list: 0x00007feb2c0011e0 ***
        if grep -E --binary-files=text -iq '*** Error in' /tmp/reducer_typescript${TYPESCRIPT_UNIQUE_FILESUFFIX}.log; then
          M4_ISSUE_FOUND=1
        fi
        # Stack smashing looks similar to: *** stack smashing detected ***: /sda/Percona-Server-5.7.13-6-Linux.x86_64.ssl101/bin/mysqld terminated
        if grep -E --binary-files=text -iq '*** stack smashing' /tmp/reducer_typescript${TYPESCRIPT_UNIQUE_FILESUFFIX}.log; then
          M4_ISSUE_FOUND=1
        fi
      else
        if ! ${ADMIN_BIN_TO_USE} -uroot -S$WORKD/socket.sock ping > /dev/null 2>&1; then M4_ISSUE_FOUND=1; fi
      fi
    fi
    ADMIN_BIN_TO_USE=
    if [ $REDUCE_GLIBC_OR_SS_CRASHES -gt 0 ]; then
      M4_OUTPUT_TEXT="GlibcCrash"
    else
      M4_OUTPUT_TEXT="Crash"
    fi
    if [ $M4_ISSUE_FOUND -eq 1 ]; then
      if [ ! "$STAGE" = "V" ]; then
        if [ $STAGE -eq 6 ]; then
          echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [Column $COLUMN/$COUNTCOLS] [*$M4_OUTPUT_TEXT*] Swapping files & saving last known good crash in $WORKO"
        else
          echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [*$M4_OUTPUT_TEXT*] [$NOISSUEFLOW] Swapping files & saving last known good crash in $WORKO"
        fi
        control_backtrack_flow
      fi
      cleanup_and_save
      return 1
    else
      if [ ! "$STAGE" = "V" ]; then
        if [ $STAGE -eq 6 ]; then
          echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [Column $COLUMN/$COUNTCOLS] [No$M4_OUTPUT_TEXT] Kill server $NEXTACTION"
        else
          echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [No$M4_OUTPUT_TEXT] [$NOISSUEFLOW] Kill server $NEXTACTION"
        fi
        NOISSUEFLOW=$[$NOISSUEFLOW+1]
      fi
      return 0
    fi

  # MODE5: MTR testcase reduction testing (set TEXT)
  elif [ $MODE -eq 5 ]; then
    COUNT_TEXT_OCCURRENCES=$(grep -E --binary-files=text -ic "$TEXT" $WORKD/log/mysql.out)
    if [ $COUNT_TEXT_OCCURRENCES -ge $MODE5_COUNTTEXT ]; then
      COUNT_TEXT_OCCURRENCES=$(grep -E --binary-files=text -ic "$MODE5_ADDITIONAL_TEXT" $WORKD/log/mysql.out)
      if [ $COUNT_TEXT_OCCURRENCES -ge $MODE5_ADDITIONAL_COUNTTEXT ]; then
        if [ ! "$STAGE" = "V" ]; then
          echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [*MTRCaseOutputBug*] [$NOISSUEFLOW] Swapping files & saving last known good MTR testcase output issue in $WORKO"
          control_backtrack_flow
        fi
        cleanup_and_save
        return 1
      else
        if [ ! "$STAGE" = "V" ]; then
          echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [NoMTRCaseOutputBug] [$NOISSUEFLOW] Kill server $NEXTACTION"
          NOISSUEFLOW=$[$NOISSUEFLOW+1]
        fi
        return 0
      fi
    else
      if [ ! "$STAGE" = "V" ]; then
        echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [NoMTRCaseOutputBug] [$NOISSUEFLOW] Kill server $NEXTACTION"
        NOISSUEFLOW=$[$NOISSUEFLOW+1]
      fi
      return 0
    fi

  # MODE6: ThreadSync Valgrind output testing (set TEXT)
  elif [ $MODE -eq 6 ]; then
    echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] Waiting for Valgrind to terminate analysis"
    while :; do
      sleep 1; sync
      if grep -E --binary-files=text -q "ERROR SUMMARY" $WORKD/valgrind.out; then break; fi
    done
    if grep -E --binary-files=text -iq "$TEXT" $WORKD/valgrind.out; then
      if [ "$STAGE" = "T" ]; then
        echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [*TSValgrindBug*] [$NOISSUEFLOW] Swapping files & saving last known good Valgrind issue thread file(s) in $WORKD/log/"
      elif [ ! "$STAGE" = "V" ]; then
        echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [*TSValgrindBug*] [$NOISSUEFLOW] Swapping files & saving last known good Valgrind issue thread file(s) in $WORKD/out/"
        control_backtrack_flow
      fi
      cleanup_and_save
      return 1
    else
      if [ ! "$STAGE" = "V" -a ! "$STAGE" = "T" ]; then
        echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [NoTSValgrindBug] [$NOISSUEFLOW] Kill server $NEXTACTION"
        NOISSUEFLOW=$[$NOISSUEFLOW+1]
      fi
      return 0
    fi

  # MODE7: ThreadSync mysql CLI output testing (set TEXT)
  elif [ $MODE -eq 7 ]; then
    if grep -E --binary-files=text -iq "$TEXT" $WORKD/log/mysql.out; then
      if [ "$STAGE" = "T" ]; then
        echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [*TSCLIOutputBug*] [$NOISSUEFLOW] Swapping files & saving last known good CLI output issue thread file(s) in $WORKD/log/"
      elif [ ! "$STAGE" = "V" ]; then
        echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [*TSCLIOutputBug*] [$NOISSUEFLOW] Swapping files & saving last known good CLI output issue thread file(s) in $WORKD/out/"
        control_backtrack_flow
      fi
      cleanup_and_save
      return 1
    else
      if [ ! "$STAGE" = "V" -a ! "$STAGE" = "T" ]; then
        echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [NoTSCLIOutputBug] [$NOISSUEFLOW] Kill server $NEXTACTION"
        NOISSUEFLOW=$[$NOISSUEFLOW+1]
      fi
      return 0
    fi

  # MODE8: ThreadSync mariadbd/mysqld error output log testing (set TEXT)
  elif [ $MODE -eq 8 ]; then
    if grep -E --binary-files=text -iq "$TEXT" $WORKD/log/*.err; then
      if [ "$STAGE" = "T" ]; then
        echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [*TSErrorLogOutputBug*] [$NOISSUEFLOW] Swapping files & saving last known good error log output issue thread file(s) in $WORKD/log/"
      elif [ ! "$STAGE" = "V" ]; then
        echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [*TSErrorLogOutputBug*] [$NOISSUEFLOW] Swapping files & saving last known good error log output issue thread file(s) in $WORKD/out/"
        control_backtrack_flow
      fi
      cleanup_and_save
      return 1
    else
      if [ ! "$STAGE" = "V" -a ! "$STAGE" = "T" ]; then
        echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [NoTSErrorLogOutputBug] [$NOISSUEFLOW] Kill server $NEXTACTION"
        NOISSUEFLOW=$[$NOISSUEFLOW+1]
      fi
      return 0
    fi

  # MODE9: ThreadSync Crash testing
  elif [ $MODE -eq 9 ]; then
    ADMIN_BIN_TO_USE="${BASEDIR}/bin/mariadb-admin"
    if [ ! -r "${ADMIN_BIN_TO_USE}" ]; then ADMIN_BIN_TO_USE="${BASEDIR}/bin/mysqladmin"; fi
    if ! ${ADMIN_BIN_TO_USE} -uroot -S$WORKD/socket.sock ping > /dev/null 2>&1; then
      if [ "$STAGE" = "T" ]; then
        echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [*TSCrash*] [$NOISSUEFLOW] Swapping files & saving last known good crash thread file(s) in $WORKD/log/"
      elif [ ! "$STAGE" = "V" ]; then
        echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [*TSCrash*] [$NOISSUEFLOW] Swapping files & saving last known good crash thread file(s) in $WORKD/out/"
        control_backtrack_flow
      fi
      cleanup_and_save
      return 1
    else
      if [ ! "$STAGE" = "V" -a ! "$STAGE" = "T" ]; then
        echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [NoTSCrash] [$NOISSUEFLOW] Kill server $NEXTACTION"
        NOISSUEFLOW=$[$NOISSUEFLOW+1]
      fi
      return 0
    fi
    ADMIN_BIN_TO_USE=

  # Invalid mode
  else
    echoit "Assert: invalid MODE (MODE=${MODE}) discovered. Terminating."
    exit 1
  fi
}

stop_mysqld_or_mdg(){
  SHUTDOWN_TIME_START=$(date +'%s')
  MODE0_MIN_SHUTDOWN_TIME=$[ $TIMEOUT_CHECK + 10 ]
  if [[ $MDG -eq 1 || $GRP_RPL -eq 1 ]]; then
    ( ps -def | grep -E 'n*.cnf' | grep $EPOCH | awk '{print $2}' | xargs -I{} kill -9 {} >/dev/null 2>&1; ) >/dev/null 2>&1
    sleep 2; sync
  else
    if [ ${FORCE_KILL} -eq 1 -a ${MODE} -ne 0 -a ${FIRST_MYSQLD_START_FLAG} -ne 1 ]; then  # In MODE=0 we may be checking for shutdown hang issues, so do not kill mariadbd/mysqld. For the first init startup of mariadbd/mysqld, kill should also not be used.
      while :; do
        KPIDS="${PIDV}"
        if [ "${REPLICATION}" -eq 1 ]; then
          KPIDS="${PIDV} ${PIDV_SLAVE}"
        fi
        if kill -0 ${KPIDS} >/dev/null 2>&1; then
          sleep 1
          ( kill -9 ${KPIDS} >/dev/null 2>&1; ) >/dev/null 2>&1
        else
          break
        fi
        KPIDS=
      done
    else
      # RV-15/09/14 Added timeout due to bug http://bugs.mysql.com/bug.php?id=73914
      # RV-02/12/14 We do not want too fast a shutdown either; quite a few bugs happen when mariadbd/mysqld is being shutdown
      # RV-22/03/17 To check for shutdown hangs, need to make sure that timeout of mariadb-admin/mysqladmin is longer then TIMEOUT_CHECK seconds + 10 seconds safety margin
      if [ $MODE -eq 0 ]; then
        ADMIN_BIN_TO_USE="${BASEDIR}/bin/mariadb-admin"
        if [ ! -r "${ADMIN_BIN_TO_USE}" ]; then ADMIN_BIN_TO_USE="${BASEDIR}/bin/mysqladmin"; fi
        timeout -k${MODE0_MIN_SHUTDOWN_TIME} -s9 ${MODE0_MIN_SHUTDOWN_TIME}s ${ADMIN_BIN_TO_USE} -uroot -S$WORKD/socket.sock shutdown >> $WORKD/log/mysqld.out 2>&1
        if [ "${REPLICATION}" -eq 1 ]; then
          timeout -k${MODE0_MIN_SHUTDOWN_TIME} -s9 ${MODE0_MIN_SHUTDOWN_TIME}s ${ADMIN_BIN_TO_USE} -uroot -S$WORKD/slave_socket.sock shutdown >> $WORKD/log/mysqld_slave.out 2>&1
        fi
        ADMIN_BIN_TO_USE=
        if grep -qiE "Access denied for user|Доступ закрыт для пользователя" $WORKD/log/mysqld*.out; then
          echoit "Assert: Access denied for user detected (ref $WORKD/log/mysqld*.out)"  # If you update the 'Access denied for user detected' here, make sure to update it everwhere else in this script also, especially the grep -qi which checks for this text
          # exit 1  # RV-11/01/2022 We should not unconditionally exit here, and potentially not exit at all; if this is a subreducer thread, the mariadbd/mysqld kill below is a much more sensible next step. For example, if the sql has had a chunck removed which caused this 'Access denied' than the next trial it may be perfectly possible reduce the testcase further in anohter way (for example, the sql that causes the 'Access denied' issue in the first place may be filtered out, etc. Even if an exit would be preferred here (unlikely), then it should be made conditional.
        fi
      else
        # RV 02/01/2021: increased timeout to 60 up from 40 as even high end servers which are busy may take bit longer to write a core
        ADMIN_BIN_TO_USE="${BASEDIR}/bin/mariadb-admin"
        if [ ! -r "${ADMIN_BIN_TO_USE}" ]; then ADMIN_BIN_TO_USE="${BASEDIR}/bin/mysqladmin"; fi
        timeout -k60 -s9 60s ${ADMIN_BIN_TO_USE} -uroot -S$WORKD/socket.sock shutdown >> $WORKD/log/mysqld.out 2>&1  # Note it is mariadb-admin/myqlsadmin being terminated with -9, not mariadbd/mysqld !
        if [ "${REPLICATION}" -eq 1 ]; then
          timeout -k60 -s9 60s ${ADMIN_BIN_TO_USE} -uroot -S$WORKD/slave_socket.sock shutdown >> $WORKD/log/mysqld_slave.out 2>&1  # Note it is mariadb-admin/myqladmin being terminated with -9, not mysqld !
        fi
        ADMIN_BIN_TO_USE=
        if grep -qiE "Access denied for user|Доступ закрыт для пользователя" $WORKD/log/mysqld*.out; then
          echoit "Assert: Access denied for user detected (ref $WORKD/log/mysqld*.out)"  # If you update the 'Access denied for user detected' here, make sure to update it everwhere else in this script also, especially the grep -qi which checks for this text
          # exit 1  # Ref RV-11/01/2022 note above
        fi
      fi
      if [ $MODE -eq 0 -o $MODE -eq 1 -o $MODE -eq 6 ]; then sleep 5; else sleep 1; fi

      KPIDS="${PIDV}"
      if [ "${REPLICATION}" -eq 1 ]; then
        KPIDS="${PIDV} ${PIDV_SLAVE}"
      fi
      if [ "${FIREWORKS}" == "1" ]; then  # Terminate mariadbd/mysqld directly in fireworks mode
        ( kill -9 ${KPIDS} >/dev/null 2>&1; ) >/dev/null 2>&1
        sleep 0.02
        while :; do
          if kill -0 ${KPIDS} >/dev/null 2>&1; then
            ( kill -9 ${KPIDS} >/dev/null 2>&1; ) >/dev/null 2>&1
            sleep 1
            if kill -0 ${KPIDS} >/dev/null 2>&1; then echoit "$ATLEASTONCE [Stage $STAGE] [WARNING] Attempting to bring down server(s) with PID(s) ${KPIDS} failed at least twice. Is this server very busy?"; else break; fi
          else
            break
          fi
        done
      else
        # Try various things now to bring server down, upto kill -9
        ADMIN_BIN_TO_USE="${BASEDIR}/bin/mariadb-admin"
        if [ ! -r "${ADMIN_BIN_TO_USE}" ]; then ADMIN_BIN_TO_USE="${BASEDIR}/bin/mysqladmin"; fi
        while :; do
          sleep 1
          if kill -0 ${KPIDS} >/dev/null 2>&1; then
            if [ $MODE -eq 0 -o $MODE -eq 1 -o $MODE -eq 6 ]; then sleep 5; else sleep 2; fi
            if kill -0 ${KPIDS} >/dev/null 2>&1; then  # Retry shutdown one more time
              ${ADMIN_BIN_TO_USE} -uroot -S${WORKD}/socket.sock shutdown >> $WORKD/log/mysqld.out 2>&1
              if [ "${REPLICATION}" -eq 1 ]; then
                ${ADMIN_BIN_TO_USE} -uroot -S${WORKD}/slave_socket.sock shutdown >> $WORKD/log/mysqld_slave.out 2>&1
              fi
              if grep -qiE "Access denied for user|Доступ закрыт для пользователя" $WORKD/log/mysqld*.out; then
                echoit "Assert: Access denied for user detected (ref $WORKD/log/mysqld*.out)"  # If you update the 'Access denied for user detected' here, make sure to update it everwhere else in this script also, especially the grep -qi which checks for this text
                # exit 1  # Ref RV-11/01/2022 note above
              fi
            else
              break
            fi
            if [ $MODE -eq 0 -o $MODE -eq 1 -o $MODE -eq 6 ]; then sleep 5; else sleep 2; fi
            if kill -0 ${KPIDS} >/dev/null 2>&1; then echoit "$ATLEASTONCE [Stage $STAGE] [WARNING] Attempting to bring down server(s) with PID(s) ${KPIDS} failed at least twice. Is this server very busy?"; else break; fi
            sleep 5
            if [ $MODE -ne 1 -a $MODE -ne 6 ]; then
              if [ $MODE -eq 0 ]; then
                if [ $[ $(date +'%s') - ${SHUTDOWN_TIME_START} ] -lt $MODE0_MIN_SHUTDOWN_TIME ]; then
                  continue  # Do not proceed to kill -9 if server is hanging and reducer is checking for the same (i.e. MODE=0) untill we've passed $TIMEOUT_CHECK + 10 second safety margin
                fi
              fi
              if kill -0 ${KPIDS} >/dev/null 2>&1; then
                if [ $MODE -ne 0 ]; then  # For MODE=0, the following is not a WARNING but fairly normal
                  echoit "$ATLEASTONCE [Stage $STAGE] [WARNING] Attempting to bring down server(s) with PID(s) ${KPIDS} failed. Now forcing kill of mariadbd/mysqld"
                fi
                ( kill -9 ${KPIDS} >/dev/null 2>&1; ) >/dev/null 2>&1
              else
                break
              fi
            fi
          else
            break
          fi
        done
        ADMIN_BIN_TO_USE=
      fi
    fi
    KPIDS=
    PIDV=
  fi
  RUN_TIME=$[ ${RUN_TIME} + $(date +'%s') - ${SHUTDOWN_TIME_START} ]  # Add shutdown runtime to overall runtime which is later checked against TIMEOUT_CHECK
}

finish(){
  if [[ ${RR_TRACING} -eq 1 ]]; then
    if [[ ${RR_SAVE_ALL_TRACES} -eq 0 ]]; then
      save_rr_trace "${WORK_BUG_DIR}/rr/${EPOCH}_rr_trace"
      echoit "[Finish] Saved the final RR trace in ${WORK_BUG_DIR}/rr/${EPOCH}_rr_trace"
    else
      echoit "[Finish] RR traces saved in                : ${WORK_BUG_DIR}/rr"
    fi
  fi
  echoit "[Finish] Finalized reducing SQL input file ($INPUTFILE)"
  echoit "[Finish] Number of server startups         : $STARTUPCOUNT (not counting subreducers)"
  echoit "[Finish] Reducer log                       : $WORKD/reducer.log"
  if [ ! -r $WORKO ]; then  # If there was no reduction (i.e. issue was not found), $WORKO was never written
    cp $INPUTFILE $WORK_OUT
    echoit "[Finish] Final testcase                    : $INPUTFILE (= input file; no optimizations were successful. $(wc -l $INPUTFILE | awk '{print $1}') lines)"
  else  # Reduction
    cp -f $WORKO $WORK_OUT
    echoit "[Finish] Final testcase                    : $WORKO ($(wc -l $WORKO | awk '{print $1}') lines)"
  fi
  rm -f $WORK_BUG_DIR/${EPOCH}_bug_bundle.tar.gz
  $(cd $WORK_BUG_DIR; tar -zhcf ${EPOCH}_bug_bundle.tar.gz ${EPOCH}*)
  echoit "[Finish] Final testcase bundle + scripts in: $WORK_BUG_DIR"
  echoit "[Finish] Final testcase for script use     : $WORK_OUT (handy to use in combination with the scripts below)"
  echoit "[Finish] File containing datadir           : $WORK_BASEDIR (All scripts below use this. Update this when basedir changes)"
  echoit "[Finish] Matching data dir init script     : $WORK_INIT (This script will use /dev/shm/${EPOCH} as working directory)"
  echoit "[Finish] Matching startup script           : $WORK_START (Starts mariadbd/mysqld with same options as used in reducer)"
  if [ $MODE -ge 6 ]; then
    # See init_workdir_and_files() and search for WORK_RUN for more info. Also more info in improvements section at top
    echoit "[Finish] Matching run script               : $WORK_RUN (though you can look at this file for an example, implementation for MODE6+ is not finished yet)"
  else
    echoit "[Finish] Matching run script (CLI)         : $WORK_RUN (executes the testcase via the mysql CLI)"
    echoit "[Finish] Matching startup script (pquery)  : $WORK_RUN_PQUERY (executes the testcase via the pquery binary)"
  fi
  echoit "[Finish] Remember; ASAN testcases may need : export ASAN_OPTIONS=quarantine_size_mb=512:atexit=0:detect_invalid_pointer_pairs=3:dump_instruction_bytes=1:abort_on_error=1:allocator_may_return_null=1"
  echoit "[Finish] Remember; UBSAN testcases may need: export UBSAN_OPTIONS=print_stacktrace=1"
  echoit "[Finish] Final testcase bundle tar ball    : ${EPOCH}_bug_bundle.tar.gz (handy for upload to bug reports)"
  echoit "[Finish] Working directory was             : $WORKD"
  if [ "$MULTI_REDUCER" != "1" ]; then  # This is the parent/main reducer
    MYSQLD_OPTIONS_REQUIRED=$(echo "$SPECIAL_MYEXTRA_OPTIONS $MYEXTRA" | sed "s|[ \t]\+| |g;s|--sql_mode=|--sql_mode= |g;s|[ \t]\+| |g")
    if [ "$(echo "$MYSQLD_OPTIONS_REQUIRED" | sed 's| ||g')" != "" ]; then
      echoit "[Finish] mariadbd/mysqld options required for replay: $MYSQLD_OPTIONS_REQUIRED (the testcase will not reproduce the issue without these options passed to mariadbd/mysqld)"
    fi
    if [ "${MYINIT}" == "" ]; then
      echoit "[Finish] mariadbd/mysqld initialization options reqd: $MYINIT (the testcase will not reproduce the issue without these options passed to mariadbd/mysqld initialization)"
    fi
    MYSQLD_OPTIONS_REQUIRED=
    if [ -r $WORKO ]; then  # If there were no issues found, $WORKO was never written
      echoit "[Finish] Final testcase size               : $(stat -c %s $WORKO) bytes ($(wc -l $WORKO | awk '{print $1}') lines)"
    fi
    if [ -r $WORKO ]; then  # If there were no issues found, $WORKO was never written
      echoit "[Info] It is often beneficial to re-run reducer on the output file ($0 $WORKO) to make it smaller still (Reason for this is that certain lines may have been chopped up (think about missing end quotes or semicolons) resulting in non-reproducibility)"
    fi
    copy_workdir_to_tmp
  fi
  if [ "${FIREWORKS}" != "1" ]; then
    if [ ! -r $WORKO ]; then  # If there was no reduction (i.e. issue was not found), $WORKO was never written
      echoit "[DONE] Final testcase: $INPUTFILE (= input file; no optimizations were successful. $(wc -l $INPUTFILE | awk '{print $1}') lines)"
    else  # Reduction
      echoit "[DONE] Final testcase: $WORKO ($(wc -l $WORKO | awk '{print $1}') lines)"
    fi
  fi
  if [ "${1}" == 'abort' ]; then
    echoit "[Abort] Done. Terminating reducer"
    trap SIGINT  # Clear the SIGINT trap
    exit 2
  fi
  exit 0
}

copy_workdir_to_tmp(){
  WORKDIR_COPY_SUCCESS=0
  if [ "${SAVE_RESULTS}" == "1" ]; then
    if [ "$MULTI_REDUCER" != "1" ]; then  # This is the parent/main reducer
      if [ $WORKDIR_LOCATION -eq 1 -o $WORKDIR_LOCATION -eq 2 ]; then
        echoit "[Cleanup] Since tmpfs or ramfs (volatile memory) was used, reducer is now saving a copy of the work directory in /tmp/$EPOCH"
        echoit "[Cleanup] Storing a copy of reducer ($0) and it's original input file ($INPUTFILE) in /tmp/$EPOCH also"
        if [[ $MDG -eq 1 || $GRP_RPL -eq 1 ]]; then
          sudo cp -a $WORKD /tmp/$EPOCH
          sudo chown -R `whoami`:`whoami` /tmp/$EPOCH
          sudo chown -R `whoami` /tmp/$EPOCH  # Google cloud will fail on trying to use groups
          cp $0 /tmp/$EPOCH  # Copy this reducer script
          cp $INPUTFILE /tmp/$EPOCH  # Copy the original input file
        else
          cp -a $WORKD /tmp/$EPOCH
          cp $0 /tmp/$EPOCH  # Copy this reducer script
          cp $INPUTFILE /tmp/$EPOCH  # Copy the original input file
        fi
        # Check if the copy of directories (excluding the socket file,this reducer script,the original input file,and the current still-being-written-to log) is indentical (i.e. no output shown for the diff command)
        DIFF_WORKDIR_COPY="not_empty"
        if [ -d "/tmp/$EPOCH" ]; then
          DIFF_WORKDIR_COPY="$(diff -qr $WORKD /tmp/$EPOCH | grep -vE "is a socket|Only in /tmp/|Files.*dev.*shm.*reducer\.log.*tmp.*reducer\.log differ")"
        fi
        if [ "$DIFF_WORKDIR_COPY" == "" ]; then
          WORKDIR_COPY_SUCCESS=1
          echoit "[Cleanup] Saved copy of work directory (+ the input file, this reducer script, and reducer.log) in /tmp/$EPOCH"
          echoit "[Cleanup] Now deleting temporary work directory $WORKD"
          rm -Rf $WORKD
        else
          echoit "[Non-fatal Error] Reducer tried saving a copy of the working directory ($WORKD), the input file ($INPUTFILE), this reducer ($0) and the reducer log in /tmp/$EPOCH, but on checkup after the copy, differences were found. The diff output was:"
          echoit "$DIFF_WORKDIR_COPY"
          echoit "Please check the diff output, and if necessary that the filesystem on which /tmp is stored is not full and that this script has write rights to /tmp. Note this error is non-fatal; the original work directory ($WORKD) was left, and the inputfile ($INPUTFILE) and this reducer ($0), if necessary, can still be accessed from their original location."
        fi
      fi
    fi
  fi
}

report_linecounts(){
  if [ $MODE -ge 6 ]; then
    if [ "$STAGE" = "V" ]; then
      TXT_OUT="[Init] Initial number of lines in restructured input file(s):"
    else
      TXT_OUT="[Init] Number of lines in input file(s):"
    fi
    TS_LARGEST_WORKF_LINECOUNT=0
    for t in $(eval echo {1..$TS_THREADS}); do
      TS_WORKF_NAME=$(eval echo $(echo '$WORKF'"$t"))
      export TS_LINECOUNTF$t=$(cat $TS_WORKF_NAME | wc -l | tr -d '[\t\n ]*')
      TS_WORKF_LINECOUNT=$(eval echo $(echo '$TS_LINECOUNTF'"$t"))
      TXT_OUT="$TXT_OUT #$t: $TS_WORKF_LINECOUNT"
      if [ $TS_WORKF_LINECOUNT -gt $TS_LARGEST_WORKF_LINECOUNT ]; then TS_LARGEST_WORKF_LINECOUNT=$TS_WORKF_LINECOUNT; fi
    done
    echoit "$TXT_OUT"
  else
    if [ "${FIREWORKS}" != "1" ]; then  # In fireworks mode, we do not use WORKF but INPUTFILE
      LINECOUNTF=$(cat ${WORKF} | wc -l | tr -d '[\t\n ]*')
    else
      LINECOUNTF=$(cat ${INPUTFILE} | wc -l | tr -d '[\t\n ]*')
    fi
    if [ "$STAGE" = "V" ]; then
      echoit "[Init] Initial number of lines in restructured input file: $LINECOUNTF (${INPUTFILE})"
    else
      echoit "[Init] Number of lines in input file: $LINECOUNTF (${INPUTFILE})"
      if [ ${LINECOUNTF} -eq 0 ]; then
        echoit "Assert: Input file empty (0 lines)! Terminating"
        exit 1
      fi
    fi
  fi
  if [ "$STAGE" = "V" ]; then echoit "[Info] Restructured files linecounts are usually higher as INSERT lines are broken up, init SQL is expanded etc."; fi
}

verify_not_found(){
  if [ "$MULTI_REDUCER" != "1" ]; then  # This is the parent - change pathnames to reflect that issue was in a subreducer
    EXTRA_PATH="subreducer/<nr>/"
  else
    EXTRA_PATH=
  fi
  echoit "$ATLEASTONCE [Stage $STAGE] Initial verify of the issue: fail. Bug/issue is not present under given conditions, or is very sporadic. Terminating."
  echoit "[Finish] Verification failed. It may help to check the following files to get an idea as to why this run did not reproduce the issue (if these files do not give any further hints, please check variable/initialization differences, enviroment differences etc. and also reference 'reproducing_and_simplification.txt' in mariadb-qa for many additional reproduction/simplification ideas):"
  WORKDIR_COPY_SUCCESS=0  # Defensive programming, not required (as copy_workdir_to_tmp sets it)
  copy_workdir_to_tmp
  if [ $WORKDIR_COPY_SUCCESS -eq 0 ]; then
    PRINTWORKD="$WORKD"
  else
    PRINTWORKD="/tmp/${EPOCH}"
  fi
  if [ $MODE -ge 6 ]; then
    if [ $TS_DBG_CLI_OUTPUT -eq 1 ]; then
      echoit "[Finish] mysql CLI client output : ${PRINTWORKD}/${EXTRA_PATH}mysql<threadid>.out   (Look for clear signs of non-replay or a terminated connection)"
    else
      echoit "[Finish] mysql CLI client output : not recorded                 (You may want to *TEMPORARY* turn on TS_DBG_CLI_OUTPUT to debug. Ensure to turn it back off before re-testing if the issue exists as it will likely not show with debug on if this is a multi-threaded issue)"
     fi
  else
    if [ $USE_PQUERY -eq 1 ]; then
      echoit "[Finish] pquery client output    : ${PRINTWORKD}/{EXTRA_PATH}default.node.tld_thread-0.sql  (Look for clear signs of non-replay or a terminated connection)"
    else
      echoit "[Finish] mysql CLI client output : ${PRINTWORKD}/${EXTRA_PATH}log/mysql.out             (Look for clear signs of non-replay or a terminated connection)"
    fi
  fi
  if [ $MODE -eq 1 -o $MODE -eq 6 ]; then
    echoit "[Finish] Valgrind output         : ${PRINTWORKD}/${EXTRA_PATH}valgrind.out          (Check if there are really 0 errors)"
  fi
  echoit "[Finish] mariadbd/mysqld error log : ${PRINTWORKD}/${EXTRA_PATH}error.log(.out)       (Check if the mariadbd/mysqld server output looks normal. '.out' = last startup)"
  echoit "[Finish] initialization output   : ${PRINTWORKD}/${EXTRA_PATH}init.log              (Check if the inital server initalization happened correctly)"
  echoit "[Finish] time init output        : ${PRINTWORKD}/${EXTRA_PATH}timezone.init         (Check if the timezone information was installed correctly)"
  exit 1
}

#STAGEV: VERIFY: Check first if the bug/issue exists and is reproducible by reducer
verify(){
  STAGE='V'
  TRIAL=1
  TRIAL_REPEAT_COUNT=0
  echoit "$ATLEASTONCE [Stage $STAGE] Verifying the bug/issue exists and is reproducible by reducer (duration depends on initial input file size)"
  # --init-file: Instead of using an init file, add the init file contents to the top of the testcase, if that still reproduces the issue, below
  ORIGINALMYEXTRA=$MYEXTRA
  INITFILE=
  MYEXTRAWITHOUTINIT=
  if [[ "$MYEXTRA" == *"init_file"* || "$MYEXTRA" == *"init-file"* ]]; then
    INITFILE=$(echo $MYEXTRA | grep -E --binary-files=text -oE "\-\-init[-_]file=[^ ]+" | sed 's|\-\-init[-_]file=||')
    MYEXTRAWITHOUTINIT=$(echo $MYEXTRA | sed 's|\-\-init[-_]file=[^ ]\+||')
  fi
  if [ "$MULTI_REDUCER" != "1" ]; then  # This is the parent/main reducer
    while :; do
      multi_reducer $1  # For the verify stage we should always pass the original input file (ref also dropc init_workdir_and_files())
      if [ "$?" -ge "1" ]; then  # Verify success.
        if [ $MODE -lt 6 ]; then
          # At the moment, MODE6+ does not use initial simplification yet. And, since MODE6+ swaps to MODE1+ after succesfull thread elimination,
          # multi_reducer_decide_input is only skipped when 1) there is a multi-threaded testcase and 2) this testcase could not be reducerd to a single thread
          # This is because (after a succesfull thread elimination process, the verify stage is re-run in a MODE1+)
          # However, for full multi-threaded simplification, reducer needs to do this: thread elimination > DATA thread reducing+SQL. Then, reducer will need
          # to have a VERIFY for the initial simplification of the data thread (and this is how multi-threaded simplification should start)
          multi_reducer_decide_input
        fi
        report_linecounts
        break
      fi
      MULTI_THREADS=$[ ${MULTI_THREADS} + ${MULTI_THREADS_INCREASE} ]
      if [ ${MULTI_THREADS} -gt ${MULTI_THREADS_MAX} ]; then  # Verify failed. Terminate.
        echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] As (possibly sporadic) issue did not reproduce with ${MULTI_THREADS} threads, and as the configured maximum number of threads (${MULTI_THREADS_MAX}) has been reached, now terminating verification"
        verify_not_found
      else
        echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] As (possibly sporadic) issue did not reproduce with $[ ${MULTI_THREADS} - ${MULTI_THREADS_INCREASE} ] threads, now increasing number of threads to ${MULTI_THREADS} (maximum is ${MULTI_THREADS_MAX})"
      fi
      if [ $MULTI_THREADS -ge 35 ]; then
        echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] WARNING: High load active. You may start seeing messages releated to server overload like:"
        echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] WARNING: 'command not found', 'No such file or directory' or 'fork: retry: Resource temporarily unavailable'"
        echoit "$ATLEASTONCE [Stage $STAGE] [${RUNMODE}] WARNING: These can safely be ignored, reducer is trying to see if the issue can be reproduced at all"
      fi
    done
  else  # This is a subreducer: go through normal verification stages
    while :; do
      if [ ! -z "$QCTEXT" ]; then
        REMOVESUFFIX="s/#[NOERROR|ERROR].*//i"
      else
        REMOVESUFFIX="s/;[\t ]*#.*/;/i"
      fi
      if   [ $TRIAL -eq 1 ]; then
        if [ $MODE -ge 6 ]; then
          echoit "$ATLEASTONCE [Stage $STAGE] Verify attempt #1: Maximum initial simplification & DEBUG_SYNC disabled and removed (DEBUG_SYNC may not be necessary)"
          for t in $(eval echo {1..$TS_THREADS}); do
            export TS_WORKF=$(eval echo $(echo '$WORKF'"$t"))
            export TS_WORKT=$(eval echo $(echo '$WORKT'"$t"))
            grep -E --binary-files=text -v "^#|^$|DEBUG_SYNC" $TS_WORKF \
              | sed 's/[\t ]\+/ /g' \
              | sed "s/[ ]*)[ ]*,[ ]*([ ]*/),\n(/g" \
              | sed "s/;\(.*CREATE.*TABLE\)/;\n\1/g" \
              | sed "/CREATE.*TABLE.*;/s/(/(\n/1;/CREATE.*TABLE.*;/s/\(.*\))/\1\n)/;/CREATE.*TABLE.*;/s/,/,\n/g;" \
              | sed 's/ VALUES[ ]*(/ VALUES \n(/g' \
                    -e "s/', '/','/g" > $TS_WORKT
          done
        else
          echoit "$ATLEASTONCE [Stage $STAGE] Verify attempt #1: Maximum initial simplification & cleanup"
          grep -E --binary-files=text -v "^#|^$|DEBUG_SYNC|^\-\-| \[Note\] |====|  WARNING: |^Hope that|^Logging: |\++++| exit with exit status |Lost connection to | valgrind |Using [MSI]|Using dynamic|MySQL Version|\------|TIME \(ms\)$|Skipping ndb|Setting mysqld |Setting mariadbd |Binaries are debug |Killing Possible Leftover|Removing Stale Files|Creating Directories|Installing Master Database|Servers started, |Try: yum|Missing separate debug|SOURCE|CURRENT_TEST|\[ERROR\]|with SSL|_root_|connect to MySQL|No such file|is deprecated at|just omit the defined" $WORKF \
            | sed "$REMOVESUFFIX" \
            | sed 's/[\t ]\+/ /g' \
            | sed 's/Query ([0-9a-fA-F]): \(.*\)/\1;/g' \
            | sed "s/[ ]*)[ ]*,[ ]*([ ]*/),\n(/g" \
            | sed "s/;\(.*CREATE.*TABLE\)/;\n\1/g" \
            | sed "/CREATE.*TABLE.*;/s/(/(\n/1;/CREATE.*TABLE.*;/s/\(.*\))/\1\n)/;/CREATE.*TABLE.*;/s/,/,\n/g;" \
            | sed 's/ VALUES[ ]*(/ VALUES \n(/g' \
                  -e "s/', '/','/g" > $WORKT
          if [ "${INITFILE}" != "" ]; then  # Instead of using an init file, add the init file contents to the top of the testcase
            echoit "$ATLEASTONCE [Stage $STAGE] Adding contents of --init-file directly into testcase and removing --init-file option from MYEXTRA"
            if [ $USE_PQUERY -eq 0 ]; then  # Standard mysql client is used; DROPC can be on a single line
              #Improvement made on 25/01/2021 RV: the original line was seen producing 'ignoring null byte in input'. I am not 100% confident on this change as testing went into the original line construction many years ago. Monitor results over time. This code was also changed elsewhere in reducer.sh, search for 'DROPC can be on a single line'.
              #echo "$(echo "$DROPC";cat $INPUTFILE | grep -E --binary-files=text -v "$DROPC")" > $WORKF
              echo "$DROPC" > $WORKF
              grep -E --binary-files=text -v "$DROPC" $INPUTFILE >> $WORKF
            else  # pquery is used; use a multi-line format for DROPC
              # Clean any DROPC statements from WORKT (similar to the grep -v above but for multiple lines instead)
              remove_dropc $WORKT
              # Re-setup DROPC using multiple lines (ref remove_dropc() for more information) and add the INITFILE
              DROPC_UNIQUE_FILESUFFIX="${RANDOM}${RANDOM}"
              echo "$(echo "$DROPC" | sed 's|;|;\n|g' | grep --binary-files=text -v "^$";cat $INITFILE;cat $WORKT)" > /tmp/WORKT_${DROPC_UNIQUE_FILESUFFIX}.tmp
              rm -f $WORKT
              mv /tmp/WORKT_${DROPC_UNIQUE_FILESUFFIX}.tmp $WORKT
            fi
            MYEXTRA=$MYEXTRAWITHOUTINIT
            echo $MYEXTRA > $WORKD/MYEXTRA
          fi
        fi
      elif [ $TRIAL -eq 2 ]; then
        if [ $MODE -ge 6 ]; then
          echoit "$ATLEASTONCE [Stage $STAGE] Verify attempt #2: Medium initial simplification (CREATE+INSERT lines split) & DEBUG_SYNC disabled and removed"
          for t in $(eval echo {1..$TS_THREADS}); do
            export TS_WORKF=$(eval echo $(echo '$WORKF'"$t"))
            export TS_WORKT=$(eval echo $(echo '$WORKT'"$t"))
            sed "s/[\t ]*)[\t ]*,[\t ]*([\t ]*/),\n(/g" TS_$WORKF \
              | sed "s/;\(.*CREATE.*TABLE\)/;\n\1/g" \
              | sed "/CREATE.*TABLE.*;/s/(/(\n/1;/CREATE.*TABLE.*;/s/\(.*\))/\1\n)/;/CREATE.*TABLE.*;/s/,/,\n/g;" > $TS_WORKT
          done
        else
          echoit "$ATLEASTONCE [Stage $STAGE] Verify attempt #2: High initial simplification & cleanup (no RQG log text removal)"
          grep -E --binary-files=text -v "^#|^$|DEBUG_SYNC|^\-\-" $WORKF \
            | sed "$REMOVESUFFIX" \
            | sed 's/[\t ]\+/ /g' \
            | sed "s/[ ]*)[ ]*,[ ]*([ ]*/),\n(/g" \
            | sed "s/;\(.*CREATE.*TABLE\)/;\n\1/g" \
            | sed "/CREATE.*TABLE.*;/s/(/(\n/1;/CREATE.*TABLE.*;/s/\(.*\))/\1\n)/;/CREATE.*TABLE.*;/s/,/,\n/g;" \
            | sed 's/ VALUES[ ]*(/ VALUES \n(/g' \
                  -e "s/', '/','/g" > $WORKT
          if [ "${INITFILE}" != "" ]; then  # Instead of using an init file, add the init file contents to the top of the testcase
            echoit "$ATLEASTONCE [Stage $STAGE] Adding contents of --init-file directly into testcase and removing --init-file option from MYEXTRA"
            if [ $USE_PQUERY -eq 0 ]; then  # Standard mysql client is used; DROPC can be on a single line
              #Improvement made on 25/01/2021 RV: the original line was seen producing 'ignoring null byte in input'. I am not 100% confident on this change as testing went into the original line construction many years ago. Monitor results over time. This code was also changed elsewhere in reducer.sh, search for 'DROPC can be on a single line'.
              #echo "$(echo "$DROPC";cat $INPUTFILE | grep -E --binary-files=text -v "$DROPC")" > $WORKF
              echo "$DROPC" > $WORKF
              grep -E --binary-files=text -v "$DROPC" $INPUTFILE >> $WORKF
            else  # pquery is used; use a multi-line format for DROPC
              # Clean any DROPC statements from WORKT (similar to the grep -v above but for multiple lines instead)
              remove_dropc $WORKT
              # Re-setup DROPC using multiple lines (ref remove_dropc() for more information) and add the INITFILE
              DROPC_UNIQUE_FILESUFFIX=$RANDOM$RANDOM
              echo "$(echo "$DROPC" | sed 's|;|;\n|g' | grep -v "^$";cat $INITFILE;cat $WORKT)" > /tmp/WORKT_${DROPC_UNIQUE_FILESUFFIX}.tmp
              rm -f $WORKT
              mv /tmp/WORKT_${DROPC_UNIQUE_FILESUFFIX}.tmp $WORKT
            fi
            MYEXTRA=$MYEXTRAWITHOUTINIT
            echo $MYEXTRA > $WORKD/MYEXTRA
          fi
        fi
      elif [ $TRIAL -eq 3 ]; then
        if [ $MODE -ge 6 ]; then
        TS_DEBUG_SYNC_REQUIRED_FLAG=1
        echoit "$ATLEASTONCE [Stage $STAGE] Verify attempt #3: Maximum initial simplification & DEBUG_SYNC enabled"
          for t in $(eval echo {1..$TS_THREADS}); do
            export TS_WORKF=$(eval echo $(echo '$WORKF'"$t"))
            export TS_WORKT=$(eval echo $(echo '$WORKT'"$t"))
            grep -E --binary-files=text -v "^#|^$" $TS_WORKF \
              | sed 's/[\t ]\+/ /g' \
              | sed "s/[ ]*)[ ]*,[ ]*([ ]*/),\n(/g" \
              | sed "s/;\(.*CREATE.*TABLE\)/;\n\1/g" \
              | sed "/CREATE.*TABLE.*;/s/(/(\n/1;/CREATE.*TABLE.*;/s/\(.*\))/\1\n)/;/CREATE.*TABLE.*;/s/,/,\n/g;" \
              | sed 's/ VALUES[ ]*(/ VALUES \n(/g' \
                    -e "s/', '/','/g" > $TS_WORKT
          done
        else
          echoit "$ATLEASTONCE [Stage $STAGE] Verify attempt #3: High initial simplification (no RQG text removal & less cleanup)"
          grep -E --binary-files=text -v "^#|^$|DEBUG_SYNC|^\-\-" $WORKF \
            | sed "$REMOVESUFFIX" \
            | sed "s/[\t ]*)[\t ]*,[\t ]*([\t ]*/),\n(/g" \
            | sed "s/;\(.*CREATE.*TABLE\)/;\n\1/g" \
            | sed "/CREATE.*TABLE.*;/s/(/(\n/1;/CREATE.*TABLE.*;/s/\(.*\))/\1\n)/;/CREATE.*TABLE.*;/s/,/,\n/g;" \
            | sed 's/ VALUES[ ]*(/ VALUES \n(/g' > $WORKT
          if [ "${INITFILE}" != "" ]; then  # Instead of using an init file, add the init file contents to the top of the testcase
            echoit "$ATLEASTONCE [Stage $STAGE] Adding contents of --init-file directly into testcase and removing --init-file option from MYEXTRA"
            if [ $USE_PQUERY -eq 0 ]; then  # Standard mysql client is used; DROPC can be on a single line
              #Improvement made on 25/01/2021 RV: the original line was seen producing 'ignoring null byte in input'. I am not 100% confident on this change as testing went into the original line construction many years ago. Monitor results over time. This code was also changed elsewhere in reducer.sh, search for 'DROPC can be on a single line'.
              #echo "$(echo "$DROPC";cat $INPUTFILE | grep -E --binary-files=text -v "$DROPC")" > $WORKF
              echo "$DROPC" > $WORKF
              grep -E --binary-files=text -v "$DROPC" $INPUTFILE >> $WORKF
            else  # pquery is used; use a multi-line format for DROPC
              # Clean any DROPC statements from WORKT (similar to the grep -v above but for multiple lines instead)
              remove_dropc $WORKT
              # Re-setup DROPC using multiple lines (ref remove_dropc() for more information) and add the INITFILE
              DROPC_UNIQUE_FILESUFFIX=$RANDOM$RANDOM
              echo "$(echo "$DROPC" | sed 's|;|;\n|g' | grep -v "^$";cat $INITFILE;cat $WORKT)" > /tmp/WORKT_${DROPC_UNIQUE_FILESUFFIX}.tmp
              rm -f $WORKT
              mv /tmp/WORKT_${DROPC_UNIQUE_FILESUFFIX}.tmp $WORKT
            fi
            MYEXTRA=$MYEXTRAWITHOUTINIT
            echo $MYEXTRA > $WORKD/MYEXTRA
          fi
        fi
      elif [ $TRIAL -eq 4 ]; then
        if [ $MODE -ge 6 ]; then
          echoit "$ATLEASTONCE [Stage $STAGE] Verify attempt #4: Medium initial simplification (CREATE+INSERT lines split) & DEBUG_SYNC enabled"
          for t in $(eval echo {1..$TS_THREADS}); do
            export TS_WORKF=$(eval echo $(echo '$WORKF'"$t"))
            export TS_WORKT=$(eval echo $(echo '$WORKT'"$t"))
            sed "s/[\t ]*)[\t ]*,[\t ]*([\t ]*/),\n(/g" TS_$WORKF \
              | sed "s/;\(.*CREATE.*TABLE\)/;\n\1/g" \
              | sed "/CREATE.*TABLE.*;/s/(/(\n/1;/CREATE.*TABLE.*;/s/\(.*\))/\1\n)/;/CREATE.*TABLE.*;/s/,/,\n/g;" > $TS_WORKT
          done
        else
          echoit "$ATLEASTONCE [Stage $STAGE] Verify attempt #4: Medium initial simplification (CREATE+INSERT lines split & remove # comments)"
          sed "s/[\t ]*)[\t ]*,[\t ]*([\t ]*/),\n(/g" $WORKF \
            | sed "$REMOVESUFFIX" \
            | sed "s/;\(.*CREATE.*TABLE\)/;\n\1/g" \
            | sed "/CREATE.*TABLE.*;/s/(/(\n/1;/CREATE.*TABLE.*;/s/\(.*\))/\1\n)/;/CREATE.*TABLE.*;/s/,/,\n/g;" > $WORKT
          if [ "${INITFILE}" != "" ]; then  # Instead of using an init file, add the init file contents to the top of the testcase
            echoit "$ATLEASTONCE [Stage $STAGE] Adding contents of --init-file directly into testcase and removing --init-file option from MYEXTRA"
            if [ $USE_PQUERY -eq 0 ]; then  # Standard mysql client is used; DROPC can be on a single line
              #Improvement made on 25/01/2021 RV: the original line was seen producing 'ignoring null byte in input'. I am not 100% confident on this change as testing went into the original line construction many years ago. Monitor results over time. This code was also changed elsewhere in reducer.sh, search for 'DROPC can be on a single line'.
              #echo "$(echo "$DROPC";cat $INPUTFILE | grep -E --binary-files=text -v "$DROPC")" > $WORKF
              echo "$DROPC" > $WORKF
              grep -E --binary-files=text -v "$DROPC" $INPUTFILE >> $WORKF
            else  # pquery is used; use a multi-line format for DROPC
              # Clean any DROPC statements from WORKT (similar to the grep -v above but for multiple lines instead)
              remove_dropc $WORKT
              # Re-setup DROPC using multiple lines (ref remove_dropc() for more information) and add the INITFILE
              DROPC_UNIQUE_FILESUFFIX=$RANDOM$RANDOM
              echo "$(echo "$DROPC" | sed 's|;|;\n|g' | grep -v "^$";cat $INITFILE;cat $WORKT)" > /tmp/WORKT_${DROPC_UNIQUE_FILESUFFIX}.tmp
              rm -f $WORKT
              mv /tmp/WORKT_${DROPC_UNIQUE_FILESUFFIX}.tmp $WORKT
            fi
            MYEXTRA=$MYEXTRAWITHOUTINIT
            echo $MYEXTRA > $WORKD/MYEXTRA
          fi
        fi
      elif [ $TRIAL -eq 5 ]; then
        if [ $MODE -ge 6 ]; then
          echoit "$ATLEASTONCE [Stage $STAGE] Verify attempt #5: Low initial simplification (only main data INSERT lines split) & DEBUG_SYNC enabled"
          for t in $(eval echo {1..$TS_THREADS}); do
            export TS_WORKF=$(eval echo $(echo '$WORKF'"$t"))
            export TS_WORKT=$(eval echo $(echo '$WORKT'"$t"))
            sed "s/[\t ]*)[\t ]*,[\t ]*([\t ]*/),\n(/g" $TS_WORKF > $TS_WORKT
          done
        else
          # The benefit of splitting INSERT lines: example: INSERT (a),(b),(c); becomes INSERT (a),\n(b)\n(c); and thus the seperate line with "b" could be eliminated/simplified.
          # If the testcase then works fine withouth the 'b' elemeneted inserted, it has become simpler. Consider large inserts (100's of rows) and how complexity can be reduced.
          echoit "$ATLEASTONCE [Stage $STAGE] Verify attempt #5: Low initial simplification (only main data INSERT lines split & remove # comments)"
          sed "s/[\t ]*)[\t ]*,[\t ]*([\t ]*/),\n(/g" $WORKF \
            | sed "$REMOVESUFFIX" > $WORKT
          if [ "${INITFILE}" != "" ]; then  # Instead of using an init file, add the init file contents to the top of the testcase
            echoit "$ATLEASTONCE [Stage $STAGE] Adding contents of --init-file directly into testcase and removing --init-file option from MYEXTRA"
            if [ $USE_PQUERY -eq 0 ]; then  # Standard mysql client is used; DROPC can be on a single line
              #Improvement made on 25/01/2021 RV: the original line was seen producing 'ignoring null byte in input'. I am not 100% confident on this change as testing went into the original line construction many years ago. Monitor results over time. This code was also changed elsewhere in reducer.sh, search for 'DROPC can be on a single line'.
              #echo "$(echo "$DROPC";cat $INPUTFILE | grep -E --binary-files=text -v "$DROPC")" > $WORKF
              echo "$DROPC" > $WORKF
              grep -E --binary-files=text -v "$DROPC" $INPUTFILE >> $WORKF
            else  # pquery is used; use a multi-line format for DROPC
              # Clean any DROPC statements from WORKT (similar to the grep -v above but for multiple lines instead)
              remove_dropc $WORKT
              # Re-setup DROPC using multiple lines (ref remove_dropc() for more information) and add the INITFILE
              DROPC_UNIQUE_FILESUFFIX=$RANDOM$RANDOM
              echo "$(echo "$DROPC" | sed 's|;|;\n|g' | grep -v "^$";cat $INITFILE;cat $WORKT)" > /tmp/WORKT_${DROPC_UNIQUE_FILESUFFIX}.tmp
              rm -f $WORKT
              mv /tmp/WORKT_${DROPC_UNIQUE_FILESUFFIX}.tmp $WORKT
            fi
            MYEXTRA=$MYEXTRAWITHOUTINIT
            echo $MYEXTRA > $WORKD/MYEXTRA
          fi
        fi
      elif [ $TRIAL -eq 6 ]; then
        if [ $MODE -ge 6 ]; then
          echoit "$ATLEASTONCE [Stage $STAGE] Verify attempt #6: No initial simplification & DEBUG_SYNC enabled"
          for t in $(eval echo {1..$TS_THREADS}); do
            export TS_WORKF=$(eval echo $(echo '$WORKF'"$t"))
            export TS_WORKT=$(eval echo $(echo '$WORKT'"$t"))
            cp -f $TS_WORKF $TS_WORKT
          done
        else
          echoit "$ATLEASTONCE [Stage $STAGE] Verify attempt #6: No initial simplification"
          echoit "$ATLEASTONCE [Stage $STAGE] Restoring original MYEXTRA and using --init-file exactly as given there originally"
          MYEXTRA=$ORIGINALMYEXTRA
          echo $MYEXTRA > $WORKD/MYEXTRA
          cp -f $WORKF $WORKT
        fi
      else
        verify_not_found
      fi
      run_and_check
      if [ "$?" -eq "1" ]; then  # Verify success, exit loop
        echoit "$ATLEASTONCE [Stage $STAGE] Verify attempt #$TRIAL: Success: Issue detected, saved files"
        report_linecounts
        TRIAL_REPEAT_COUNT=0
        break
      else  # Verify fail, 'while' loop continues (and possibly with repeated trials if NR_OF_TRIAL_REPEATS>1)
        echoit "$ATLEASTONCE [Stage $STAGE] Verify attempt #$TRIAL: Failed: Issue not detected"
        TRIAL_REPEAT_COUNT=$[ ${TRIAL_REPEAT_COUNT} + 1 ]
        if [ ${TRIAL_REPEAT_COUNT} -lt ${NR_OF_TRIAL_REPEATS} ]; then
          echoit "$ATLEASTONCE [Stage $STAGE] Repeating trial (Attempt $[ ${TRIAL_REPEAT_COUNT} + 1 ]/${NR_OF_TRIAL_REPEATS})"
        else
          TRIAL=$[$TRIAL+1]
          TRIAL_REPEAT_COUNT=0
        fi
      fi
    done
  fi
}

fireworks_setup(){
  echoit "[Init] FIREWORKS mode active, so automatically set:"
  echoit "[Init] > USE_PQUERY=1: fireworks mode will use pquery"  # This is not strictly necessary. The CLI could be used also, but pquery is likely faster? Test later. TODO
  USE_PQUERY=1
  echoit "[Init] > USE_NEW_TEXT_STRING=1: fireworks mode will use the new text string script"
  USE_NEW_TEXT_STRING=1
  if [ -z "${FIREWORKS_LINES}" ]; then
    echo "Assert: FIREWORKS mode is active, yet FIREWORKS_LINES is empty. Terminating."
    exit 1
  fi
  if [ ${FIREWORKS_LINES} -lt 10000 ]; then
    echo "[Init] > FIREWORKS_LINES=10000: FIREWORKS_LINES was set to less then 10000, which is unlikely to produce desirable results (minimum)"
    FIREWORKS_LINES=10000
  fi
  PQUERY_MULTI_QUERIES=$[ ${FIREWORKS_LINES} + 1000 ]  # 1000: Arbritary safety buffer addition, likely only about 5 is required (for CREATE DABATASE test; etc.)
  echoit "[Init] > PQUERY_MULTI_QUERIES=${PQUERY_MULTI_QUERIES}: ensures FIREWORKS_LINES (${FIREWORKS_LINES}) queries can be executed"
  if [ "${SCAN_FOR_NEW_BUGS}" != "1" ]; then
    echoit "[Init] > SCAN_FOR_NEW_BUGS=1: enabled new bug scanning (required)"
    SCAN_FOR_NEW_BUGS=1
  fi
  if [ ! -r "${KNOWN_BUGS_LOC}" ]; then
    echoit "[Init] > Failed to read KNOWN_BUGS_LOC file at '${KNOWN_BUGS_LOC}'. Please check. Terminating."
    exit 1
  fi
  if [ -z "${FIREWORKS_TIMEOUT}" ]; then
    echoit "[Init] > FIREWORKS_TIMEOUT is empty (required). Default: 450 (seconds)"
    exit 1
  fi
  if [ "$(echo "${FIREWORKS_TIMEOUT}" | grep -o '[0-9]\+')" != "${FIREWORKS_TIMEOUT}" ]; then
    echoit "[Init] > FIREWORKS_TIMEOUT is non-numeric. Set it to the desired number of seconds. Default: 450"
    exit 1
  fi
  echoit "[Init] > TIMEOUT_COMMAND=\"timeout -k${FIREWORKS_TIMEOUT} -s9 ${FIREWORKS_TIMEOUT}s\": runaway/hanging instances protection"
  TIMEOUT_COMMAND="timeout -k${FIREWORKS_TIMEOUT} -s9 ${FIREWORKS_TIMEOUT}s"
  echoit "[Init] > STAGE1_LINES=-1: Avoid STAGE1 from ever terminating (required)"
  STAGE1_LINES=-1
  echoit "[Init] > MULTI_THREADS=25: If system overload is seen, decrease this in-code (preference)"
  MULTI_THREADS=25  # Setting this to a low number (1-5) will likely not yield great results. If the server supports it you can raise this. For 32 threads, 128GB and /dev/shm resized to 90GB, a good setting is MULTI_THREADS=25 with two reducer.sh scripts running both in fireworks mode, with /dev/shm cleaned out prior to starting them, and provided nothing else is running on the server. Watch out for OOS issues on /dev/shm tmpfs and/or OOM. Note that this setting basically means: x mariadbd/mysqld servers (with one client thread running against it) per reducer started in fireworks mode.
  # Note that MULTI_THREADS_INCREASE and MULTI_THREADS_MAX are of no significance as long as a reasonably lenght input SQL file is used; reducer will never reach this.
  if [ "${PQUERY_REVERSE_NOSHUFFLE_OPT}" != "0" ]; then
    # Requires --no-shuffle option to pquery as reducer (in fireworks mode) will pre-shuffle the in.tmp (i.e. WORKT) file before execution. Using pquery shuffling for this (i.e. without --no-shuffle,  is not the best solution for this, as it requires grabbing the SQL by pquery, whereas if it is pre-shuffled by reducer, issue reproducibility will, presumably, be much more perfect as there is zero post or re-parsing (i.e. the same SQL file can be used again in exactly the same way)
    if [ ${PQUERY_MULTI} -eq 1 ]; then  # If this is 1, then --shuffle is already active and so it needs to be reversed
      echoit "[Init] > PQUERY_REVERSE_NOSHUFFLE_OPT=1: As PQUERY_MULTI was set to 1, we need to ensure pquery shuffling is disabled in favor of in-reducer shuffling (required)"
      PQUERY_REVERSE_NOSHUFFLE_OPT=1
    else  # PQUERY_MULTI is 0, so --no-shuffle is effective if PQUERY_REVERSE_NOSHUFFLE_OPT=0
      echoit "[Init] > PQUERY_REVERSE_NOSHUFFLE_OPT=0: As PQUERY_MULTI was set to 1, we need to ensure pquery shuffling is disabled in favor of in-reducer shuffling (required)"
      PQUERY_REVERSE_NOSHUFFLE_OPT=0
    fi
  fi
  if [ "${FORCE_SKIPV}" != "1" ]; then
    echoit "[Init] > FORCE_SKIPV=1: enabled skipping verify stage (ensures 'free' runs)"
    FORCE_SKIPV=1
  fi
  echoit "[Init] > MODE=3: enabling endless-loop MODE=3 with a dummy unfindable TEXT string"
  MODE=3
  echoit "[Init] > TEXT='fireworksmodeenabled': dummy unfindable TEXT string"
  TEXT='fireworksmodeenabled'
}

#Init
  if [ "${FIREWORKS}" == "1" ]; then
    fireworks_setup
  fi
  set_internal_options  # Should come before options_check
  options_check $1
  init_workdir_and_files
  if [ $MODE -eq 9 ]; then echoit "[Init] Run mode: MODE=9: ThreadSync Crash [ALPHA]"
                           echoit "[Init] Looking for any mariadbd/mysqld crash"; fi
  if [ $MODE -eq 8 ]; then echoit "[Init] Run mode: MODE=8: ThreadSync mariadbd/mysqld error log [ALPHA]"
                           echoit "[Init] Looking for this string: '$TEXT' in mariadbd/mysqld error log output (@ $WORKD/log/*.err when MULTI mode is not active)"; fi
  if [ $MODE -eq 7 ]; then echoit "[Init] Run mode: MODE=7: ThreadSync mysql CLI output [ALPHA]"
                           echoit "[Init] Looking for this string: '$TEXT' in mysql CLI output (@ $WORKD/log/mysql.out when MULTI mode is not active)"; fi
  if [ $MODE -eq 6 ]; then echoit "[Init] Run mode: MODE=6: ThreadSync Valgrind output [ALPHA]"
                           echoit "[Init] Looking for this string: '$TEXT' in Valgrind output (@ $WORKD/valgrind.out when MULTI mode is not active)"; fi
  if [ $MODE -eq 5 ]; then echoit "[Init] Run mode: MODE=5: MTR testcase output"
                           echoit "[Init] Looking for "$MODE5_COUNTTEXT"x this string: '$TEXT' in mysql CLI verbose output (@ $WORKD/log/mysql.out when MULTI mode is not active)"
    if [ "$MODE5_ADDITIONAL_TEXT" != "" -a $MODE5_ADDITIONAL_COUNTTEXT -ge 1 ]; then
                           echoit "[Init] Looking additionally for "$MODE5_ADDITIONAL_COUNTTEXT"x this string: '$MODE5_ADDITIONAL_TEXT' in mysql CLI verbose output (@ $WORKD/log/mysql.out when MULTI mode is not active)"; fi; fi
  if [ $MODE -eq 4 ]; then
    if [ $REDUCE_GLIBC_OR_SS_CRASHES -gt 0 ]; then
                           echoit "[Init] Run mode: MODE=4: GLIBC crash"
                           echoit "[Init] Looking for any GLIBC crash";
    else
                           echoit "[Init] Run mode: MODE=4: Crash"
                           echoit "[Init] Looking for any mariadbd/mysqld crash"; fi; fi
  if [ $MODE -eq 3 ]; then

  if [ "${MODE3_ANY_SIG}" == "1" -a "${USE_NEW_TEXT_STRING}" != "1" ]; then
    echo "Error: MODE3_ANY_SIG is set to 1, yet USE_NEW_TEXT_STRING, which is required for MODE3_ANY_SIG=1, is set to ${USE_NEW_TEXT_STRING}"
    echo "Terminating now."
    exit 1
  fi
    if [ "$PQUERY_CONS_Q_FAIL" -eq 1 ]; then
      echoit "[Init] PQUERY_CONS_Q_FAIL active: MODE set to 3, USE_PQUERY set to 1, USE_NEW_TEXT_STRING set to 0"
      echoit "[Init] PQUERY_CONS_Q_FAIL active: All other issues (crashes/asserts, any TEXT, error log contents etc.) will be ignored"
      echoit "[Init] Run mode: MODE=3 with PQUERY_CONS_Q_FAIL=1: Scanning for '${TEXT}' in the pquery log"
    elif [ $REDUCE_GLIBC_OR_SS_CRASHES -gt 0 ]; then
                           echoit "[Init] Run mode: MODE=3 with REDUCE_GLIBC_OR_SS_CRASHES=1: console typscript log"
                           echoit "[Init] Looking for this string: '$TEXT' in console typscript log output (@ /tmp/reducer_typescript${TYPESCRIPT_UNIQUE_FILESUFFIX}.log)";
    elif [ "${MODE3_ANY_SIG}" == "1" ]; then  # If MODE3_ANY_SIG=1 then USE_NEW_TEXT_STRING=1
                           echoit "[Init] Run mode: MODE=3 with USE_NEW_TEXT_STRING=1 and MODE3_ANY_SIG=1: UniqueID matching using new_text_string.sh"
                           echoit "[Init] Looking for this regex string: '^SIG' in ${TEXT_STRING_LOC} output (@ $WORKD/MYBUG.FOUND when MULTI mode is not active)";
    elif [ $USE_NEW_TEXT_STRING -gt 0 ]; then
      if [ "${FIREWORKS}" != "1" ]; then
                           echoit "[Init] Run mode: MODE=3 with USE_NEW_TEXT_STRING=1: UniqueID matching using new_text_string.sh"
                           echoit "[Init] Looking for this string: '$TEXT' in ${TEXT_STRING_LOC} output (@ $WORKD/MYBUG.FOUND when MULTI mode is not active)";
      else
                           echoit "[Init] Run mode: FireWorks with MODE=3, using new_text_string.sh for UniqueID generation"
      fi
    else
                           echoit "[Init] Run mode: MODE=3: mariadbd/mysqld error log"
                           echoit "[Init] Looking for this string: '$TEXT' in mariadbd/mysqld error log output (@ $WORKD/log/*.err when MULTI mode is not active)"; fi; fi
  if [ $MODE -eq 2 ]; then
    if [ $USE_PQUERY -eq 1 ]; then
                           echoit "[Init] Run mode: MODE=2: pquery client output"
                           echoit "[Init] Looking for this string: '$TEXT' in pquery client output (@ $WORKD/default.node.tld_thread-0.sql when MULTI mode is not active)";
    else
                           echoit "[Init] Run mode: MODE=2: mysql CLI output"
                           echoit "[Init] Looking for this string: '$TEXT' in mysql CLI output (@ $WORKD/log/mysql.out when MULTI mode is not active)"; fi; fi
  if [ $MODE -eq 1 ]; then echoit "[Init] Run mode: MODE=1: Valgrind output"
                           echoit "[Init] Looking for this string: '$TEXT' in Valgrind output (@ $WORKD/valgrind.out when MULTI mode is not active)"; fi
  if [ $MODE -eq 0 ]; then echoit "[Init] Run mode: MODE=0: Timeout/hang/shutdown"
                           echoit "[Init] Looking for trial durations longer then ${TIMEOUT_CHECK_REAL} seconds (with timeout trigger @ ${TIMEOUT_CHECK} seconds)"; fi
  if [ "${FIREWORKS}" != "1" ]; then
    echoit "[Info] Leading [] = No bug/issue found yet, leading [*] = bug/issue at least seen once"
  else
    echoit "[Info] Leading [] = No bug found yet, leading [*] = at least one new previously unknown bug discovered"
  fi
  report_linecounts
  if [ "$SKIPV" != "1" ]; then
    verify $1
    if [ "$MULTI_REDUCER" = "1" ]; then
      # This is a simplfication subreducer started by a parent/main reducer, but only to verify if the issue is reproducible (as SKIPV=0).
      # We terminate now after checking if the issue is yes/no reproducible.
      finish $INPUTFILE
    fi
  fi

#STAGET: TS_THREAD_ELIMINATION: Reduce the number of threads in MODE9 (ThreadSync multi-threaded testcases)
if [ $MODE -ge 6 ]; then
  NEXTACTION="& try removing next thread"
  STAGE=T
  TRIAL=1
  if [ $TS_THREADS -ne 1 ]; then  # If $TS_THREADS = 1 there is only one thread, and thread elimination is not necessary
    echoit "$ATLEASTONCE [Stage $STAGE] ThreadSync thread elimination: removing unncessary threads"
    while :; do
      for t in $(eval echo {1..$TS_THREADS}); do
        export TS_WORKF=$(eval echo $(echo '$WORKF'"$t"))
        export TS_WORKT=$(eval echo $(echo '$WORKT'"$t"))
        cp -f $TS_WORKF $TS_WORKT
      done

      if [ $TRIAL -gt 1 ]; then report_linecounts; fi
      TS_ELIMINATION_THREAD_ID=$[$TS_THREADS+1+$TS_ELIMINATED_THREAD_COUNT-$TRIAL]
      if [ $SPORADIC -eq 0 ]; then
        if   [ $TS_LARGEST_WORKF_LINECOUNT -gt 40000 ]; then TS_TE_ATTEMPTS=1 # Large   case, highly likely not sporadic, try only once to eliminate a thread
        elif [ $TS_LARGEST_WORKF_LINECOUNT -gt 10000 ]; then TS_TE_ATTEMPTS=2 # Medium  case, highly likely not sporadic, try twice to eliminate a thread
        elif [ $TS_LARGEST_WORKF_LINECOUNT -gt  5000 ]; then TS_TE_ATTEMPTS=4 # Small   case, highly likely not sporadic, try 4 times to eliminate a thread
        elif [ $TS_LARGEST_WORKF_LINECOUNT -gt  1000 ]; then TS_TE_ATTEMPTS=6 # Smaller case, highly likely not sporadic, try 6 times to eliminate a thread
        else TS_TE_ATTEMPTS=10                                                # Minimal case, highly likely not sporadic, try 10 times to eliminate a thread
        fi
      else
        if   [ $TS_LARGEST_WORKF_LINECOUNT -gt 40000 ]; then TS_TE_ATTEMPTS=10 # Large   case, established sporadic, try 10 thread elimination attempts
        elif [ $TS_LARGEST_WORKF_LINECOUNT -gt 10000 ]; then TS_TE_ATTEMPTS=13 # Medium  case, established sporadic, try 13 times to eliminate a thread
        elif [ $TS_LARGEST_WORKF_LINECOUNT -gt  5000 ]; then TS_TE_ATTEMPTS=15 # Small   case, established sporadic, try 15 to eliminate a thread
        elif [ $TS_LARGEST_WORKF_LINECOUNT -gt  1000 ]; then TS_TE_ATTEMPTS=15 # Smaller case, established sporadic, try 17 to eliminate a thread
        else TS_TE_ATTEMPTS=20                                                 # Minimal case, established sporadic, try 20 times to eliminate a thread
        fi
      fi
      for a in $(eval echo {1..$TS_TE_ATTEMPTS}); do
        echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [Attempt $a] Trying to eliminate thread $TS_ELIMINATION_THREAD_ID"

        # Single thread elimination (based on reverse order of TRIAL - control thread is normally first)
        export TS_WORKF=$(eval echo $(echo '$WORKF'"$TS_ELIMINATION_THREAD_ID"))
        export TS_WORKT=$(eval echo $(echo '$WORKT'"$TS_ELIMINATION_THREAD_ID"))
        TS_T_THREAD=$(grep -E --binary-files=text "DEBUG_SYNC.*SIGNAL" $TS_WORKF | sed 's/^.*SIGNAL[ ]*//;s/ .*$//g')
        echo "" > $TS_WORKT

        # Update the control thread (remove DEBUG_SYNCs for thread in question)
        if [ -n "$TS_T_THREAD" ]; then  # Don't run this for threads which did not have DEBUG_SYNC text yet (early crash)
                                        # This does leave some unnecessary DEBUG_SYNC info in the control thread, but this will be auto-reduced later
          for t in $(eval echo {1..$TS_THREADS}); do
            export TS_WORKF=$(eval echo $(echo '$WORKF'"$t"))
            export TS_WORKT=$(eval echo $(echo '$WORKT'"$t"))
            if grep -E --binary-files=text -qi "SIGNAL GO_T2" $TS_WORKF; then  # Control thread
              grep -E --binary-files=text -v "DEBUG_SYNC.*$TS_T_THREAD " $TS_WORKF > $TS_WORKT  # do not remove critical end space (T2 == T20 delete otherwise!)
            fi
          done
        fi
        run_and_check
        if [ "$?" -eq "1" ]; then  # Thread elimination success
          echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [Attempt $a] Thread $TS_ELIMINATION_THREAD_ID elimination: Success. Thread $TS_ELIMINATION_THREAD_ID was eliminated and input file(s) were swapped"
          break
        else
          if [ $a -eq $TS_TE_ATTEMPTS ]; then
            echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [Attempt $a] Thread $TS_ELIMINATION_THREAD_ID elimination: Failed. Thread $TS_ELIMINATION_THREAD_ID will be left as-is ftm (will be reduced later)."
          else
            echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [Attempt $a] Thread $TS_ELIMINATION_THREAD_ID elimination: Failed. Re-attempting."
          fi
          # Re-instate TS_WORKT with original contents
          cp -f $TS_WORKF $TS_WORKT
        fi
      done
      TRIAL=$[$TRIAL+1]
      if [ $TRIAL -eq $[$TS_THREADS+1+$TS_ELIMINATED_THREAD_COUNT] ]; then
        echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] Last thread processed. ThreadSync thread elimination complete"
        break
      fi
    done
  fi
  if [ $TS_THREADS -eq 1 ]; then
    echoit "$ATLEASTONCE [Stage $STAGE] [TSE Finish] Only one SQL thread remaining. Merging DATA and SQL thread and swapping to single threaded simplification"
    WORKO="$WORKD/single_out.sql"
    cp -f $TS_DATAINPUTFILE $WORKF
    # We can immediately use thread #1 as TS_init_all_sql_files (from the last run above, or from the original run if there was ever only one thread)
    # has set thread #1 to be the correct remaining thread
    export TS_WORKF=$(eval echo $(echo '$WORKF1')); cat $TS_WORKF >> $WORKF
    cp -f $WORKF $WORKO
    echoit "$ATLEASTONCE [Stage $STAGE] [TSE Finish] Merging complete. Single threaded DATA+SQL file saved as $WORKO"
    if [ $MODE -eq 6 ]; then
      export -n MODE=1
      echoit "$ATLEASTONCE [Stage $STAGE] [TSE Finish] Swapped to standard single-threaded valgrind output testing (MODE1)"
    elif [ $MODE -eq 7 ]; then
      export -n MODE=2
      echoit "$ATLEASTONCE [Stage $STAGE] [TSE Finish] Swapped to standard single-threaded mysql CLI output testing (MODE2)"
    elif [ $MODE -eq 8 ]; then
      export -n MODE=3
      echoit "$ATLEASTONCE [Stage $STAGE] [TSE Finish] Swapped to standard single-threaded mariadbd/mysqld output simplification (MODE3)"
    elif [ $MODE -eq 9 ]; then
      export -n MODE=4
      echoit "$ATLEASTONCE [Stage $STAGE] [TSE Finish] Swapped to standard single-threaded crash simplification (MODE4)"
    fi
    VERIFY=1
    echoit "$ATLEASTONCE [Stage $STAGE] [TSE Finish] Now starting re-verification in $MODE (this enables INSERT splitting in initial simplification etc.)"
    verify $WORKO
  else
    echoit "$ATLEASTONCE [Stage $STAGE] [TSE Finish] More than one thread remaining. Implement multi-threaded simplification here"
    echoit "Terminating now."
    exit 1
  fi
fi

#STAGE1: Reduce large size files fast
if [ "${FIREWORKS}" != "1" ]; then  # In fireworks mode, we do not use WORKF but INPUTFILE
  LINECOUNTF=$(cat ${WORKF} | wc -l | tr -d '[\t\n ]*')
else
  LINECOUNTF=$(cat ${INPUTFILE} | wc -l | tr -d '[\t\n ]*')
fi
if [ $SKIPSTAGEBELOW -lt 1 -a $SKIPSTAGEABOVE -gt 1 ]; then
  if [ "${FIREWORKS}" != "1" ]; then
    NEXTACTION="& try removing next random line(set)"
    STAGE=1
  else
    NEXTACTION="& create next FIREWORKS random lineset"
    STAGE='F'
  fi
  TRIAL=1
  if [ $LINECOUNTF -ge $STAGE1_LINES -o $PQUERY_MULTI -gt 0 -o $FORCE_SKIPV -gt 0 -o $REDUCE_GLIBC_OR_SS_CRASHES -gt 0 ]; then
    if [ "${FIREWORKS}" != "1" ]; then  # FIREWORKS mode will always stay in stage 1, and msg is nonsensical for FW
      echoit "$ATLEASTONCE [Stage $STAGE] Commencing stage $STAGE (trial duration depends on initial input file size)"
    fi
    while [ $LINECOUNTF -ge $STAGE1_LINES ]; do
      if [ $LINECOUNTF -eq $STAGE1_LINES  ]; then NEXTACTION="& Progress to the next stage"; fi
      if [ "${FIREWORKS}" != "1" ]; then echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] Remaining number of lines in input file: $LINECOUNTF"; fi
      if [ "$MULTI_REDUCER" != "1" -a $SPORADIC -eq 1 -a $REDUCE_GLIBC_OR_SS_CRASHES -le 0 ]; then
        # This is the parent/main reducer AND the issue is sporadic (so; need to use multiple threads). Disabled for REDUCE_GLIBC_OR_SS_CRASHES as it is always single-threaded
        if [ "${FIREWORKS}" == "1" ]; then  # FireWorks mode does not use WORKF but INPUTFILE
          multi_reducer ${INPUTFILE}
        else
          multi_reducer ${WORKF}  # $WORKT is not used by the main reducer in this case. The subreducer uses $WORKT it's own session however (in the else below). Also note that the use of $WORKF is necessary due to the dropc code in init_workdir_and_files() - i.e. we need the modified WORKF file, not the original INPUTFILE.
        fi
      else
        if [ "${FIREWORKS}" == "1" ]; then
          cut_fireworks_chunk_and_shuffle
        else
          determine_chunk
          cut_random_chunk
        fi
        run_and_check
      fi
      TRIAL=$[$TRIAL+1]
      if [ "${FIREWORKS}" != "1" ]; then  # In fireworks mode, we do not use WORKF but INPUTFILE
        LINECOUNTF=$(cat ${WORKF} | wc -l | tr -d '[\t\n ]*')
      else
        LINECOUNTF=$(cat ${INPUTFILE} | wc -l | tr -d '[\t\n ]*')
      fi
    done
  else
    echoit "$ATLEASTONCE [Stage $STAGE] Skipping stage $STAGE as remaining number of lines in input file <= $STAGE1_LINES (STAGE1_LINES)"
  fi
fi

#STAGE2: Loop through each line of the remaining file (now max $STAGE1_LINES lines) once
if [ $SKIPSTAGEBELOW -lt 2 -a $SKIPSTAGEABOVE -gt 2 ]; then
  NEXTACTION="& try removing next SQL line"
  STAGE=2
  TRIAL=1
  TRIAL_REPEAT_COUNT=0
  NOISSUEFLOW=0
  CURRENTLINE=1
  echoit "$ATLEASTONCE [Stage $STAGE] Commencing stage $STAGE"
  while :; do
    if [ ${TRIAL} -gt 1 -a "${FIREWORKS}" != "1" ]; then echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] Remaining number of lines in input file: $LINECOUNTF"; fi
    if [ ${CURRENTLINE} -gt ${LINECOUNTF} ]; then
      break  # EOF reached
    elif [ ${CURRENTLINE} -eq ${LINECOUNTF} ]; then
      NEXTACTION="& progress to the next stage"  # Last line
    fi
    echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] Now filtering line ${CURRENTLINE} (Current chunk size: fixed to 1)"
    sed -n "$CURRENTLINE ! p" $WORKF > $WORKT
    while :; do
      run_and_check
      if [ "$?" -ne "1" ]; then  # Issue failed to reproduce, revert (after retrying if applicable, i.e. NR_OF_TRIAL_REPEATS>1)
        TRIAL_REPEAT_COUNT=$[ ${TRIAL_REPEAT_COUNT} + 1 ]
        if [ ${TRIAL_REPEAT_COUNT} -lt ${NR_OF_TRIAL_REPEATS} ]; then
          echoit "$ATLEASTONCE [Stage $STAGE] Repeating trial (Attempt $[ ${TRIAL_REPEAT_COUNT} + 1 ]/${NR_OF_TRIAL_REPEATS})"
          NEXTACTION="& reattempt removing the same SQL line"
          continue;
        else  # Maximum repeats reached and issue failed to reproduce in any of them
          # Only advance the filter line number if there was no issue, otherwise stay on the same line as the file has gotten one line shorter, and so the next line is now the current line! IOW, in "Verify success" below we do not advance the line counter as the next line is now the current line, whereas here we advance by one to jump ahead to the next line whilst leaving the current line which was tested for removal (and could not be removed) intact.
          CURRENTLINE=$[ ${CURRENTLINE} + 1 ];
          NEXTACTION="& try removing next SQL line"
          if [ ${CURRENTLINE} -eq ${LINECOUNTF} ]; then
            NEXTACTION="& progress to the next stage"  # Last line
          fi
          break
        fi
      else  # Verify success
        break;
      fi
    done
    TRIAL_REPEAT_COUNT=0
    if [ "${FIREWORKS}" -eq 1 ]; then  # In fireworks mode, we do not use WORKF but INPUTFILE
      if [ ! -r "${INPUTFILE}" ]; then abort; fi
      SIZEF=$(stat -c %s ${INPUTFILE})
      LINECOUNTF=$(cat ${INPUTFILE} | wc -l | tr -d '[\t\n ]*')
    else
      if [ ! -r "${WORKF}" ]; then abort; fi
      SIZEF=$(stat -c %s ${WORKF})
      LINECOUNTF=$(cat ${WORKF} | wc -l | tr -d '[\t\n ]*')
    fi
    TRIAL=$[$TRIAL+1]
  done
fi

#STAGE3: Execute various cleanup sed's to reduce testcase complexity further. Perform a check if the issue is still present for each replacement (set)
if [ $SKIPSTAGEBELOW -lt 3 -a $SKIPSTAGEABOVE -gt 3 ]; then
  NEXTACTION="& try next testcase complexity reducing sed"
  STAGE=3
  TRIAL=1
  TRIAL_REPEAT_COUNT=0
  if [ ! -r "${WORKF}" ]; then abort; fi
  SIZEF=`stat -c %s $WORKF`
  echoit "$ATLEASTONCE [Stage $STAGE] Commencing stage $STAGE"
  while :; do
    NOSKIP=0

    # The @##@ sed's remove comments like /*! NULL */. Each sed removes one /* */ block per line, so 3 sed's removes 3x /* */ for each line
    if   [ $TRIAL -eq 1  ]; then sed "s/[\t ]*,[ \t]*/,/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 2  ]; then NOSKIP=1; sed "s/\\\"/'/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 3  ]; then sed "s/\\\'//g" $WORKF > $WORKT
    elif [ $TRIAL -eq 4  ]; then sed "s/'[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'/'0000-00-00'/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 5  ]; then sed "s/'[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\.[0-9][0-9][0-9][0-9][0-9][0-9]'/'00:00:00.000000'/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 6  ]; then sed "s/'[-][0-9]*\.[0-9]*'/'0.0'/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 7  ]; then sed "s/'[0-9][0-9]:[0-9][0-9]:[0-9][0-9]'/'00:00:00'/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 8  ]; then sed "s/'[-][0-9]'/'0'/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 9  ]; then sed "s/'[-][0-9]\+'/'0'/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 10 ]; then sed "s/'0'/0/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 11 ]; then sed "s/,[-][0-9],/,0,/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 12 ]; then sed "s/,[-][0-9]\+,/,0,/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 13 ]; then sed "s/'[a-z]'/'a'/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 14 ]; then sed "s/'[a-z]\+'/'a'/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 15 ]; then sed "s/'[A-Z]'/'a'/g"  $WORKF > $WORKT
    elif [ $TRIAL -eq 16 ]; then sed "s/'[A-Z]\+'/'a'/g"  $WORKF > $WORKT
    elif [ $TRIAL -eq 17 ]; then sed -e 's/^[ \t]\+//g' -e 's/[ \t]\+$//g' -e 's/[ \t]\+/ /g' $WORKF > $WORKT
    elif [ $TRIAL -eq 18 ]; then sed -e 's/( /(/g' -e 's/ )/)/g' $WORKF > $WORKT
    elif [ $TRIAL -eq 19 ]; then sed -e 's/\*\//@##@/' -e 's/\/\*.*@##@//' $WORKF > $WORKT
    elif [ $TRIAL -eq 20 ]; then sed -e 's/\*\//@##@/' -e 's/\/\*.*@##@//' $WORKF > $WORKT
    elif [ $TRIAL -eq 21 ]; then sed -e 's/\*\//@##@/' -e 's/\/\*.*@##@//' $WORKF > $WORKT
    elif [ $TRIAL -eq 22 ]; then sed -e 's/ \. /\./g' -e 's/, /,/g' $WORKF > $WORKT
    elif [ $TRIAL -eq 23 ]; then sed -e 's/)[ \t]\+,/),/g' -e 's/)[ \t]\+;/);/g' $WORKF > $WORKT
    elif [ $TRIAL -eq 24 ]; then sed 's/\/\*\(.*\)\*\//\1/' $WORKF > $WORKT
    elif [ $TRIAL -eq 25 ]; then sed 's/field/f/g' $WORKF > $WORKT
    elif [ $TRIAL -eq 26 ]; then sed 's/field/f/gi' $WORKF > $WORKT
    elif [ $TRIAL -eq 27 ]; then sed 's/column/c/g' $WORKF > $WORKT
    elif [ $TRIAL -eq 28 ]; then sed 's/column/c/gi' $WORKF > $WORKT
    elif [ $TRIAL -eq 29 ]; then sed 's/col/c/g' $WORKF > $WORKT
    elif [ $TRIAL -eq 30 ]; then sed 's/col/c/gi' $WORKF > $WORKT
    elif [ $TRIAL -eq 31 ]; then sed 's/view/v/g' $WORKF > $WORKT
    elif [ $TRIAL -eq 32 ]; then sed 's/view\([0-9]\)*/v\1/gi' $WORKF > $WORKT
    elif [ $TRIAL -eq 33 ]; then sed 's/table/t/g' $WORKF > $WORKT
    elif [ $TRIAL -eq 34 ]; then sed 's/table\([0-9]\)*/t\1/gi' $WORKF > $WORKT
    elif [ $TRIAL -eq 35 ]; then sed 's/alias\([0-9]\)*/a\1/gi' $WORKF > $WORKT
    elif [ $TRIAL -eq 36 ]; then sed 's/ \([=<>!]\+\)/\1/gi' $WORKF > $WORKT
    elif [ $TRIAL -eq 37 ]; then sed 's/\([=<>!]\+\) /\1/gi' $WORKF > $WORKT
    elif [ $TRIAL -eq 38 ]; then sed 's/[=<>!]\+/=/gi' $WORKF > $WORKT
    elif [ $TRIAL -eq 39 ]; then sed 's/ .*[=<>!]\+.* / 1=1 /gi' $WORKF > $WORKT
    elif [ $TRIAL -eq 40 ]; then sed 's/([0-9]\+)/(1)/gi' $WORKF > $WORKT
    elif [ $TRIAL -eq 41 ]; then sed 's/([0-9]\+)//gi' $WORKF > $WORKT
    elif [ $TRIAL -eq 42 ]; then sed 's/[ ]\+/ /g' $WORKF > $WORKT
    elif [ $TRIAL -eq 43 ]; then sed 's/^[ ]\+//g' $WORKF > $WORKT
    elif [ $TRIAL -eq 44 ]; then sed 's/[ ]\+$//g' $WORKF > $WORKT
    elif [ $TRIAL -eq 45 ]; then sed 's/transforms\.//gi' $WORKF > $WORKT
    elif [ $TRIAL -eq 46 ]; then sed 's/test\.//gi' $WORKF > $WORKT
    elif [ $TRIAL -eq 47 ]; then sed "s/'[^']\+'/'abcdefghijklmnopqrstuvwxyz'/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 48 ]; then sed "s/'[^']\+'/'abcdefghijklm'/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 49 ]; then sed "s/'[^']\+'/'abcde'/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 50 ]; then sed "s/'[^']\+'/NULL/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 51 ]; then sed "s/NULL,/,/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 52 ]; then sed "s/NULL,/,/" $WORKF > $WORKT  # 1st occurrence only
    elif [ $TRIAL -eq 53 ]; then sed "s/NULL,/,/" $WORKF > $WORKT  # 2nd occurrence only
    elif [ $TRIAL -eq 54 ]; then sed "s/'[^']\+'/'a'/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 55 ]; then sed "s/'[^']\+'/'0'/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 56 ]; then sed "s/'[^']\+'/''/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 57 ]; then sed "s/'[^']\+'/1/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 58 ]; then sed "s/'[^']\+'/0/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 59 ]; then NOSKIP=1; sed "s/$/;/;s/;;$/;/" $WORKF > $WORKT  # Reintroduce end ; everwhere, if lost
    elif [ $TRIAL -eq 60 ]; then sed 's/`//g' $WORKF > $WORKT; NEXTACTION="& progress to the next stage"
    else break
    fi
    if [ ! -r "${WORKT}" ]; then abort; fi
    SIZET=`stat -c %s $WORKT`
    if [ ${NOSKIP} -eq 0 -a $SIZET -ge $SIZEF ]; then
      echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] Skipping this trial as it does not reduce filesize"
      TRIAL=$[$TRIAL+1]
      TRIAL_REPEAT_COUNT=0
    else
      if [ -f $WORKD/log/mysql.out ]; then echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] Remaining size of input file: $SIZEF bytes ($LINECOUNTF lines)"; fi
      run_and_check
      if [ "$?" -ne "1" ]; then  # Issue failed to reproduce, revert (after retrying if applicable, i.e. NR_OF_TRIAL_REPEATS>1)
        TRIAL_REPEAT_COUNT=$[ ${TRIAL_REPEAT_COUNT} + 1 ]
        if [ ${TRIAL_REPEAT_COUNT} -lt ${NR_OF_TRIAL_REPEATS} ]; then
          echoit "$ATLEASTONCE [Stage $STAGE] Repeating trial (Attempt $[ ${TRIAL_REPEAT_COUNT} + 1 ]/${NR_OF_TRIAL_REPEATS})"
          NEXTACTION="& reattempt the same testcase complexity reducing sed"
        else  # Maximum repeats reached and issue failed to reproduce in any of them
          TRIAL=$[$TRIAL+1]
          TRIAL_REPEAT_COUNT=0
          NEXTACTION="& try next testcase complexity reducing sed"
        fi
      else  # Verify success
        TRIAL=$[$TRIAL+1]
        TRIAL_REPEAT_COUNT=0
        NEXTACTION="& try next testcase complexity reducing sed"
      fi
      if [ "${FIREWORKS}" != "1" ]; then  # In fireworks mode, we do not use WORKF but INPUTFILE
        if [ ! -r "${WORKF}" ]; then abort; fi
        SIZEF=$(stat -c %s ${WORKF})
        LINECOUNTF=$(cat ${WORKF} | wc -l | tr -d '[\t\n ]*')
      else
        if [ ! -r "${INPUTFILE}" ]; then abort; fi
        SIZEF=$(stat -c %s ${INPUTFILE})
        LINECOUNTF=$(cat ${INPUTFILE} | wc -l | tr -d '[\t\n ]*')
      fi
    fi
  done
fi

#STAGE4: Execute various query syntax complexity reducing sed's to reduce testcase complexity further. Perform a check if the issue is still present for each replacement (set)
if [ $SKIPSTAGEBELOW -lt 4 -a $SKIPSTAGEABOVE -gt 4 ]; then
  NEXTACTION="& try next query syntax complexity reducing sed"
  STAGE=4
  TRIAL=1
  TRIAL_REPEAT_COUNT=0
  if [ ! -r "${WORKF}" ]; then abort; fi
  SIZEF=`stat -c %s $WORKF`
  echoit "$ATLEASTONCE [Stage $STAGE] Commencing stage $STAGE"
  while :; do
    NOSKIP=0

    # WARNING: ALWAYS, in as far as possible, use double quotes (") for sed as many SQL statements use single quotes, and testcases will often fail to reduce when such single quotes are removed!
    # The @##@ sed's remove comments like /*! NULL */. Each sed removes one /* */ block per line, so 3 sed's removes 3x /* */ for each line
    if   [ $TRIAL -eq 1  ]; then sed "s/IN[ \t]*(.*)/IN (SELECT 1)/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 2  ]; then sed "s/IN[ \t]*(.*)/IN (SELECT 1)/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 3  ]; then sed "s/ON[ \t]*(.*)/ON (1=1)/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 4  ]; then sed "s/ON[ \t]*(.*)/ON (1=1)/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 5  ]; then sed "s/FROM[ \t]*(.*)/FROM (SELECT 1)/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 6  ]; then sed "s/FROM[ \t]*(.*)/FROM (SELECT 1)/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 7  ]; then sed "s/WHERE.*ORDER BY/ORDER BY/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 8  ]; then sed "s/WHERE.*ORDER BY/ORDER BY/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 9  ]; then sed "s/WHERE.*LIMIT/LIMIT/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 10 ]; then sed "s/WHERE.*LIMIT/LIMIT/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 11 ]; then sed "s/WHERE.*GROUP BY/GROUP BY/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 12 ]; then sed "s/WHERE.*GROUP BY/GROUP BY/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 13 ]; then sed "s/WHERE.*HAVING/HAVING/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 14 ]; then sed "s/WHERE.*HAVING/HAVING/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 15 ]; then sed "s/ORDER BY.*WHERE/WHERE/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 16 ]; then sed "s/ORDER BY.*WHERE/WHERE/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 17 ]; then sed "s/ORDER BY.*LIMIT/LIMIT/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 18 ]; then sed "s/ORDER BY.*LIMIT/LIMIT/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 19 ]; then sed "s/ORDER BY.*GROUP BY/GROUP BY/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 20 ]; then sed "s/ORDER BY.*GROUP BY/GROUP BY/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 21 ]; then sed "s/ORDER BY.*HAVING/HAVING/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 22 ]; then sed "s/ORDER BY.*HAVING/HAVING/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 23 ]; then sed "s/LIMIT.*WHERE/WHERE/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 24 ]; then sed "s/LIMIT.*WHERE/WHERE/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 25 ]; then sed "s/LIMIT.*ORDER BY/ORDER BY/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 26 ]; then sed "s/LIMIT.*ORDER BY/ORDER BY/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 27 ]; then sed "s/LIMIT.*GROUP BY/GROUP BY/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 28 ]; then sed "s/LIMIT.*GROUP BY/GROUP BY/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 29 ]; then sed "s/LIMIT.*HAVING/HAVING/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 30 ]; then sed "s/LIMIT.*HAVING/HAVING/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 31 ]; then sed "s/GROUP BY.*WHERE/WHERE/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 32 ]; then sed "s/GROUP BY.*WHERE/WHERE/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 33 ]; then sed "s/GROUP BY.*ORDER BY/ORDER BY/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 34 ]; then sed "s/GROUP BY.*ORDER BY/ORDER BY/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 35 ]; then sed "s/GROUP BY.*LIMIT/LIMIT/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 36 ]; then sed "s/GROUP BY.*LIMIT/LIMIT/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 37 ]; then sed "s/GROUP BY.*HAVING/HAVING/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 38 ]; then sed "s/GROUP BY.*HAVING/HAVING/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 39 ]; then sed "s/HAVING.*WHERE/WHERE/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 40 ]; then sed "s/HAVING.*WHERE/WHERE/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 41 ]; then sed "s/HAVING.*ORDER BY/ORDER BY/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 42 ]; then sed "s/HAVING.*ORDER BY/ORDER BY/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 43 ]; then sed "s/HAVING.*LIMIT/LIMIT/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 44 ]; then sed "s/HAVING.*LIMIT/LIMIT/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 45 ]; then sed "s/HAVING.*GROUP BY/GROUP BY/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 46 ]; then sed "s/HAVING.*GROUP BY/GROUP BY/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 47 ]; then sed "s/LIMIT[[:digit:][:space:][:cntrl:]]*;$/;/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 48 ]; then sed "s/ORDER BY.*;$/;/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 49 ]; then sed "s/GROUP BY.*;$/;/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 50 ]; then sed "s/HAVING.*;$/;/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 51 ]; then sed "s/WHERE.*;$/;/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 52 ]; then sed "s/LIMIT.*;$/;/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 53 ]; then sed "s/GROUP BY.*;$/;/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 54 ]; then sed "s/ORDER BY.*;$/;/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 55 ]; then sed "s/HAVING.*;$/;/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 56 ]; then sed "s/WHERE.*;$/;/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 57 ]; then sed "s/(SELECT 1)/(1)/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 58 ]; then sed "s/ORDER BY \(.*\),\(.*\)/ORDER BY \1/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 59 ]; then sed "s/ORDER BY \(.*\),\(.*\)/ORDER BY \1/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 60 ]; then sed "s/ORDER BY \(.*\),\(.*\)/ORDER BY \1/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 61 ]; then sed "s/ORDER BY \(.*\),\(.*\)/ORDER BY \1/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 62 ]; then sed "s/ORDER BY \(.*\),\(.*\)/ORDER BY \1/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 63 ]; then sed "s/GROUP BY \(.*\),\(.*\)/GROUP BY \1/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 64 ]; then sed "s/GROUP BY \(.*\),\(.*\)/GROUP BY \1/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 65 ]; then sed "s/GROUP BY \(.*\),\(.*\)/GROUP BY \1/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 66 ]; then sed "s/GROUP BY \(.*\),\(.*\)/GROUP BY \1/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 67 ]; then sed "s/GROUP BY \(.*\),\(.*\)/GROUP BY \1/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 68 ]; then sed "s/SELECT \(.*\),\(.*\)/SELECT \1/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 69 ]; then sed "s/SELECT \(.*\),\(.*\)/SELECT \1/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 70 ]; then sed "s/SELECT \(.*\),\(.*\)/SELECT \1/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 71 ]; then sed "s/SELECT \(.*\),\(.*\)/SELECT \1/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 72 ]; then sed "s/SELECT \(.*\),\(.*\)/SELECT \1/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 73 ]; then sed "s/ SET \(.*\),\(.*\)/ SET \1/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 74 ]; then sed "s/ SET \(.*\),\(.*\)/ SET \1/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 75 ]; then sed "s/ SET \(.*\),\(.*\)/ SET \1/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 76 ]; then sed "s/ SET \(.*\),\(.*\)/ SET \1/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 77 ]; then sed "s/ SET \(.*\),\(.*\)/ SET \1/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 78 ]; then sed "s/AND.*IN/IN/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 79 ]; then sed "s/AND.*ON/ON/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 80 ]; then sed "s/AND.*WHERE/WHERE/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 81 ]; then sed "s/AND.*ORDER BY/ORDER BY/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 82 ]; then sed "s/AND.*GROUP BY/GROUP BY/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 83 ]; then sed "s/AND.*LIMIT/LIMIT/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 84 ]; then sed "s/AND.*HAVING/HAVING/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 85 ]; then sed "s/OR.*IN/IN/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 86 ]; then sed "s/OR.*ON/ON/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 87 ]; then sed "s/OR.*WHERE/WHERE/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 88 ]; then sed "s/OR.*ORDER BY/ORDER BY/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 89 ]; then sed "s/OR.*GROUP BY/GROUP BY/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 90 ]; then sed "s/OR.*LIMIT/LIMIT/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 91 ]; then sed "s/OR.*HAVING/HAVING/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 92 ]; then sed "s/ NOT NULL/ /i" $WORKF > $WORKT
    elif [ $TRIAL -eq 93 ]; then sed "s/ NOT NULL/ /gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 94 ]; then sed "s/ NULL/ /i" $WORKF > $WORKT
    elif [ $TRIAL -eq 95 ]; then sed "s/ NULL/ /gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 96 ]; then sed "s/ AUTO_INCREMENT/ /gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 97 ]; then sed "s/ ALGORITHM=MERGE/ /gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 98 ]; then sed "s/ OR REPLACE/ /gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 99 ]; then sed "s/ PRIMARY/ /gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 100 ]; then sed "s/ PRIMARY KEY/ /gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 101 ]; then sed "s/ DEFAULT NULL/ /i" $WORKF > $WORKT
    elif [ $TRIAL -eq 102 ]; then sed "s/ DEFAULT NULL/ /gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 103 ]; then sed "s/ DEFAULT 0/ /i" $WORKF > $WORKT
    elif [ $TRIAL -eq 104 ]; then sed "s/ DEFAULT 0/ /gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 105 ]; then sed "s/ DEFAULT .2038-01-19 03:14:07./ /i" $WORKF > $WORKT
    elif [ $TRIAL -eq 106 ]; then sed "s/ DEFAULT .2038-01-19 03:14:07./ /gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 107 ]; then sed "s/ DEFAULT .1970-01-01 00:00:01./ /i" $WORKF > $WORKT
    elif [ $TRIAL -eq 108 ]; then sed "s/ DEFAULT .1970-01-01 00:00:01./ /gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 109 ]; then sed "s/ DEFAULT CURRENT_TIMESTAMP/ /i" $WORKF > $WORKT
    elif [ $TRIAL -eq 110 ]; then sed "s/ DEFAULT CURRENT_TIMESTAMP/ /gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 111 ]; then sed "s/ ON UPDATE CURRENT_TIMESTAMP/ /i" $WORKF > $WORKT
    elif [ $TRIAL -eq 112 ]; then sed "s/ ON UPDATE CURRENT_TIMESTAMP/ /gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 113 ]; then sed "s/ IF NOT EXISTS / /gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 114 ]; then sed "s/ DISTINCT / /gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 115 ]; then sed "s/ SQL_.*_RESULT / /gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 116 ]; then sed "s/CHARACTER SET[ ]*.*[ ]*COLLATE[ ]*.*\([, ]\)/\1/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 117 ]; then sed "s/CHARACTER SET[ ]*.*\([, ]\)/\1/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 118 ]; then sed "s/COLLATE[ ]*.*\([, ]\)/\1/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 119 ]; then awk '{ for (i=1; i<=NF; ++i) if ($i ~ "^v[0-9]+$") $i = (seen[$i] ? seen[$i] : seen[$i] = "v" ++n) }; 1' $WORKF > $WORKT  # With thanks, https://unix.stackexchange.com/a/702361/241016 (Kusalananda) - simplifies all fuzzer 'v[0-9]+' aliases etc.
    elif [ $TRIAL -eq 120 ]; then sed "s|\(v[0-9]\+\)| \1 |g" $WORKF | awk '{ for (i=1; i<=NF; ++i) if ($i ~ "^v[0-9]+$") $i = (seen[$i] ? seen[$i] : seen[$i] = "v" ++n) }; 1' > $WORKT 
    elif [ $TRIAL -eq 121 ]; then sed "s/DROP DATABASE transforms;CREATE DATABASE transforms;//" $WORKF > $WORKT
    elif [ $TRIAL -eq 122 ]; then sed "s/[a-z0-9]\+_//" $WORKF > $WORKT
    elif [ $TRIAL -eq 123 ]; then sed "s/[a-z0-9]\+_//" $WORKF > $WORKT
    elif [ $TRIAL -eq 124 ]; then sed "s/[a-z0-9]\+_//" $WORKF > $WORKT
    elif [ $TRIAL -eq 125 ]; then sed "s/[a-z0-9]\+_//" $WORKF > $WORKT
    elif [ $TRIAL -eq 126 ]; then sed "s/[a-z0-9]\+_//" $WORKF > $WORKT
    elif [ $TRIAL -eq 127 ]; then sed "s/[0-9]\+\.//" $WORKF > $WORKT
    elif [ $TRIAL -eq 128 ]; then sed "s/\.[0-9]\+//" $WORKF > $WORKT
    elif [ $TRIAL -eq 129 ]; then sed "s/alias/a/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 130 ]; then sed "s/SELECT .* /SELECT * /gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 131 ]; then sed "s/SELECT .* /SELECT * /i" $WORKF > $WORKT
    elif [ $TRIAL -eq 132 ]; then sed "s/SELECT .* /SELECT 1 /gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 133 ]; then sed "s/SELECT .* /SELECT 1 /i" $WORKF > $WORKT
    elif [ $TRIAL -eq 134 ]; then sed -e "s/[\t ]\+/ /g" -e "s/ *\([;,]\)/\1/g" -e "s/ $//g" -e "s/^ //g" $WORKF > $WORKT
    elif [ $TRIAL -eq 135 ]; then sed "s/CHARACTER[ ]*SET[ ]*latin1/ /i" $WORKF > $WORKT
    elif [ $TRIAL -eq 136 ]; then sed "s/CHARACTER[ ]*SET[ ]*utf8/ /i" $WORKF > $WORKT
    elif [ $TRIAL -eq 137 ]; then sed "s/SELECT .* /SELECT 1 /gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 138 ]; then sed "s/COLUMN_FORMAT COMPRESSED/ /i" $WORKF > $WORKT
    elif [ $TRIAL -eq 139 ]; then sed "s/INTEGER/INT/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 140 ]; then sed "s/MAX[ \t]\+[0-9]\+//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 141 ]; then sed "s/MAX[ \t]\+//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 142 ]; then sed "s/NOT NULL//gi" $WORKF > $WORKT  # All
    elif [ $TRIAL -eq 143 ]; then sed "s/NOT NULL//i" $WORKF > $WORKT  # First occurrence only
    elif [ $TRIAL -eq 144 ]; then sed "s/NOT NULL//i" $WORKF > $WORKT  # Second occurrence only
    elif [ $TRIAL -eq 145 ]; then sed "s/NOT NULL//i" $WORKF > $WORKT  # Third occurrence only
    elif [ $TRIAL -eq 146 ]; then sed "s/TEMPORARY//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 147 ]; then sed "s/TEMPORARY//i" $WORKF > $WORKT
    elif [ $TRIAL -eq 148 ]; then sed "s/AUTO_INCREMENT KEY//i" $WORKF > $WORKT
    elif [ $TRIAL -eq 149 ]; then sed "s/AUTO_INCREMENT//i" $WORKF > $WORKT
    elif [ $TRIAL -eq 150 ]; then sed "s/UNIQUE//i" $WORKF > $WORKT
    elif [ $TRIAL -eq 151 ]; then sed "s/IDX/I/" $WORKF > $WORKT
    elif [ $TRIAL -eq 152 ]; then sed "s/ IS NOT NULL / /gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 153 ]; then sed "s/ IS NOT NULL / /i" $WORKF > $WORKT
    elif [ $TRIAL -eq 154 ]; then sed "s/ IS NOT NULL / /i" $WORKF > $WORKT
    elif [ $TRIAL -eq 155 ]; then sed "s/,''/ /g" $WORKF > $WORKT
    elif [ $TRIAL -eq 156 ]; then sed "s/,''/ /" $WORKF > $WORKT
    elif [ $TRIAL -eq 157 ]; then sed "s/,''/ /" $WORKF > $WORKT
    elif [ $TRIAL -eq 158 ]; then sed "s/  / /g" $WORKF > $WORKT
    elif [ $TRIAL -eq 159 ]; then sed "s/( /(/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 160 ]; then sed "s/ )/)/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 161 ]; then sed "s|(SELECT[ \t]\+[^()]\+FROM[ \t]\+\([a-zA-Z0-9_]\+\) )| \1 |gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 162 ]; then sed "s|(SELECT[ \t]\+[^()]\+FROM[ \t]\+\([a-zA-Z0-9_]\+\) )| \1 |i" $WORKF > $WORKT
    elif [ $TRIAL -eq 163 ]; then sed "s|(SELECT[ \t]\+[^()]\+FROM[ \t]\+\([a-zA-Z0-9_]\+\) )| \1 |i" $WORKF > $WORKT
    elif [ $TRIAL -eq 164 ]; then sed "s|(SELECT[ \t]\+[^()]\+FROM[ \t]\+\([^ \t]\+\)[ \t][^()]\+)| \1 |gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 165 ]; then sed "s|(SELECT[ \t]\+[^()]\+FROM[ \t]\+\([^ \t]\+\)[ \t][^()]\+)| \1 |i" $WORKF > $WORKT
    elif [ $TRIAL -eq 166 ]; then sed "s|(SELECT[ \t]\+[^()]\+FROM[ \t]\+\([^ \t]\+\)[ \t][^()]\+)| \1 |i" $WORKF > $WORKT
    elif [ $TRIAL -eq 167 ]; then sed "s|(SELECT[ \t]\+[^()]\+FROM[^()]\+)| 1 |gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 168 ]; then sed "s|(SELECT[ \t]\+[^()]\+FROM[^()]\+)| 1 |i" $WORKF > $WORKT
    elif [ $TRIAL -eq 169 ]; then sed "s|(SELECT[ \t]\+[^()]\+FROM[^()]\+)| 1 |i" $WORKF > $WORKT
    elif [ $TRIAL -eq 170 ]; then sed "s/[0-9]\+/0/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 171 ]; then sed "s/[0-9]\+/1/" $WORKF > $WORKT
    elif [ $TRIAL -eq 172 ]; then sed "s/ -[0-9]\+/ -1/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 173 ]; then sed "s/ -[0-9]\+/ -1/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 174 ]; then sed "s/ -1/ 1/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 175 ]; then sed "s/ [0-9]\+\.[0-9]\+ / 1.0 /" $WORKF > $WORKT
    elif [ $TRIAL -eq 176 ]; then sed "s/ [0-9]\+\.[0-9]\+ / 1 /g" $WORKF > $WORKT
    elif [ $TRIAL -eq 177 ]; then sed "s/[0-9]\+\.[0-9]\+/1.0/" $WORKF > $WORKT
    elif [ $TRIAL -eq 178 ]; then sed "s/[0-9]\+\.[0-9]\+/1/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 179 ]; then sed "s/BETWEEN[^A]\+AND/AND/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 180 ]; then sed "s/BETWEEN[^A]\+AND/AND/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 181 ]; then sed "s/BETWEEN[^A]\+AND/AND/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 182 ]; then sed "s/DESC//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 183 ]; then sed "s/DESC//i" $WORKF > $WORKT
    elif [ $TRIAL -eq 184 ]; then sed "s/ASC//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 185 ]; then sed "s/ASC//i" $WORKF > $WORKT
    elif [ $TRIAL -eq 186 ]; then sed "s/SELECT[^F]\+FROM/SELECT * FROM/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 187 ]; then sed "s/SELECT[^F]\+FROM/SELECT * FROM/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 188 ]; then sed "s/SELECT[^F]\+FROM/SELECT 1 FROM/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 189 ]; then sed "s/SELECT[^F]\+FROM/SELECT 1 FROM/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 190 ]; then sed "s/LEFT/ /gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 191 ]; then sed "s/LEFT/ /g" $WORKF > $WORKT
    elif [ $TRIAL -eq 192 ]; then sed "s/RIGHT/ /gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 193 ]; then sed "s/RIGHT/ /i" $WORKF > $WORKT
    elif [ $TRIAL -eq 194 ]; then sed "s/OUTER/ /gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 195 ]; then sed "s/OUTER/ /i" $WORKF > $WORKT
    elif [ $TRIAL -eq 196 ]; then sed "s/INNER/ /gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 197 ]; then sed "s/INNER/ /g" $WORKF > $WORKT
    elif [ $TRIAL -eq 198 ]; then sed "s/CROSS/ /gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 199 ]; then sed "s/CROSS/ /i" $WORKF > $WORKT
    elif [ $TRIAL -eq 200 ]; then sed "s/NATURAL/ /gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 201 ]; then sed "s/NATURAL/ /i" $WORKF > $WORKT
    elif [ $TRIAL -eq 202 ]; then sed "s/FOLLOWING/ /gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 203 ]; then sed "s/FOLLOWING/ /i" $WORKF > $WORKT
    elif [ $TRIAL -eq 204 ]; then sed "s/BETWEEN[ \t]\+(/BETWEEN(/gi;s/BETWEEN([^)]\+)/BETWEEN 1/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 205 ]; then sed "s/BETWEEN[ \t]\+(/BETWEEN(/i;s/BETWEEN([^)]\+)/BETWEEN 1/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 206 ]; then sed "s/BETWEEN[ \t]\+(/BETWEEN(/gi;s/BETWEEN([^()]\+)/BETWEEN 1/gi" $WORKF > $WORKT  # i.e. single instances, potentially later in the file, which do not have double (())
    elif [ $TRIAL -eq 207 ]; then sed "s/BETWEEN[ \t]\+(/BETWEEN(/i;s/BETWEEN([^()]\+)/BETWEEN 1/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 208 ]; then sed "s/BETWEEN[ \t]\+(/BETWEEN(/i;s/BETWEEN([^)]\+)[^)]\+)/BETWEEN 1/gi" $WORKF > $WORKT  # i.e. double: (())
    elif [ $TRIAL -eq 209 ]; then sed "s/BETWEEN[ \t]\+(/BETWEEN(/i;s/BETWEEN([^)]\+)[^)]\+)/BETWEEN 1/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 210 ]; then sed "s/AS[ \t]\+(/AS(/gi;s/AS([^)]\+)/AS vvv1/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 211 ]; then sed "s/AS[ \t]\+(/AS(/i;s/AS([^)]\+)/AS vvv2/i" $WORKF > $WORKT  # vvv2: defensive coding
    elif [ $TRIAL -eq 212 ]; then sed "s/AS[ \t]\+(/AS(/gi;s/AS([^()]\+)/AS vvv1/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 213 ]; then sed "s/AS[ \t]\+(/AS(/i;s/AS([^()]\+)/AS vvv2/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 214 ]; then sed "s/AS[ \t]\+(/AS(/i;s/AS([^)]\+)[^)]\+)/AS vvv4/i" $WORKF > $WORKT  # i.e. double: (())
    elif [ $TRIAL -eq 215 ]; then sed "s/AS[ \t]\+(/AS(/i;s/AS([^)]\+)[^)]\+)/AS vvv4/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 216 ]; then sed "s/WITH[^)]\+)//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 217 ]; then sed "s/WITH[^)]\+)//i" $WORKF > $WORKT
    elif [ $TRIAL -eq 218 ]; then sed "s/WITH[^)]\+)//i" $WORKF > $WORKT
    elif [ $TRIAL -eq 219 ]; then sed "s/WITH[^*]\+([^()]\+)//gi" $WORKF > $WORKT  # WITH followed by text followed by (
    elif [ $TRIAL -eq 220 ]; then sed "s/WITH[^*]\+([^()]\+)//i" $WORKF > $WORKT
    elif [ $TRIAL -eq 221 ]; then sed "s/WITH[^*]\+([^()]\+)//i" $WORKF > $WORKT
    elif [ $TRIAL -eq 222 ]; then sed "s/WITH[^)]\+)[^)]\+)//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 223 ]; then sed "s/WITH[^)]\+)[^)]\+)//i" $WORKF > $WORKT
    elif [ $TRIAL -eq 224 ]; then sed "s/WITH[^)]\+)[^)]\+)//i" $WORKF > $WORKT
    elif [ $TRIAL -eq 225 ]; then sed "s/(SELECT[^)]\+)/(SELECT 1)/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 226 ]; then sed "s/(SELECT[^)]\+)/(SELECT 1)/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 227 ]; then sed "s/(SELECT[^)]\+)/(SELECT 1)/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 228 ]; then sed "s/(SELECT[^()]\+)/(SELECT 1)/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 229 ]; then sed "s/(SELECT[^()]\+)/(SELECT 1)/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 230 ]; then sed "s/(SELECT[^()]\+)/(SELECT 1)/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 231 ]; then sed "s/(SELECT[^)]\+)[^)]\+)/(SELECT 1)/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 232 ]; then sed "s/(SELECT[^)]\+)[^)]\+)/(SELECT 1)/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 233 ]; then sed "s/(SELECT[^)]\+)[^)]\+)/(SELECT 1)/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 234 ]; then sed "s/(SELECT[^(]\+)/(SELECT (/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 235 ]; then sed "s/(SELECT[^(]\+)/(SELECT (/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 236 ]; then sed "s/(SELECT[^(]\+)/(SELECT (/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 237 ]; then sed "s/(SELECT[^()]\+)/(SELECT (/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 238 ]; then sed "s/(SELECT[^()]\+)/(SELECT (/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 239 ]; then sed "s/(SELECT[^()]\+)/(SELECT (/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 240 ]; then sed "s/(SELECT[^)]\+)/(SELECT 1 FROM t)/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 241 ]; then sed "s/(SELECT[^)]\+)/(SELECT 1 FROM t)/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 242 ]; then sed "s/(SELECT[^)]\+)/(SELECT 1 FROM t1)/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 243 ]; then sed "s/(SELECT[^)]\+)/(SELECT 1 FROM t1)/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 244 ]; then sed "s/(SELECT[^()]\+)/(SELECT 1 FROM t)/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 245 ]; then sed "s/(SELECT[^()]\+)/(SELECT 1 FROM t)/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 246 ]; then sed "s/(SELECT[^()]\+)/(SELECT 1 FROM t1)/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 247 ]; then sed "s/(SELECT[^()]\+)/(SELECT 1 FROM t1)/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 248 ]; then sed "s/(SELECT[^)]\+)[^)]\+)/(SELECT 1 FROM t)/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 249 ]; then sed "s/(SELECT[^)]\+)[^)]\+)/(SELECT 1 FROM t)/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 250 ]; then sed "s/(SELECT[^)]\+)[^)]\+)/(SELECT 1 FROM t1)/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 251 ]; then sed "s/(SELECT[^)]\+)[^)]\+)/(SELECT 1 FROM t1)/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 252 ]; then sed "s/(SELECT[^(]\+)/(SELECT 1 FROM (/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 253 ]; then sed "s/(SELECT[^(]\+)/(SELECT 1 FROM (/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 254 ]; then sed "s/(SELECT[^(]\+)/(SELECT 1 FROM (/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 255 ]; then sed "s/(SELECT[^()]\+)/(SELECT 1 FROM (/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 256 ]; then sed "s/(SELECT[^()]\+)/(SELECT 1 FROM (/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 257 ]; then sed "s/(SELECT[^)]\+)/(SELECT * FROM t)/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 258 ]; then sed "s/(SELECT[^)]\+)/(SELECT * FROM t)/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 259 ]; then sed "s/(SELECT[^)]\+)/(SELECT * FROM t1)/ig" $WORKF > $WORKT
    elif [ $TRIAL -eq 260 ]; then sed "s/(SELECT[^)]\+)/(SELECT * FROM t1)/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 261 ]; then sed "s/(SELECT[^()]\+)/(SELECT * FROM t)/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 262 ]; then sed "s/(SELECT[^()]\+)/(SELECT * FROM t)/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 263 ]; then sed "s/(SELECT[^()]\+)/(SELECT * FROM t1)/ig" $WORKF > $WORKT
    elif [ $TRIAL -eq 264 ]; then sed "s/(SELECT[^()]\+)/(SELECT * FROM t1)/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 265 ]; then sed "s/(SELECT[^)]\+)[^)]\+)/(SELECT * FROM t)/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 266 ]; then sed "s/(SELECT[^)]\+)[^)]\+)/(SELECT * FROM t)/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 267 ]; then sed "s/(SELECT[^)]\+)[^)]\+)/(SELECT * FROM t1)/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 268 ]; then sed "s/(SELECT[^)]\+)[^)]\+)/(SELECT * FROM t1)/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 269 ]; then sed "s/(SELECT[^(]\+)/(SELECT * FROM (/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 270 ]; then sed "s/(SELECT[^(]\+)/(SELECT * FROM (/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 271 ]; then sed "s/(SELECT[^(]\+)/(SELECT * FROM (/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 272 ]; then sed "s/(SELECT[^()]\+)/(SELECT * FROM (/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 273 ]; then sed "s/(SELECT[^()]\+)/(SELECT * FROM (/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 274 ]; then NOSKIP=1; sed "s/$/;/;s/;;$/;/" $WORKF > $WORKT  # Reintroduce end ; everwhere, if lost
    elif [ $TRIAL -eq 275 ]; then sed "s/[- *+%^0-9][- *+%^0-9][- *+%^0-9][- *+%^0-9][- *+%^0-9]\+/ + 1 /gi" $WORKF > $WORKT  # Long math calculations
    elif [ $TRIAL -eq 276 ]; then sed "s/[- *+%^0-9][- *+%^0-9][- *+%^0-9][- *+%^0-9][- *+%^0-9]\+/ + 1 /i" $WORKF > $WORKT 
    elif [ $TRIAL -eq 277 ]; then sed "s/[- *+%^0-9][- *+%^0-9][- *+%^0-9]\+/ + 1 /gi" $WORKF > $WORKT 
    elif [ $TRIAL -eq 278 ]; then sed "s/[- *+%^0-9][- *+%^0-9][- *+%^0-9]\+/ + 1 /i" $WORKF > $WORKT 
    elif [ $TRIAL -eq 279 ]; then sed "s/ + 1 //gi" $WORKF > $WORKT 
    elif [ $TRIAL -eq 280 ]; then sed "s/CONCURRENT//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 281 ]; then sed "s/CONCURRENT//i" $WORKF > $WORKT; NEXTACTION="& progress to the next stage"
    else break
    fi
    if [ ! -r "${WORKT}" ]; then abort; fi
    SIZET=`stat -c %s $WORKT`
    if [ ${NOSKIP} -eq 0 -a $SIZET -ge $SIZEF ]; then
      echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] Skipping this trial as it does not reduce filesize"
      TRIAL=$[$TRIAL+1]
      TRIAL_REPEAT_COUNT=0
    else
      if [ -f $WORKD/log/mysql.out ]; then echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] Remaining size of input file: $SIZEF bytes ($LINECOUNTF lines)"; fi
      run_and_check
      if [ "$?" -ne "1" ]; then  # Issue failed to reproduce, revert (after retrying if applicable, i.e. NR_OF_TRIAL_REPEATS>1)
        TRIAL_REPEAT_COUNT=$[ ${TRIAL_REPEAT_COUNT} + 1 ]
        if [ ${TRIAL_REPEAT_COUNT} -lt ${NR_OF_TRIAL_REPEATS} ]; then
          echoit "$ATLEASTONCE [Stage $STAGE] Repeating trial (Attempt $[ ${TRIAL_REPEAT_COUNT} + 1 ]/${NR_OF_TRIAL_REPEATS})"
          NEXTACTION="& reattempt the same testcase complexity reducing sed"
        else  # Maximum repeats reached and issue failed to reproduce in any of them
          TRIAL=$[$TRIAL+1]
          TRIAL_REPEAT_COUNT=0
          NEXTACTION="& try next query syntax complexity reducing sed"
        fi
      else  # Verify success
        TRIAL=$[$TRIAL+1]
        TRIAL_REPEAT_COUNT=0
        NEXTACTION="& try next query syntax complexity reducing sed"
      fi
      if [ "${FIREWORKS}" != "1" ]; then  # In fireworks mode, we do not use WORKF but INPUTFILE
        if [ ! -r "${WORKF}" ]; then abort; fi
        SIZEF=$(stat -c %s ${WORKF})
        LINECOUNTF=$(cat ${WORKF} | wc -l | tr -d '[\t\n ]*')
      else
        if [ ! -r "${INPUTFILE}" ]; then abort; fi
        SIZEF=$(stat -c %s ${INPUTFILE})
        LINECOUNTF=$(cat ${INPUTFILE} | wc -l | tr -d '[\t\n ]*')
      fi
    fi
  done
fi

#STAGE5: Rename tables and views to generic tx/vx names. This stage is not size bound (i.e. testcase size is not checked per&pre-run to see if the run can be skipped like in some other stages). Performs a check if the issue is still present for each replacement (set).
if [ $SKIPSTAGEBELOW -lt 5 -a $SKIPSTAGEABOVE -gt 5 ]; then
  NEXTACTION="& try next testcase complexity reducing sed"
  STAGE=5
  TRIAL=1
  echoit "$ATLEASTONCE [Stage $STAGE] Commencing stage $STAGE"

  # Change tablenames to tx
  COUNTTABLES=$(grep -E --binary-files=text "CREATE[\t ]*TABLE" $WORKF | wc -l)
  if [ $COUNTTABLES -gt 0 ]; then
    for i in $(eval echo {$COUNTTABLES..1}); do  # Reverse order
      # the '...\n/2' sed is a precaution against multiple CREATE TABLEs on one line (it replaces the second occurrence)
      TABLENAME=$(grep -E --binary-files=text -m$i "CREATE[\t ]*TABLE" $WORKF | tail -n1 | sed 's/CREATE[\t ]*TABLE/\n/2' \
        | head -n1 | sed -e 's/CREATE[\t ]*TABLE[\t ]*\(.*\)[\t ]*(/\1/' -e 's/ .*//1' -e 's/(.*//1')
      sed "s/\([(. ]\)$TABLENAME\([ )]\)/\1 $TABLENAME \2/gi;s/ $TABLENAME / t$i /gi" $WORKF > $WORKT
      if [ "$TABLENAME" = "t$i" ]; then
        echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] Skipping this trial as table $i is already named 't$i' in the file"
      else
        echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] Trying to rename table '$TABLENAME' to 't$i'"
        run_and_check
      fi
      TRIAL=$[$TRIAL+1]
    done
  fi

  # Change viewnames to vx
  COUNTVIEWS=$(grep -E --binary-files=text "CREATE[\t ]*VIEW" $WORKF | wc -l)
  if [ $COUNTVIEWS -gt 0 ]; then
    for i in $(eval echo {$COUNTVIEWS..1}); do  # Reverse order
      # the '...\n/2' sed is a precaution against multiple CREATE VIEWs on one line (it replaces the second occurrence)
      VIEWNAME=$(grep -E --binary-files=text -m$i "CREATE[\t ]*VIEW" $WORKF | tail -n1 | sed 's/CREATE[\t ]*VIEW/\n/2' \
        | head -n1 | sed -e 's/CREATE[\t ]*VIEW[\t ]*\(.*\)[\t ]*(/\1/' -e 's/ .*//1' -e 's/(.*//1')
      sed "s/\([(. ]\)$VIEWNAME\([ )]\)/\1 $VIEWNAME \2/gi;s/ $VIEWNAME / v$i /gi" $WORKF > $WORKT
      if [ "$VIEWNAME" = "v$i" ]; then
        echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] Skipping this trial as view $i is already named 'v$i' in the file"
      else
        echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] Trying to rename view '$VIEWNAME' to 'v$i'"
        run_and_check
      fi
      TRIAL=$[$TRIAL+1]
    done
  fi
fi

#STAGE6: Eliminate columns to reduce testcase complexity further. Perform a check if the issue is still present for each replacement (set).
if [ $SKIPSTAGEBELOW -lt 6 -a $SKIPSTAGEABOVE -gt 6 ]; then
  NEXTACTION="& try and rename this column (if it failed removal) or remove the next column"
  STAGE=6
  TRIAL=1
  if [ ! -r "${WORKF}" ]; then abort; fi
  SIZEF=`stat -c %s $WORKF`
  echoit "$ATLEASTONCE [Stage $STAGE] Commencing stage $STAGE"

  # CREATE TABLE name (...); statements on one line are split to obtain one column per line by the initial verification (STAGE V).
  # And, another situation, CREATE TABLE statements with each column on a new line is the usual RQG output. Both these cases are handled.
  # However, this stage assumes that each column is on a new line. As such, the only unhandled situation is where there is a mix of new lines in
  # the CREATE TABLE statement, which is to be avoided (and is rather unlikely). In such cases, cleanup the testcase manually to have this format:
  # CREATE TABLE name (
  # <col defs, one per line>,    #Note the trailing comma
  # <col defs, one per line>,
  # <key def, one or more per line>
  # ) ENGINE=abc;

  COUNTTABLES=$(grep -E --binary-files=text "CREATE[\t ]*TABLE" $WORKF | wc -l)
  if [ ${COUNTTABLES} -ge 1 ]; then
    for t in $(eval echo {$COUNTTABLES..1}); do  # Reverse order process all tables
      # the '...\n/2' sed is a precaution against multiple CREATE TABLEs on one line (it replaces the second occurrence)
      TABLENAME=$(grep -E --binary-files=text -m$t "CREATE[\t ]*TABLE" $WORKF | tail -n1 | sed 's/CREATE[\t ]*TABLE/\n/2' \
        | head -n1 | sed -e 's/CREATE[\t ]*TABLE[\t ]*\(.*\)[\t ]*(/\1/' -e 's/ .*//1' -e 's/(.*//1')

      # Check if this table ($TABLENAME) is references in aother INSERT..INTO..$TABLENAME2..SELECT..$TABLENAME line.
      # If so, reducer does not need to process this table since it will be processed later when reducer gets to the table $TABLENAME2
      # This is basically an optimization to avoid x (number of columns) unnecessary restarts which will definitely fail:
      # Example: CREATE TABLE t1 (id INT); INSERT INTO t1 VALUES (1); CREATE TABLE t2 (id2 INT): INSERT INTO t2 SELECT * FROM t1;
      # One cannot remove t1.id because t2 has the same number of columns and does a select from t1
      if grep -E --binary-files=text -qi "INSERT.*INTO.*SELECT.*FROM.*$TABLENAME" $WORKF; then
        echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] Skipping column reduction for table '$TABLENAME' as it is present in a INSERT..SELECT..$TABLENAME. This will be/has been reduced elsewhere"
        echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] Will now try and simplify the column names of this table ('$TABLENAME') to more uniform names"
        COLUMN=1
        COLS=$(cat $WORKF | awk "/CREATE.*TABLE.*$TABLENAME/,/;/" | sed 's/^ \+//' | grep -E --binary-files=text -vi "CREATE|ENGINE|^KEY|^PRIMARY|;" | sed 's/ .*$//' | grep -E --binary-files=text -v "\(|\)")
        COUNTCOLS=$(printf "%b\n" "$COLS" | wc -l)
        for COL in $COLS; do
          if [ "$COL" != "c$C_COL_COUNTER" ]; then
            # Try and rename column now to cx to make testcase cleaner
            if [ -f $WORKD/log/mysql.out ]; then echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [Column $COLUMN/$COUNTCOLS] Now attempting to rename column '$COL' to a more uniform 'c$C_COL_COUNTER'"; fi
            sed "s/$COL/c$C_COL_COUNTER/g" $WORKF > $WORKT
            C_COL_COUNTER=$[$C_COL_COUNTER+1]
            run_and_check
            if [ $? -eq 1 ]; then
              # This column was removed, reducing column count
              COUNTCOLS=$[$COUNTCOLS-1]
            fi
            COLUMN=$[$COLUMN+1]
            if [ "${FIREWORKS}" != "1" ]; then  # In fireworks mode, we do not use WORKF but INPUTFILE
              if [ ! -r "${WORKF}" ]; then abort; fi
              SIZEF=$(stat -c %s ${WORKF})
              LINECOUNTF=$(cat ${WORKF} | wc -l | tr -d '[\t\n ]*')
            else
              if [ ! -r "${INPUTFILE}" ]; then abort; fi
              SIZEF=$(stat -c %s ${INPUTFILE})
              LINECOUNTF=$(cat ${INPUTFILE} | wc -l | tr -d '[\t\n ]*')
            fi
          else
            if [ -f $WORKD/log/mysql.out ]; then echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [Column $COLUMN/$COUNTCOLS] Not renaming column '$COL' as it's name is already optimal"; fi
          fi
        done
      else
        NUMOFINVOLVEDTABLES=1

        # Check if there are INSERT..INTO..$TABLENAME..SELECT..$TABLENAME2 lines. If so, fetch $TABLENAME2 etc.
        TEMPTABLENAME=$TABLENAME
        while grep -E --binary-files=text -qi "INSERT.*INTO.*$TEMPTABLENAME.*SELECT" $WORKF; do
          NUMOFINVOLVEDTABLES=$[$NUMOFINVOLVEDTABLES+1]
          # the '...\n/2' sed is a precaution against multiple INSERT INTOs on one line (it replaces the second occurrence)
          export TABLENAME$NUMOFINVOLVEDTABLES=$(grep -E --binary-files=text "INSERT.*INTO.*$TEMPTABLENAME.*SELECT" $WORKF | tail -n1 | sed 's/INSERT.*INTO/\n/2' | head -n1 | sed -e "s/INSERT.*INTO.*$TEMPTABLENAME.*SELECT.*FROM[\t ]*\(.*\)/\1/" -e 's/ //g;s/;//g')
          TEMPTABLENAME=$(eval echo $(echo '$TABLENAME'"$NUMOFINVOLVEDTABLES"))
        done

        COLUMN=1
        COLS=$(cat $WORKF | awk "/CREATE.*TABLE.*$TABLENAME/,/;/" | sed 's/^ \+//' | grep -E --binary-files=text -vi "CREATE|ENGINE|^KEY|^PRIMARY|;" | sed 's/ .*$//' | grep -E --binary-files=text -v "\(|\)")
        COUNTCOLS=$(printf "%b\n" "$COLS" | wc -l)
        # The inner loop below is called for each table (= each trial) and processes all columns for the table in question
        # So the hierarchy is: reducer > STAGE6 > TRIAL x (various tables) > Column y of table x
        for COL in $COLS; do
          echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [Column $COLUMN/$COUNTCOLS] Trying to eliminate column '$COL' in table '$TABLENAME'"

          # Eliminate the column from the correct CREATE TABLE table (this will match the first occurrence of that column name in the correct CREATE TABLE)
          # This sed presumes that each column is on one line, by itself, terminated by a comma (can be improved upon as per the above remark note)
          WORKT2=`echo $WORKT | sed 's/$/.2/'`
          sed "/CREATE.*TABLE.*$TABLENAME/,/^[ ]*$COL.*,/s/^[ ]*$COL.*,//1" $WORKF | grep -E --binary-files=text -v "^$" > $WORKT2  # Remove the column from table defintion
          # Write the testcase with removed column table definition to WORKT as well in case there are no INSERT removals
          # (and hence $WORKT will not be replaced with $WORKT2 anymore below, so reducer does it here as a harmless, but potentially needed, precaution)
          cp -f $WORKT2 $WORKT

          # If present, the script also need to drop the same column from the INSERT for that table, otherwise the testcase will definitely fail (incorrect INSERT)
          # Small limitation 1: ,',', (a comma inside a txt string) is not handled correctly. Column elimination will work, but only upto this occurrence (per table)
          # Small limitation 2: INSERT..INTO..SELECT <specific columns> does not work. SELECT * in such cases is handled. You could manually edit the testcase.

          for c in $(eval echo {1..$NUMOFINVOLVEDTABLES}); do
            if   [ $c -eq 1 ]; then
              # We are now processing any INSERT..INTO..$TABLENAME..VALUES reductions
              # Noth much is required here. In effect, this is what happens here:
              # CREATE TABLE t1 (id INT);
              # INSERT INTO t1 VALUES (1);
              # reducer will try and eliminate "(1)" (after "id" was removed from the table defintion above already)
              # Note that this will also run (due to the for loop) for a NUMOFINVOLVEDTABLES=2+ run - i.e. if an INSERT..INTO..$TABLENAME..SELECT is detected,
              # This run ensures that (see t1/t2 example below) that any additional INSERT INTO t2 VALUES (2) (besides the INSERT SELECT) are covered
              TABLENAME_OLD=$TABLENAME
            elif [ $c -ge 2 ]; then
              # We are now processing any eliminations from other tables to ensure that INSERT..INTO..$TABLENAME..SELECT works for this table
              # We do this by setting TABLENAME to $TABLENAME2 etc. In effect, this is what happens:
              # CREATE TABLE t1 (id INT);
              # INSERT INTO t1 VALUES (1);
              # CREATE TABLE t2 (id2 INT):
              # INSERT INTO t2 SELECT * FROM t1;
              # reducer will try and eliminate "(1)" from table t1 (after "id2" was removed from the table defintion above already)
              # An extra part (see * few lines lower) will ensure that "id" is also removed from t1
              TABLENAME=$(eval echo $(echo '$TABLENAME'"$c"))   # Replace TABLENAME with TABLENAMEx thereby eliminating all "chained" columns
              echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [Column $COLUMN/$COUNTCOLS] INSERT..SELECT into this table from another one detected: removing corresponding column $COLUMN in table '$TABLENAME'"
              WORKT3=`echo $WORKT | sed 's/$/.3/'`
              COL_LINE=$[$(cat $WORKT2 | grep -E --binary-files=text -m1 -n "CREATE.*TABLE.*$TABLENAME" | awk -F":" '{print $1}') + $COLUMN]
              cat $WORKT2 | sed "${COL_LINE}d" > $WORKT3  # (*) Remove the column from the connected table defintion
              cp -f $WORKT3 $WORKT2
              rm $WORKT3
            else
              echo "ASSERT: NUMOFINVOLVEDTABLES!=1||2: $NUMOFINVOLVEDTABLES!=1||2";
              echo "Terminating now."
              exit 1
            fi

            # First count how many actual INSERT rows there are
            COUNTINSERTS=0
            COUNTINSERTS=$(for INSERT in $(cat $WORKT2 | awk "/INSERT.*INTO.*$TABLENAME.*VALUES/,/;/" | \
              sed "s/;/,/;s/^[ ]*(/(\n/;s/)[ ,;]$/\n)/;s/)[ ]*,[ ]*(/\n/g" | \
              grep -E --binary-files=text -v "^[ ]*[\(\)][ ]*$|INSERT"); do \
              echo $INSERT; \
              done | wc -l)

            if [ $COUNTINSERTS -gt 0 ]; then
              # Loop through each line within a single INSERT (ex: INSERT INTO t1 VALUES ('a',1),('b',2);), and through multiple INSERTs (ex: INSERT .. INSERT ..)
              # And each time grab the "between ( and )" information and therein remove the n-th column ($COLUMN) value reducer is trying to remove. Then use a
              # simple sed to replace the old "between ( and )" with the new "between ( and )" which contains one less column (the correct one which removed from
              # the CREATE TABLE statement above also. Then re-test if the issue remains and swap files if this is the case, as usual.
              if [ $c -ge 2 ]; then
                echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [Column $COLUMN/$COUNTCOLS] Also removing $COUNTINSERTS INSERT..VALUES for column $COLUMN in table '$TABLENAME' to match column removal in said table"
              else
                echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [Column $COLUMN/$COUNTCOLS] Removing $COUNTINSERTS INSERT..VALUES for column '$COL' in table '$TABLENAME'"
              fi
              for i in $(eval echo {1..$COUNTINSERTS}); do
                FROM=$(for INSERT in $(cat $WORKT2 | awk "/INSERT.*INTO.*$TABLENAME.*VALUES/,/;/" | \
                  sed "s/;/,/;s/^[ ]*(/(\n/;s/)[ ,;]$/\n)/;s/)[ ]*,[ ]*(/\n/g" | \
                  grep -E --binary-files=text -v "^[ ]*[\(\)][ ]*$|INSERT"); do \
                  echo $INSERT; \
                  done | awk "{if(NR==$i) print "'$1}')

                TO_DONE=0
                TO=$(for INSERT in $(cat $WORKT2 | awk "/INSERT.*INTO.*$TABLENAME.*VALUES/,/;/" | \
                  sed "s/;/,/;s/^[ ]*(/(\n/;s/)[ ,;]$/\n)/;s/)[ ]*,[ ]*(/\n/g" | \
                  grep -E --binary-files=text -v "^[ ]*[\(\)][ ]*$|INSERT"); do \
                  echo $INSERT | tr ',' '\n' | awk "{if(NR!=$COLUMN && $TO_DONE==0) print "'$1}'; echo "==>=="; \
                  done | tr '\n' ',' | sed 's/,==>==/\n/g' | sed 's/^,//' | awk "{if(NR==$i) print "'$1}')
                TO_DONE=1

                # Fix backslash issues (replace \ with \\) like 'you\'ve' - i.e. a single quote within single quoted INSERT values
                # This insures the regex matches in the sed below against the original file: you\'ve > you\\'ve (here) > you\'ve (in the sed)
                FROM=$(echo $FROM | sed 's|\\|\\\\|g')
                TO=$(echo $TO | sed 's|\\|\\\\|g')

                # The actual replacement
                cat $WORKT2 | sed "s/$FROM/$TO/" > $WORKT
                cp -f $WORKT $WORKT2

                #DEBUG
                #echoit "i: |$i|";echoit "from: |$FROM|";echoit "_to_: |$TO|";
              done
            fi
            # DEBUG
            #echoit "c: |$c|";echoit "COUNTINSERTS: |$COUNTINSERTS|";echoit "COLUMN: |$COLUMN|";echoit "diff: $(diff $WORKF $WORKT2)"
            #read -p "pause"

          done
          rm $WORKT2
          TABLENAME=$TABLENAME_OLD

          if [ -f $WORKD/log/mysql.out ]; then echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [Column $COLUMN/$COUNTCOLS] Remaining size of input file: $SIZEF bytes ($LINECOUNTF lines)"; fi
          run_and_check
          if [ $? -eq 0 ]; then
            if [ "$COL" != "c$C_COL_COUNTER" ]; then
              if [ "${FIREWORKS}" != "1" ]; then  # In fireworks mode, we do not use WORKF but INPUTFILE
                if [ ! -r "${WORKF}" ]; then abort; fi
                SIZEF=$(stat -c %s ${WORKF})
                LINECOUNTF=$(cat ${WORKF} | wc -l | tr -d '[\t\n ]*')
              else
                if [ ! -r "${INPUTFILE}" ]; then abort; fi
                SIZEF=$(stat -c %s ${INPUTFILE})
                LINECOUNTF=$(cat ${INPUTFILE} | wc -l | tr -d '[\t\n ]*')
              fi

              # This column was not removed. Try and rename column now to cx to make testcase cleaner
              if [ -f $WORKD/log/mysql.out ]; then echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [Column $COLUMN/$COUNTCOLS] Now attempting to rename this column ('$COL') to a more uniform 'c$C_COL_COUNTER'"; fi
              sed "s/$COL/c$C_COL_COUNTER/g" $WORKF > $WORKT
              C_COL_COUNTER=$[$C_COL_COUNTER+1]
              run_and_check
            else
              if [ -f $WORKD/log/mysql.out ]; then echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] [Column $COLUMN/$COUNTCOLS] Not renaming column '$COL' as it's name is already optimal"; fi
            fi

            # Only advance the column number if there was no issue showing, otherwise stay on the same column (If the issue does show,
            # the script will remove the current column and shift all other columns down by one, hence it has to stay in the same
            # place as this will contain the next column)
            COLUMN=$[$COLUMN+1]
          else
            # This column was removed, reducing column count
            COUNTCOLS=$[$COUNTCOLS-1]
          fi
          if [ "${FIREWORKS}" != "1" ]; then  # In fireworks mode, we do not use WORKF but INPUTFILE
            if [ ! -r "${WORKF}" ]; then abort; fi
            SIZEF=$(stat -c %s ${WORKF})
            LINECOUNTF=$(cat ${WORKF} | wc -l | tr -d '[\t\n ]*')
          else
            if [ ! -r "${INPUTFILE}" ]; then abort; fi
            SIZEF=$(stat -c %s ${INPUTFILE})
            LINECOUNTF=$(cat ${INPUTFILE} | wc -l | tr -d '[\t\n ]*')
          fi
        done
      fi
      TRIAL=$[$TRIAL+1]
    done
  fi
fi

#STAGE7: Execute various final testcase cleanup sed's. Perform a check if the issue is still present for each replacement (set)
if [ $SKIPSTAGEBELOW -lt 7 -a $SKIPSTAGEABOVE -gt 7 ]; then
  NEXTACTION="& try next testcase complexity reducing sed"
  STAGE=7
  TRIAL=1
  TRIAL_REPEAT_COUNT=0
  if [ ! -r "${WORKF}" ]; then abort; fi
  SIZEF=`stat -c %s $WORKF`
  echoit "$ATLEASTONCE [Stage $STAGE] Commencing stage $STAGE"
  while :; do
    NOSKIP=0

    # WARNING: ALWAYS, in as far as possible, use double quotes (") for sed as many SQL statements use single quotes, and testcases will often fail to reduce when such single quotes are removed!
    if   [ $TRIAL -eq 1   ]; then sed "s/[\t]\+/ /g" $WORKF > $WORKT
    elif [ $TRIAL -eq 2   ]; then sed "s/[ ]\+/ /g" $WORKF > $WORKT
    elif [ $TRIAL -eq 3   ]; then sed "s/[ ]*,/,/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 4   ]; then sed "s/,[ ]*/,/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 5   ]; then sed "s/[ ]*;[ ]*/;/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 6   ]; then sed -e "s/^[ ]*//g" -e "s/[ ]*$//g" $WORKF > $WORKT
    elif [ $TRIAL -eq 7   ]; then sed "s/GRANDPARENT/gp/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 8   ]; then sed "s/PARENT/p/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 9   ]; then sed "s/CHILD/c/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 10  ]; then sed "s/\([(,]\)[ ]*'a'[ ]*/\1''/g;s/[ ]*'a'[ ]*\([,)]\)/''\1/g" $WORKF > $WORKT  # Simplify INSERT VALUES
    elif [ $TRIAL -eq 11  ]; then sed "s/\([(,]\)[ ]*''[ ]*/\1/g;s/[ ]*''[ ]*\([,)]\)/\1/g" $WORKF > $WORKT  # Try and elimiante ''
    elif [ $TRIAL -eq 12  ]; then sed "s/\([(,]\)[ ]*'[a-z]'[ ]*/\1''/g;s/[ ]*'[a-z]'[ ]*\([,)]\)/''\1/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 13  ]; then sed "s/\([(,]\)[ ]*'[A-Z]'[ ]*/\1''/g;s/[ ]*'[A-Z]'[ ]*\([,)]\)/''\1/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 14  ]; then sed "s/\([(,]\)[ ]*'[a-zA-Z]'[ ]*/\1''/g;s/[ ]*'[a-zA-Z]'[ ]*\([,)]\)/''\1/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 15  ]; then sed "s/\([(,]\)[ ]*'[a-z]*'[ ]*/\1''/g;s/[ ]*'[a-z]*'[ ]*\([,)]\)/''\1/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 16  ]; then sed "s/\([(,]\)[ ]*'[A-Z]*'[ ]*/\1''/g;s/[ ]*'[A-Z]*'[ ]*\([,)]\)/''\1/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 17  ]; then sed "s/\([(,]\)[ ]*'[a-zA-Z]*'[ ]*/\1''/g;s/[ ]*'[a-zA-Z]*'[ ]*\([,)]\)/''\1/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 18  ]; then sed "s/\([(,]\)[ ]*''[ ]*/\1/g;s/[ ]*''[ ]*\([,)]\)/\1/g" $WORKF > $WORKT  # Try and elimiante '' again now
    elif [ $TRIAL -eq 19  ]; then sed "s/([ ]*[0-9][ ]*,/(0,/g;s/,[ ]*[0-9][ ]*,/,0,/g;s/,[ ]*[0-9][ ]*)/,0)/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 20  ]; then sed "s/([ ]*[0-9]*[ ]*,/(0,/g;s/,[ ]*[0-9]*[ ]*,/,0,/g;s/,[ ]*[0-9]*[ ]*)/,0)/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 21  ]; then sed "s/([ ]*NULL[ ]*,/(1,/g;s/,[ ]*NULL[ ]*,/,1,/g;s/,[ ]*NULL[ ]*)/,1)/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 22  ]; then sed "s/([ ]*NULL[ ]*,/(0,/g;s/,[ ]*NULL[ ]*,/,0,/g;s/,[ ]*NULL[ ]*)/,0)/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 23  ]; then sed "s/([ ]*NULL[ ]*,/('',/g;s/,[ ]*NULL[ ]*,/,'',/g;s/,[ ]*NULL[ ]*)/,'')/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 24  ]; then sed "s/\([(,]\)[ ]*''[ ]*/\1/g;s/[ ]*''[ ]*\([,)]\)/\1/g" $WORKF > $WORKT  # Try and elimiante '' again now
    elif [ $TRIAL -eq 25  ]; then sed "s/\([(,]\)[ ]*'[0-9]'[ ]*/\1''/g;s/[ ]*'[0-9]'[ ]*\([,)]\)/''\1/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 26  ]; then sed "s/\([(,]\)[ ]*'[0-9]*'[ ]*/\1''/g;s/[ ]*'[0-9]*'[ ]*\([,)]\)/''\1/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 27  ]; then sed "s/\([(,]\)[ ]*'[-0-9]*'[ ]*/\1''/g;s/[ ]*'[-0-9]*'[ ]*\([,)]\)/''\1/g" $WORKF > $WORKT  # Date
    elif [ $TRIAL -eq 28  ]; then sed "s/\([(,]\)[ ]*'[:0-9]*'[ ]*/\1''/g;s/[ ]*'[:0-9]*'[ ]*\([,)]\)/''\1/g" $WORKF > $WORKT  # Time
    elif [ $TRIAL -eq 29  ]; then sed "s/\([(,]\)[ ]*'[:.0-9]*'[ ]*/\1''/g;s/[ ]*'[:.0-9]*'[ ]*\([,)]\)/''\1/g" $WORKF > $WORKT  # Time, FSP
    elif [ $TRIAL -eq 30  ]; then sed "s/\([(,]\)[ ]*'[-: 0-9]*'[ ]*/\1''/g;s/[ ]*'[-: 0-9]*'[ ]*\([,)]\)/''\1/g" $WORKF > $WORKT  # Datetime
    elif [ $TRIAL -eq 31  ]; then sed "s/\([(,]\)[ ]*'[-.: 0-9]*'[ ]*/\1''/g;s/[ ]*'[-.: 0-9]*'[ ]*\([,)]\)/''\1/g" $WORKF > $WORKT  # Dt, FSP
    elif [ $TRIAL -eq 32  ]; then sed "s/\([(,]\)[ ]*''[ ]*/\1/g;s/[ ]*''[ ]*\([,)]\)/\1/g" $WORKF > $WORKT  # Try and elimiante '' again now
    elif [ $TRIAL -eq 33  ]; then sed "s/[ ]*'[a-z]'[ ]*/''/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 34  ]; then sed "s/[ ]*'[A-Z]'[ ]*/''/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 35  ]; then sed "s/[ ]*'[a-zA-Z]'[ ]*/''/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 36  ]; then sed "s/[ ]*'[a-z]*'[ ]*/''/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 37  ]; then sed "s/[ ]*'[A-Z]*'[ ]*/''/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 38  ]; then sed "s/[ ]*'[a-zA-Z]*'[ ]*/''/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 39  ]; then sed "s/[ ]*[0-9][ ]*/0/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 40  ]; then sed "s/[ ]*[0-9]*[ ]*/0/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 41  ]; then sed "s/[ ]*NULL[ ]*//g" $WORKF > $WORKT
    elif [ $TRIAL -eq 42  ]; then sed "s/[ ]*NULL[ ]*/0/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 43  ]; then sed "s/[ ]*NULL[ ]*/''/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 44  ]; then sed "s/[ ]*'[0-9]'[ ]*/''/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 45  ]; then sed "s/[ ]*'[0-9]*'[ ]*/''/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 46  ]; then sed "s/[0-9]/0/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 47  ]; then sed "s/[0-9]\+/0/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 48  ]; then sed "s/[ ]*AUTO_INCREMENT=[0-9]*//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 49  ]; then sed "s/[ ]*AUTO_INCREMENT[ ]*,/,/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 50  ]; then sed "s/PRIMARY[ ]*KEY.*,//g" $WORKF > $WORKT
         # TODO: add situation where PRIMARY KEY is last column (i.e. remove comma on preceding line)
    elif [ $TRIAL -eq 51  ]; then sed "s/PRIMARY[ ]*KEY[ ]*(\(.*\))/KEY (\1)/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 52  ]; then sed "s/KEY[ ]*(\(.*\),.*)/KEY(\1)/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 53  ]; then sed "s/INNR/I/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 54  ]; then sed "s/OUTR/O/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 55  ]; then sed "s/,LOAD_FILE('[A-Za-z0-9\/.]*'),/,'',/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 56  ]; then sed "s/_tinyint/ti/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 57  ]; then sed "s/_smallint/si/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 58  ]; then sed "s/_mediumint/mi/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 59  ]; then sed "s/_bigint/bi/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 60  ]; then sed "s/_int/i/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 61  ]; then sed "s/_decimal/dc/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 62  ]; then sed "s/_float/f/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 63  ]; then sed "s/_bit/bi/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 64  ]; then sed "s/_double/do/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 65  ]; then sed "s/_nokey/nk/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 66  ]; then sed "s/_key/k/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 67  ]; then sed "s/_varchar/vc/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 68  ]; then sed "s/_char/c/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 69  ]; then sed "s/_datetime/dt/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 70  ]; then sed "s/_date/d/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 71  ]; then sed "s/_time/t/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 72  ]; then sed "s/_timestamp/ts/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 73  ]; then sed "s/_year/y/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 74  ]; then sed "s/_blob/b/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 75  ]; then sed "s/_tinyblob/tb/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 76  ]; then sed "s/_mediumblob/mb/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 77  ]; then sed "s/_longblob/lb/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 78  ]; then sed "s/_text/te/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 79  ]; then sed "s/_tinytext/tt/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 80  ]; then sed "s/_mediumtext/mt/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 81  ]; then sed "s/_longtext/lt/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 82  ]; then sed "s/_binary/bn/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 83  ]; then sed "s/_varbinary/vb/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 84  ]; then sed "s/_enum/e/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 85  ]; then sed "s/_set/s/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 86  ]; then sed "s/_not/n/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 87  ]; then sed "s/_null/nu/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 88  ]; then sed "s/_latin1/l/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 89  ]; then sed "s/_utf8/u/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 90  ]; then sed -e "s/;[ ]*;/;/g" -e "s/[ ]*,[ ]*/,/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 91  ]; then sed "s/VARCHAR[ ]*(\(.*\))/CHAR (\1)/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 92  ]; then sed "s/VARBINARY[ ]*(\(.*\))/BINARY (\1)/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 93  ]; then sed "s/DATETIME/DATE/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 94  ]; then sed "s/TIME/DATE/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 95  ]; then sed "s/TINYBLOB/BLOB/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 96  ]; then sed "s/MEDIUMBLOB/BLOB/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 97  ]; then sed "s/LONGBLOB/BLOB/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 98  ]; then sed "s/TINYTEXT/TEXT/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 99  ]; then sed "s/MEDIUMTEXT/TEXT/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 100 ]; then sed "s/LONGTEXT/TEXT/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 101 ]; then sed "s/INTEGER/INT/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 102 ]; then sed "s/TINYINT/INT/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 103 ]; then sed "s/SMALLINT/INT/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 104 ]; then sed "s/MEDIUMINT/INT/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 105 ]; then sed "s/BIGINT/INT/gi;" $WORKF > $WORKT
    elif [ $TRIAL -eq 106 ]; then sed "s/BOOLEAN/INT/gi;" $WORKF > $WORKT
    elif [ $TRIAL -eq 107 ]; then sed "s/NUMERIC/INT/gi;" $WORKF > $WORKT
    elif [ $TRIAL -eq 108 ]; then sed "s/SERIAL/INT/gi;" $WORKF > $WORKT
    elif [ $TRIAL -eq 109 ]; then sed "s/WHERE[ ]*(\(.*\),.*)/WHERE (\1)/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 110 ]; then sed "s/\\\'[0-9a-zA-Z]\\\'/0/g" $WORKF > $WORKT  # \'c\' in PS matching
    elif [ $TRIAL -eq 111 ]; then sed "s/\\\'[0-9a-zA-Z]\\\'/1/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 112 ]; then sed "s/\\\'[0-9a-zA-Z]*\\\'/0/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 113 ]; then sed "s/\\\'[0-9a-zA-Z]*\\\'/1/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 114 ]; then sed "s/\\\'[0-9a-zA-Z]*\\\'/\\\'\\\'/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 115 ]; then sed "s/<>/=/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 116 ]; then sed "s/([ ]*(/((/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 117 ]; then sed "s/)[ ]*)/))/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 118 ]; then sed "s/([ ]*/(/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 119 ]; then sed "s/[ ]*)/)/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 120 ]; then sed "s/ prep_stmt_[0-9]*/ p1/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 121 ]; then sed "/INSERT[ ]*INTO/,/)/{s/INSERT[ ]*INTO[ ]*\(.*\)[ ]*(/INSERT INTO \1/p;d}" $WORKF > $WORKT
    elif [ $TRIAL -eq 122 ]; then sed "s/QUICK //gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 123 ]; then sed "s/LOW_PRIORITY //gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 124 ]; then sed "s/IGNORE //gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 125 ]; then sed "s/enum[ ]*('[a-zA-Z0-9]*','[a-zA-Z0-9]*','[a-zA-Z0-9]*','[a-zA-Z0-9]*','[a-zA-Z0-9]*',/ENUM('','','','','',/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 126 ]; then sed "s/enum[ ]*('[a-zA-Z0-9]*','[a-zA-Z0-9]*','[a-zA-Z0-9]*','[a-zA-Z0-9]*','[a-zA-Z0-9]*',/ENUM('','','','','',/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 127 ]; then sed "s/enum[ ]*('[a-zA-Z0-9]*','[a-zA-Z0-9]*','[a-zA-Z0-9]*','[a-zA-Z0-9]*','[a-zA-Z0-9]*',/ENUM('','','','','',/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 128 ]; then sed "s/enum[ ]*('[a-zA-Z0-9]*','[a-zA-Z0-9]*','[a-zA-Z0-9]*','[a-zA-Z0-9]*','[a-zA-Z0-9]*',/ENUM('','','','','',/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 129 ]; then sed "s/enum[ ]*('','','','','','',/ENUM('',/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 130 ]; then sed "s/enum[ ]*('','','','',/ENUM('',/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 131 ]; then sed "s/enum[ ]*('','','',/ENUM('',/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 132 ]; then sed "s/enum[ ]*('','',/ENUM('',/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 133 ]; then sed "s/set[ ]*('[a-zA-Z0-9]*','[a-zA-Z0-9]*','[a-zA-Z0-9]*','[a-zA-Z0-9]*','[a-zA-Z0-9]*',/ENUM('',/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 134 ]; then sed "s/set[ ]*('','[a-zA-Z0-9]*','[a-zA-Z0-9]*','[a-zA-Z0-9]*','[a-zA-Z0-9]*','[a-zA-Z0-9]*',/ENUM('',/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 135 ]; then sed "s/set[ ]*('','[a-zA-Z0-9]*','[a-zA-Z0-9]*','[a-zA-Z0-9]*','[a-zA-Z0-9]*','[a-zA-Z0-9]*',/ENUM('',/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 136 ]; then sed "s/set[ ]*('','[a-zA-Z0-9]*','[a-zA-Z0-9]*','[a-zA-Z0-9]*','[a-zA-Z0-9]*','[a-zA-Z0-9]*',/ENUM('',/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 137 ]; then sed "s/set[ ]*('','','','','','',/SET('',/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 138 ]; then sed "s/set[ ]*('','','','',/SET('',/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 139 ]; then sed "s/set[ ]*('','','',/SET('',/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 140 ]; then sed "s/set[ ]*('','',/SET('',/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 141 ]; then NOSKIP=1; sed "s/ ENGINE=TokuDB/ ENGINE=InnoDB/gi" $WORKF > $WORKT # NOSKIP as lenght of 'TokuDB' is same as 'InnoDB' and we want to check if the testcase is engine specific or not
    elif [ $TRIAL -eq 142 ]; then sed "s/ ENGINE=RocksDB/ ENGINE=InnoDB/gi" $WORKF > $WORKT  # NOSKIP not required; InnoDB is shorter then RocksDB
    elif [ $TRIAL -eq 143 ]; then NOSKIP=1; sed "s/ ENGINE=MEMORY/ ENGINE=InnoDB/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 144 ]; then NOSKIP=1; sed "s/ ENGINE=MyISAM/ ENGINE=InnoDB/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 145 ]; then NOSKIP=1; sed "s/ ENGINE=CSV/ ENGINE=InnoDB/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 146 ]; then NOSKIP=1; sed "s/ ENGINE=NDB/ ENGINE=InnoDB/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 147 ]; then NOSKIP=1; sed "s/ ENGINE=[A-Za-z_-]\+/ ENGINE=InnoDB/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 148 ]; then sed "s/ ENGINE=[A-Za-z_-]\+/ /gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 149 ]; then sed "s/ ENGINE=TokuDB/ ENGINE=none/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 150 ]; then sed "s/ ENGINE=RocksDB/ ENGINE=none/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 151 ]; then NOSKIP=1; sed "s/TokuDB/InnoDB/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 152 ]; then sed "s/RocksDB/InnoDB/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 153 ]; then sed -e "s/[\t ]\+/ /g" -e "s/ \([;,]\)/\1/g" -e "s/ $//g" -e "s/^ //g" $WORKF > $WORKT
    elif [ $TRIAL -eq 154 ]; then sed "s/.*/\L&/" $WORKF > $WORKT
    elif [ $TRIAL -eq 155 ]; then sed "s/[ ]*([ ]*/(/;s/[ ]*)[ ]*/)/" $WORKF > $WORKT
    elif [ $TRIAL -eq 156 ]; then sed "s/;.*/;/" $WORKF > $WORKT
    elif [ $TRIAL -eq 157 ]; then sed "s/;#;.*$/;/" $WORKF > $WORKT
    elif [ $TRIAL -eq 158 ]; then sed "s/''/0/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 159 ]; then sed "/INSERT/,/;/s/''/0/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 160 ]; then sed "/SELECT/,/;/s/''/0/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 161 ]; then sed "s/;[ \t]\+#/;#/" $WORKF > $WORKT  # Remove any spaces/tabs before #EOL comments if present
    elif [ $TRIAL -eq 162 ]; then sed "s/;[ \t]*#.*/;/" $WORKF > $WORKT  # Attempt to remove #EOL comments
    elif [ $TRIAL -eq 163 ]; then sed "s/#[^#]\+$/;/" $WORKF > $WORKT  # Another attempt at removing #EOL comments
    elif [ $TRIAL -eq 164 ]; then sed "s/#[^#]\+$/#/" $WORKF > $WORKT  # If previous attempts do not work, attempt shorter comments
    elif [ $TRIAL -eq 165 ]; then sed "s/[ \t]\+$//" $WORKF > $WORKT  # Remove spaces at end of line
    elif [ $TRIAL -eq 166 ]; then NOSKIP=1; sed "s|\([^;]\)$|\1;|" $WORKF > $WORKT  # Add ";" on lines that do not have it
    elif [ $TRIAL -eq 167 ]; then NOSKIP=1; sed "s|#;|;#|" $WORKF > $WORKT  # Ref line above/below for combination effect
    elif [ $TRIAL -eq 168 ]; then sed "s/;[ \t]\+;/;/g" $WORKF > $WORKT  # Remove empty statements if possible
    elif [ $TRIAL -eq 169 ]; then sed "s/[ \t]\+/ /g" $WORKF > $WORKT
    elif [ $TRIAL -eq 170 ]; then sed "s/  / /" $WORKF > $WORKT
    elif [ $TRIAL -eq 171 ]; then sed "s/  / /" $WORKF > $WORKT
    elif [ $TRIAL -eq 172 ]; then sed "s/  / /" $WORKF > $WORKT
    elif [ $TRIAL -eq 173 ]; then sed "s|;#.*$|;|" $WORKF > $WORKT
    elif [ $TRIAL -eq 174 ]; then sed "s|;#[^#]\+$|;|" $WORKF > $WORKT
    elif [ $TRIAL -eq 175 ]; then sed "s/;  ;/;/" $WORKF > $WORKT
    elif [ $TRIAL -eq 176 ]; then sed "s/; ;/;/" $WORKF > $WORKT
    elif [ $TRIAL -eq 177 ]; then sed "s/;;/;/" $WORKF > $WORKT
    elif [ $TRIAL -eq 178 ]; then sed "s/; \+/;/" $WORKF > $WORKT
    elif [ $TRIAL -eq 179 ]; then sed "s/t1/t/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 180 ]; then sed "s/c1/c/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 181 ]; then sed "s/p1/p/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 182 ]; then sed "s/f1/f/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 183 ]; then sed "s/v1/c/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 184 ]; then sed "s/c,c,c/c/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 185 ]; then sed "s/c,c/c/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 186 ]; then sed "s/t[ \t]*(v)/t/g" $WORKF > $WORKT
    elif [ $TRIAL -eq 187 ]; then sed "s/[0-9][0-9][0-9][0-9][0-9]\+/1/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 188 ]; then sed "s/[0-9][0-9][0-9][0-9][0-9]\+/1/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 189 ]; then sed "s/[0-9][0-9][0-9][0-9]\+/1/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 190 ]; then sed "s/[0-9][0-9][0-9][0-9]\+/1/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 191 ]; then sed "s/[0-9][0-9][0-9]\+/1/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 192 ]; then sed "s/[0-9][0-9][0-9]\+/1/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 193 ]; then sed "s/[0-9][0-9]\+/1/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 194 ]; then sed "s/[0-9][0-9]\+/1/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 195 ]; then sed "s/[-+%^*]1//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 196 ]; then sed "s/[-+%^*]1//i" $WORKF > $WORKT
    elif [ $TRIAL -eq 197 ]; then sed "s/[-+%^*] [-+%^*]/-/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 198 ]; then sed "s/[-+%^*] [-+%^*]/-/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 199 ]; then sed "s/- 1/1/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 200 ]; then sed "s/ORDER BY [^ ]\+//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 201 ]; then sed "s/ORDER BY [^ ]\+//i" $WORKF > $WORKT
    elif [ $TRIAL -eq 202 ]; then sed "s/CASE.*END/1/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 203 ]; then sed "s/CASE[^E]\+END/1/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 204 ]; then sed "s/CASE.*END/1/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 205 ]; then sed "s/CASE[^E]\+END/1/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 206 ]; then sed "s/CASE.*END/CASE WHEN 1 THEN 2 ELSE 3 END/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 207 ]; then sed "s/CASE[^E]\+END/CASE WHEN 1 THEN 2 ELSE 3 END/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 208 ]; then sed "s/CASE.*END/CASE WHEN 1 THEN 2 ELSE 3 END/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 209 ]; then sed "s/CASE[^E]\+END/CASE WHEN 1 THEN 2 ELSE 3 END/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 210 ]; then sed "s/VALUES[ \t]\+([^)]\+),/VALUES (1),/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 211 ]; then sed "s/VALUES[ \t]\+([^)]\+),/VALUES /i" $WORKF > $WORKT
    elif [ $TRIAL -eq 212 ]; then sed "s/VALUES[ \t]\+([^)]\+),/VALUES /i" $WORKF > $WORKT
    elif [ $TRIAL -eq 213 ]; then sed "s/VALUES[ \t]\+([^)]\+),/VALUES /i" $WORKF > $WORKT
    elif [ $TRIAL -eq 214 ]; then sed "s/VALUES[ \t]\+(.*)/VALUES (1)/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 215 ]; then sed "s/([ \t+]ORDER[ \t+]BY[ \t+]t[ \t+])/(t)/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 216 ]; then sed "s/([ \t+]ORDER[ \t+]BY[ \t+]t[ \t+])/(t)/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 217 ]; then sed "s/([ \t+]ORDER[ \t+]BY[ \t+][^)]\+)/(t)/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 218 ]; then sed "s/([ \t+]ORDER[ \t+]BY[ \t+][^)]\+)/(t)/i" $WORKF > $WORKT
    elif [ $TRIAL -eq 219 ]; then sed "s/HAVING[ \t]\+FIRST_VALUE[ \t]\+[^A-Z]\+[A-Z]//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 220 ]; then sed "s/SUM[ \t]\+([ \t]\+)/1/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 221 ]; then sed "s/MAX[ \t]\+([ \t]\+)/1/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 222 ]; then sed "s/MIN[ \t]\+([ \t]\+)/1/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 223 ]; then sed "s/AVG[ \t]\+([ \t]\+)/1/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 224 ]; then sed "s/CHECK[ \t]\+([^)]\+[)]\+//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 225 ]; then sed "s/CHECK[ \t]\+([^)]\+[)]\+//i" $WORKF > $WORKT
    elif [ $TRIAL -eq 226 ]; then sed "s/CHECK[ \t]\+([^)]\+[)]\+//i" $WORKF > $WORKT
    elif [ $TRIAL -eq 227 ]; then sed "s/v0/c/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 228 ]; then sed "s/ CHAR)/ INT)/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 229 ]; then sed "s/c(c)/c/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 230 ]; then sed "s|0[-+/ ]\+0|0|gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 231 ]; then sed "s|0[ \t]*[+/-][ \t]*0|0|gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 232 ]; then sed "s|0[ \t]*[+/-][ \t]*0|0|i" $WORKF > $WORKT
    elif [ $TRIAL -eq 233 ]; then sed "s|0[ \t]*[+/-][ \t]*0|0|i" $WORKF > $WORKT
    elif [ $TRIAL -eq 234 ]; then sed "s|0[ \t]*[+/-][ \t]*0|0|i" $WORKF > $WORKT
    elif [ $TRIAL -eq 235 ]; then sed "s/stmt/s/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 236 ]; then sed "s/f1/f/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 237 ]; then sed "s/t1/t/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 238 ]; then sed "s/s1/s/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 239 ]; then sed "s/ps/p/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 240 ]; then sed "s/[ ]*TABLESPACE [^ ]\+ STORAGE DISK[ ]*/ /gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 241 ]; then sed "s/GROUP_CONCAT([^)]\+)/*/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 242 ]; then sed "s/COMMENT[ ]*=[ ]*['\"]WRAPPER[ ]*['\"]mysql['\"][ ]*,[ ]*srv[ ]*['\"]srv['\"][ ]*,[ ]*TABLE[ ]*['\"]t['\"]['\"]//i" $WORKF > $WORKT
    elif [ $TRIAL -eq 243 ]; then sed "s/COMMENT[ ]*=[ ]*['\"]WRAPPER[ ]*['\"]mysql['\"][ ]*,[ ]*srv[ ]*['\"]srv['\"][ ]*,[ ]*TABLE[ ]*['\"]t['\"]['\"]//i" $WORKF > $WORKT
    elif [ $TRIAL -eq 244 ]; then sed "s/COMMENT[ ]*=[ ]*['\"]WRAPPER[ ]*['\"]mysql['\"][ ]*,[ ]*srv[ ]*['\"]srv['\"][ ]*,[ ]*TABLE[ ]*['\"]t['\"]['\"]//i" $WORKF > $WORKT
    elif [ $TRIAL -eq 245 ]; then sed "s/COMMENT[ ]*=[ ]*['\"]WRAPPER[ ]*['\"]mysql['\"][ ]*,[ ]*srv[ ]*['\"]srv['\"][ ]*,[ ]*TABLE[ ]*['\"]t['\"]['\"]//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 246 ]; then sed "s/WITH SYSTEM VERSIONING//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 247 ]; then sed "s/WITH SYSTEM VERSIONING//i" $WORKF > $WORKT
    elif [ $TRIAL -eq 248 ]; then sed "s|'../socket.sock'|''|g" $WORKF > $WORKT
    elif [ $TRIAL -eq 249 ]; then sed "s|'../socket.sock'|''|" $WORKF > $WORKT
    elif [ $TRIAL -eq 250 ]; then sed "s/PWD1//g" $WORKF > $WORKT
    elif [ $TRIAL -eq 251 ]; then sed "s/PWD1//" $WORKF > $WORKT
    elif [ $TRIAL -eq 252 ]; then grep -E --binary-files=text -v "^$" $WORKF > $WORKT
    elif [ $TRIAL -eq 253 ]; then
      if [ -r "${SCRIPT_PWD}/testcase_prettify.sh" ]; then
        NOSKIP=1;  # Attempt a full run of testcase_prettify.sh to greatly improve testcase quality
        ${SCRIPT_PWD}/testcase_prettify.sh $WORKF > $WORKT
      elif [ -r "${HOME}/mariadb-qa/testcase_prettify.sh" ]; then  # When started from BASEDIRs
        NOSKIP=1;  # Attempt a full run of testcase_prettify.sh to greatly improve testcase quality
        ${HOME}/mariadb-qa/testcase_prettify.sh $WORKF > $WORKT
      else
        cat $WORKF > $WORKT  # No updates; this will ensure next trial triggers. Do not use 'continue' here.
      fi
    elif [ $TRIAL -eq 254 ]; then sed "s/0D0R0O0P0D0A0T0A0B0A0S0E0t0r0a0n0s0f0o0r0m0s0/NO_SQL_REQUIRED/" $WORKF > $WORKT
    # RV 25/01/21 Disabled next trial to see if this fixes the # mariadbd/mysqld options required insert
    # RV 09/05/22 It seems to help. Reinstated trial by temporary dummy swap instead
    elif [ $TRIAL -eq 255 ]; then sed 's|^# mysqld|DONOTDELETE|;s|# mariadbd|DONOTDELETE|' $WORKF | grep -E --binary-files=text -v "^#" | sed 's|^DONOTDELETE|# mysqld|' > $WORKT
    elif [ $TRIAL -eq 256 ]; then NOSKIP=1; sed "s/$/;/;s/;;$/;/" $WORKF > $WORKT  # Reintroduce end ; everwhere, if lost
    elif [ $TRIAL -eq 257 ]; then sed "s/t0/t/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 258 ]; then sed "s/c0/c/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 259 ]; then sed "s/FROM DUAL//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 260 ]; then sed "s/WITHOUT VALIDATION//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 261 ]; then sed "s/PARTITION.*;/;/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 262 ]; then sed "s/[ \t]\+CHARACTER SET[^)]\+)/)/gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 263 ]; then sed "s/index_merge=[ofn]\+[,]*//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 264 ]; then sed "s/index_merge_union=[ofn]\+[,]*//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 265 ]; then sed "s/index_merge_sort_union=[ofn]\+[,]*//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 266 ]; then sed "s/index_merge_intersection=[ofn]\+[,]*//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 267 ]; then sed "s/index_merge_sort_intersection=[ofn]\+[,]*//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 268 ]; then sed "s/index_condition_pushdown=[ofn]\+[,]*//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 269 ]; then sed "s/derived_merge=[ofn]\+[,]*//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 270 ]; then sed "s/derived_with_keys=[ofn]\+[,]*//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 271 ]; then sed "s/firstmatch=[ofn]\+[,]*//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 272 ]; then sed "s/loosescan=[ofn]\+[,]*//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 273 ]; then sed "s/materialization=[ofn]\+[,]*//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 274 ]; then sed "s/in_to_exists=[ofn]\+[,]*//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 275 ]; then sed "s/semijoin=[ofn]\+[,]*//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 276 ]; then sed "s/partial_match_rowid_merge=[ofn]\+[,]*//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 277 ]; then sed "s/partial_match_table_scan=[ofn]\+[,]*//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 278 ]; then sed "s/subquery_cache=[ofn]\+[,]*//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 279 ]; then sed "s/mrr=[ofn]\+[,]*//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 280 ]; then sed "s/mrr_cost_based=[ofn]\+[,]*//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 281 ]; then sed "s/mrr_sort_keys=[ofn]\+[,]*//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 282 ]; then sed "s/outer_join_with_cache=[ofn]\+[,]*//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 283 ]; then sed "s/semijoin_with_cache=[ofn]\+[,]*//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 284 ]; then sed "s/join_cache_incremental=[ofn]\+[,]*//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 285 ]; then sed "s/join_cache_hashed=[ofn]\+[,]*//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 286 ]; then sed "s/join_cache_bka=[ofn]\+[,]*//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 287 ]; then sed "s/optimize_join_buffer_size=[ofn]\+[,]*//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 288 ]; then sed "s/table_elimination=[ofn]\+[,]*//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 289 ]; then sed "s/extended_keys=[ofn]\+[,]*//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 290 ]; then sed "s/exists_to_in=[ofn]\+[,]*//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 291 ]; then sed "s/orderby_uses_equalities=[ofn]\+[,]*//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 292 ]; then sed "s/condition_pushdown_for_derived=[ofn]\+[,]*//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 293 ]; then sed "s/split_materialized=[ofn]\+[,]*//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 294 ]; then sed "s/condition_pushdown_for_subquery=[ofn]\+[,]*//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 295 ]; then sed "s/rowid_filter=[ofn]\+[,]*//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 296 ]; then sed "s/condition_pushdown_from_having=[ofn]\+[,]*//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 297 ]; then sed "s/not_null_range_scan=[ofn]\+[,]*//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 298 ]; then sed "s/hash_join_cardinality=[ofn]\+[,]*//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 299 ]; then sed "s/cset_narrowing=[ofn]\+[,]*//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 300 ]; then sed "s/sargable_casefold=[ofn]\+[,]*//gi" $WORKF > $WORKT
    elif [ $TRIAL -eq 301 ]; then NEXTACTION="& Finalize run"; sed 's/`//g' $WORKF > $WORKT
    else break
    fi
    if [ ! -r "${WORKT}" ]; then abort; fi
    SIZET=`stat -c %s $WORKT`
    if [ ${NOSKIP} -eq 0 -a $SIZET -ge $SIZEF ]; then
      echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] Skipping this trial as it does not reduce filesize"
      TRIAL=$[$TRIAL+1]
      TRIAL_REPEAT_COUNT=0
    else
      if [ -f $WORKD/log/mysql.out ]; then echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] Remaining size of input file: $SIZEF bytes ($LINECOUNTF lines)"; fi
      run_and_check
      if [ "$?" -ne "1" ]; then  # Issue failed to reproduce, revert (after retrying if applicable, i.e. NR_OF_TRIAL_REPEATS>1)
        TRIAL_REPEAT_COUNT=$[ ${TRIAL_REPEAT_COUNT} + 1 ]
        if [ ${TRIAL_REPEAT_COUNT} -lt ${NR_OF_TRIAL_REPEATS} ]; then
          echoit "$ATLEASTONCE [Stage $STAGE] Repeating trial (Attempt $[ ${TRIAL_REPEAT_COUNT} + 1 ]/${NR_OF_TRIAL_REPEATS})"
          NEXTACTION="& reattempt the same testcase complexity reducing sed"
        else  # Maximum repeats reached and issue failed to reproduce in any of them
          TRIAL=$[$TRIAL+1]
          TRIAL_REPEAT_COUNT=0
          NEXTACTION="& try next testcase complexity reducing sed"
        fi
      else  # Verify success
        TRIAL=$[$TRIAL+1]
        TRIAL_REPEAT_COUNT=0
        NEXTACTION="& try next testcase complexity reducing sed"
      fi
      if [ "${FIREWORKS}" != "1" ]; then  # In fireworks mode, we do not use WORKF but INPUTFILE
        if [ ! -r "${WORKF}" ]; then abort; fi
        SIZEF=$(stat -c %s ${WORKF})
        LINECOUNTF=$(cat ${WORKF} | wc -l | tr -d '[\t\n ]*')
      else
        if [ ! -r "${INPUTFILE}" ]; then abort; fi
        SIZEF=$(stat -c %s ${INPUTFILE})
        LINECOUNTF=$(cat ${INPUTFILE} | wc -l | tr -d '[\t\n ]*')
      fi
    fi
  done
fi

#STAGE8: Execute mariadbd/mysqld option simplification. Perform a check if the issue is still present once options are removed one-by-one
if [ $SKIPSTAGEBELOW -lt 8 -a $SKIPSTAGEABOVE -gt 8 ]; then
  NEXTACTION="& try removing next mariadbd/mysqld option"
  STAGE=8
  TRIAL=1
  TRIAL_REPEAT_COUNT=0
  cp $WORKF $WORKT  # Setup STAGE8 to begin with the last known good testcase. WORKT is used as input in run_and_check
  FILE1="$WORKD/file1"
  FILE2="$WORKD/file2"
  echoit "$ATLEASTONCE [Stage $STAGE] Commencing stage $STAGE"

  myextra_split(){
    if [ ! -d "${WORKD}" ]; then abort; fi
    touch $WORKD
    echo $MYEXTRA | sed 's|[ \t]\+| |g' | tr -s " " "\n" | grep -v "^[ \t]*$" > $WORKD/mysqld_opt.out
    MYSQLD_OPTION_COUNT=$(cat $WORKD/mysqld_opt.out | wc -l)
    head -n $((MYSQLD_OPTION_COUNT/2)) $WORKD/mysqld_opt.out > $FILE1
    tail -n $((MYSQLD_OPTION_COUNT-MYSQLD_OPTION_COUNT/2)) $WORKD/mysqld_opt.out > $FILE2
  }

  myextra_reduction(){
    while read line; do
      STAGE8_CHK=0
      STAGE8_NOT_STARTED_CORRECTLY=0
      echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] Filtering mariadbd/mysqld option $line from MYEXTRA";
      MYEXTRA=$(echo $MYEXTRA | sed "s|$line||")
      while :; do
        run_and_check
        TRIAL_REPEAT_COUNT=$[ ${TRIAL_REPEAT_COUNT} + 1 ]
        if [ $STAGE8_CHK -eq 0 -o $STAGE8_NOT_STARTED_CORRECTLY -eq 1 ];then  # Issue failed to reproduce, revert (after retrying if applicable, i.e. NR_OF_TRIAL_REPEATS>1)
          if [ ${TRIAL_REPEAT_COUNT} -lt ${NR_OF_TRIAL_REPEATS} ]; then
            echoit "$ATLEASTONCE [Stage $STAGE] Repeating trial (Attempt $[ ${TRIAL_REPEAT_COUNT} + 1 ]/${NR_OF_TRIAL_REPEATS})"
            NEXTACTION="& reattempt removing the same mariadbd/mysqld option"
            continue
          else  # Maximum repeats reached and issue failed to reproduce in any of them
            MYEXTRA="$MYEXTRA $line"
            break
          fi
        else  # Issue reproduced, so leave MYEXTRA as-is (already filtered), and filter the same from WORK_START now too
          sed -i "s|$line||" $WORK_START
          break
        fi
      done
      NEXTACTION="& try removing next mariadbd/mysqld option"
      TRIAL_REPEAT_COUNT=0
      TRIAL=$[$TRIAL+1]
    done < $WORKD/mysqld_opt.out
  }

  # If NR_OF_TRIAL_REPEATS is >1 then try only per-option reduction (simplifies code)
  if [ ${NR_OF_TRIAL_REPEATS} -gt 1 ]; then
    echo $MYEXTRA | sed 's|[ \t]\+| |g' | tr -s " " "\n" | grep -v "^[ \t]*$" > $WORKD/mysqld_opt.out
    MYSQLD_OPTION_COUNT=$(cat $WORKD/mysqld_opt.out | wc -l)
    myextra_reduction  # Commence 1-by-1 reduction (with build-in NR_OF_TRIAL_REPEATS handling)
  else
    # Deal with options differently depending on how many there are (this selection is made only once)
    myextra_split
    if [ $MYSQLD_OPTION_COUNT -eq 0 ]; then  # 0 options
      if [ -n "$(echo ${MYEXTRA} | sed "s|[ \t]*||")" ]; then
        echoit "Assert: counted number of mariadbd/mysqld options was zero, yet \$MYEXTRA is not empty;"
        echoit "MYEXTRA: $MYEXTRA"
        echoit "Please check. Terminating."
        exit 1
      fi
      echoit "$ATLEASTONCE [Stage $STAGE] Skipping this stage as the testcase does not contain extraneous mariadbd/mysqld options"
    elif [ $MYSQLD_OPTION_COUNT -ge 1 -a $MYSQLD_OPTION_COUNT -le 4 ]; then  # 1-4 options
      myextra_reduction
    else  # 4+ options
      while :; do
        SAVE_STAGE8_MYEXTRA=$MYEXTRA
        MYEXTRA=$(cat $FILE1 | tr -s "\n" " " | sed 's|[ \t]\+| |g;s| $||g;s|^ ||g')
        STAGE8_CHK=0
        STAGE8_NOT_STARTED_CORRECTLY=0
        echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] Using first set of mariadbd/mysqld option(s) from MYEXTRA: $MYEXTRA";
        run_and_check
        TRIAL=$[$TRIAL+1]
        if [ $STAGE8_CHK -eq 0 -o $STAGE8_NOT_STARTED_CORRECTLY -eq 1 ];then  # Issue failed to reproduce, try second set
          MYEXTRA=$(cat $FILE2 | tr -s "\n" " " | sed 's|[ \t]\+| |g;s| $||g;s|^ ||g')
          STAGE8_CHK=0
          STAGE8_NOT_STARTED_CORRECTLY=0
          echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] Using second set of mariadbd/mysqld option(s) from MYEXTRA: $MYEXTRA";
          run_and_check
          TRIAL=$[$TRIAL+1]
          if [ $STAGE8_CHK -eq 0 -o $STAGE8_NOT_STARTED_CORRECTLY -eq 1 ];then  # Issue failed to reproduce, try reducing 1-by-1
            # Both the first set as well as the second set of options failed to reproduce the issue
            MYEXTRA=$SAVE_STAGE8_MYEXTRA
            myextra_reduction  # Commence 1-by-1 reduction
            break
          else  # Issue reproduced, so leave MYEXTA as-is (already filtered), and filter each filtered optiom from WORK_START now too
            while read line; do
              sed -i "s|$line||" $WORK_START
            done < $FILE1  # We use $FILE1 here (the opposite option set with options that are not required for issue reproduction)
            myextra_split
            if [ $(wc -l $FILE1 $FILE2 | grep total | awk '{print $1}') -le 4 ]; then  # Remaining nr of options <=4
              myextra_reduction  # Commence 1-by-1 reduction
              break
            fi
          fi
        else  # Issue reproduced, so leave MYEXTRA as-is (already filtered), and filter each filtered option from WORK_START now too
          while read line; do
            sed -i "s|$line||" $WORK_START
          done < $FILE2  # We use $FILE2 here (the opposite option set with options that are not required for issue reproduction)
          myextra_split
          if [ $(wc -l $FILE1 $FILE2 | grep total | awk '{print $1}') -le 4 ]; then  # Remaining nr of options <=4
            myextra_reduction  # Commence 1-by-1 reduction
            break
          fi
        fi
      done
    fi
  fi
fi

#STAGE9: Execute storage engine, binlogging, keyring and similar options simplification.
if [ $SKIPSTAGEBELOW -lt 9 -a $SKIPSTAGEABOVE -gt 9 ]; then
  NEXTACTION=
  STAGE=9
  TRIAL=1
  echoit "$ATLEASTONCE [Stage $STAGE] Commencing stage $STAGE"
  cp $WORKF $WORKT  # Setup STAGE9 to begin with the last known good testcase. WORKT is used as input in run_and_check

  stage9_run(){
    TRIAL_REPEAT_COUNT=0
    STAGE9_CHK=0
    SAVE_MYINIT=
    if [[ ${MYINIT_DROP} -eq 1 ]]; then
      SAVE_MYINIT=${MYINIT}
      MYINIT=
    fi
    STAGE9_NOT_STARTED_CORRECTLY=0
    SAVE_SPECIAL_MYEXTRA_OPTIONS=$SPECIAL_MYEXTRA_OPTIONS
    SPECIAL_MYEXTRA_OPTIONS=$(echo "$SPECIAL_MYEXTRA_OPTIONS" | sed "s|$STAGE9_FILTER||");
    while :; do
      run_and_check
      TRIAL_REPEAT_COUNT=$[ ${TRIAL_REPEAT_COUNT} + 1 ]
      if [ $STAGE9_CHK -eq 0 -o $STAGE9_NOT_STARTED_CORRECTLY -eq 1 ];then  # Issue failed to reproduce, revert (after retrying if applicable, i.e. NR_OF_TRIAL_REPEATS>1)
        if [ ${TRIAL_REPEAT_COUNT} -lt ${NR_OF_TRIAL_REPEATS} ]; then  # Retry if NR_OF_TRIAL_REPEATS>1
          echoit "$ATLEASTONCE [Stage $STAGE] Repeating trial (Attempt $[ ${TRIAL_REPEAT_COUNT} + 1 ]/${NR_OF_TRIAL_REPEATS})"
          continue
        else  # Maximum repeats reached and issue failed to reproduce in any of them
          SPECIAL_MYEXTRA_OPTIONS=$SAVE_SPECIAL_MYEXTRA_OPTIONS
          if [ "${SAVE_MYINIT}" != "" ]; then
            MYINIT=${SAVE_MYINIT}
          fi
          break
        fi
      else  # Issue reproduced, so leave SPECIAL_MYEXTRA_OPTIONS as-is (already filtered), and filter the same from WORK_START now too
        sed -i "s|$STAGE9_FILTER||" $WORK_START
        if [ "${SAVE_MYINIT}" != "" ]; then
          sed -i "s|${MYINIT}||" $WORK_START
        fi
        break
      fi
    done
    TRIAL_REPEAT_COUNT=0
    TRIAL=$[$TRIAL+1]
  }

  if [[ ! -z "$TOKUDB" ]] ;then
    echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] Removing TokuDB storage engine from startup options"
    STAGE9_FILTER=$TOKUDB
    stage9_run
  fi
  if [[ ! -z "$ROCKSDB" ]];then
    echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] Removing RocksDB storage engine from startup options"
    STAGE9_FILTER=$ROCKSDB
    stage9_run
  fi
  if [[ ! -z "$BL_ENCRYPTION" ]];then
    echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] Removing Binary Logs encryption from startup options"
    STAGE9_FILTER=$BL_ENCRYPTION
    stage9_run
  fi
  if [[ ! -z "$KF_ENCRYPTION" ]];then
    echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] Removing Keyring File encryption from startup options"
    STAGE9_FILTER=$KF_ENCRYPTION
    stage9_run
  fi
  if [[ ! -z "$BINLOG" ]];then
    echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] Removing Binary logging from startup options"
    STAGE9_FILTER=$BINLOG
    stage9_run
  fi
  if [[ ! -z "$ONLYFULLGROUPBY" ]];then
    echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] Removing ONLY_FULL_GROUP_BY SQL Mode from startup options"
    STAGE9_FILTER="ONLY_FULL_GROUP_BY"  # In many cases, this can be successfully removed whereas --sql_mode= cannot (i.e. is required)
    stage9_run
    if [ $STAGE9_CHK -ne 0 -a $STAGE9_NOT_STARTED_CORRECTLY -ne 1 ];then  # Issue reproduced, now try and remove --sql_mode=
      echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] Removing SQL Mode (--sql_mode=) from startup options"
      STAGE9_FILTER="--sql_mode="
      stage9_run
    fi
  fi
  if [ "${MYINIT}" != "" ]; then  # Try and drop both MYINIT and any matching options from MYEXTRA as well
    echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] Removing MYINIT options from startup options & from mariadbd/mysqld initialization"
    STAGE9_FILTER=$(echo ${MYINIT} | sed 's|^[ \t]\+||;s|[ \t]\+$||')
    MYINIT_DROP=1
    stage9_run
  fi
  if [ "${MYINIT}" != "" ]; then  # Previous one failed, so try MYINIT removal only
    echoit "$ATLEASTONCE [Stage $STAGE] [Trial $TRIAL] Removing MYINIT options from mariadbd/mysqld initialization"
    MYINIT_DROP=1
    stage9_run
  fi
fi

finish $INPUTFILE
