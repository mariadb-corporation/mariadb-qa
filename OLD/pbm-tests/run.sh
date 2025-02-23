#!/usr/bin/env bash

export DEBUG=

shopt -s extglob

set +e

# don't change
export SCRIPT_PWD=$(cd `dirname $0` && pwd)
export PQA_PATH=${SCRIPT_PWD}/../

. ${PQA_PATH}/pbm-tests/inc/common.sh
. ${PQA_PATH}/pbm-tests/subunit.sh

###
### PREPARE ENVIRONMENT
###
prepare_environment

trap cleanup_on_exit EXIT
trap terminate SIGHUP SIGINT SIGQUIT SIGTERM

result=0

# Default test timeout in seconds
TEST_TIMEOUT=900

# Magic exit code to indicate a skipped test
export SKIPPED_EXIT_CODE=200

# Default server installation directory (-d option)
MONGODB_PATH=${MONGODB_PATH:-"$PWD"}

TEST_BASEDIR="${PQA_PATH}/pbm-tests"
TEST_VAR_ROOT="${TEST_RESULT_DIR}/var"

# Global statistics
FAILED_COUNT=0
FAILED_TESTS=
SKIPPED_COUNT=0
SKIPPED_TESTS=
SUCCESSFUL_COUNT=0
TOTAL_COUNT=0
TOTAL_TIME=0

function usage()
{
cat <<EOF
Usage: $0 [-f] [-g] [-h] [-s suite] [-t test_name] [-d mysql_basedir] [-c build_conf]
-f          Continue running tests after failures
-d path     Server installation directory. Default is '.'
-g          Debug mode
-t path     Run only a single named test
-h          Print this help message
-s suite    Select a test suite to run. Possible values: experimental, t
            Default is 't'
-j N        Run tests in N parallel processes
-T seconds  Test timeout (default is $TEST_TIMEOUT seconds)
-r path     Use specified path as root directory for test workers
EOF
}

###############################################################################
# Calculate the number of parallel workers automatically based on the number of
# available cores
###############################################################################
function autocalc_nworkers()
{
    # We are limiting this for now to 1
    NWORKERS=1

#    if [ -r /proc/cpuinfo ]
#    then
#        NWORKERS=`grep processor /proc/cpuinfo | wc -l`
#    elif which sysctl >/dev/null 2>&1
#    then
#        NWORKERS=`sysctl -n hw.ncpu`
#    fi
#
#    if [[ ! $NWORKERS =~ ^[0-9]+$ || $NWORKERS < 1 ]]
#    then
#        echo "Cannot determine the number of available CPU cures!"
#        exit -1
#    fi
#
#    XB_TEST_MAX_WORKERS=${XB_TEST_MAX_WORKERS:-16}
#    if [ "$NWORKERS" -gt $XB_TEST_MAX_WORKERS ]
#    then
#        cat <<EOF
#Autodetected number of cores: $NWORKERS
#Limiting to $XB_TEST_MAX_WORKERS to avoid excessive resource consumption
#EOF
#        NWORKERS=$XB_TEST_MAX_WORKERS
#    fi
}

###############################################################################
# Kill a specified worker
###############################################################################
function kill_worker()
{
    local worker=$1
    local pid=${worker_pids[$worker]}
    local cpids=`pgrep -P $pid`

    worker_pids[$worker]=""

    if ! kill -0 $pid >/dev/null 2>&1
    then
        wait $pid >/dev/null 2>&1 || true
        return 0
    fi

    # First send SIGTERM to let worker exit gracefully
    kill -SIGTERM $pid >/dev/null 2>&1 || true
    for cpid in $cpids ; do kill -SIGTERM $cpid >/dev/null 2>&1 ; done

    sleep 1

    if ! kill -0 $pid >/dev/null 2>&1
    then
        wait $pid >/dev/null 2>&1 || true
        return 0
    fi

    # Now kill with SIGKILL
    kill -SIGKILL $pid >/dev/null 2>&1 || true
    for cpid in $cpids ; do kill -SIGKILL $cpid >/dev/null 2>&1 ; done
    wait $pid >/dev/null 2>&1 || true
    release_port_locks $pid
}

########################################################################
# Kill all running workers
########################################################################
function kill_all_workers()
{
    while true
    do
        found=""

        # First send SIGTERM to let workers exit gracefully
        for ((i = 1; i <= NWORKERS; i++))
        do
            [ -z ${worker_pids[$i]:-""} ] && continue

            found="yes"

           if ! kill -0 ${worker_pids[$i]} >/dev/null 2>&1
           then
               worker_pids[$i]=""
               continue
           fi

            kill -SIGTERM ${worker_pids[$i]} >/dev/null 2>&1 || true
        done

        [ -z "$found" ] && break

        sleep 1

        # Now kill with SIGKILL
        for ((i = 1; i <= NWORKERS; i++))
        do
            [ -z ${worker_pids[$i]:-""} ] && continue

            if ! kill -0 ${worker_pids[$i]} >/dev/null 2>&1
            then
                wait ${worker_pids[$i]} >/dev/null 2>&1 || true
                worker_pids[$i]=""
                continue
            fi

            kill -SIGKILL ${worker_pids[$i]} >/dev/null 2>&1 || true
            wait ${worker_pids[$i]} >/dev/null 2>&1 || true
            release_port_locks ${worker_pids[$i]}
            worker_pids[$i]=""
        done
    done
}

########################################################################
# Handler called from a fatal signal handler trap
########################################################################
function terminate()
{
    echo "Terminated, cleaning up..."

    # The following will call cleanup_on_exit()
    exit 2
}

########################################################################
# Display the test run summary and exit
########################################################################
function print_status_and_exit()
{
    local test_time=$((`now` - TEST_START_TIME))
    cat <<EOF
==============================================================================
Spent $TOTAL_TIME of $test_time seconds executing testcases

SUMMARY: $TOTAL_COUNT run, $SUCCESSFUL_COUNT successful, $SKIPPED_COUNT skipped, $FAILED_COUNT failed

EOF

    if [ -n "$SKIPPED_TESTS" ]
    then
        echo "Skipped tests: $SKIPPED_TESTS"
        echo
    fi

    if [ -n "$FAILED_TESTS" ]
    then
        echo "Failed tests: $FAILED_TESTS"
        echo
    fi

    echo "See pbm-test-run/results/ for detailed output"

    if [ "$FAILED_COUNT" = 0 ]
    then
        exit 0
    fi

    exit 1
}

########################################################################
# Cleanup procedure invoked on process exit
########################################################################
function cleanup_on_exit()
{
    kill_servers $TEST_VAR_ROOT

    remove_var_dirs

    release_port_locks $$

    kill_all_workers

    cleanup_all_workers
}

function find_program()
{
    local VARNAME="$1"
    shift
    local PROGNAME="$1"
    shift
    local DIRLIST="$*"
    local found=""

    for dir in in $DIRLIST
    do
	if [ -d "$dir" -a -x "$dir/$PROGNAME" ]
	then
	    eval "$VARNAME=\"$dir/$PROGNAME\""
	    found="yes"
	    break
	fi
    done
    if [ -z "$found" ]
    then
	echo "Can't find $PROGNAME in $DIRLIST"
	exit -1
    fi
}

########################################################################
# Explore environment and setup global variables
########################################################################
function set_vars()
{
    if gnutar --version > /dev/null 2>&1
    then
        TAR=gnutar
    elif gtar --version > /dev/null 2>&1
    then
        TAR=gtar
    else
        TAR=tar
    fi

    if gnused --version > /dev/null 2>&1
    then
        SED=gnused
    elif gsed --version > /dev/null 2>&1
    then
        SED=gsed
    else
        SED=sed
    fi

    #find_program MONGOD mongod $MONGODB_PATH/bin
    #find_program MONGO mongo $MONGODB_PATH/bin
    #find_program MONGOS mongos $MONGODB_PATH/bin
    #find_program MONGODUMP mongodump $MONGODB_PATH/bin
    #find_program MONGOEXPORT mongoexport $MONGODB_PATH/bin
    #find_program BSONDUMP bsondump $MONGODB_PATH/bin

    PATH="${MONGODB_PATH}/bin:${PBM_PATH}:${YCSB_PATH}/bin:${MGODATAGEN_PATH}:$PATH"

    export TAR SED MONGODB_PATH PATH
}

###########################################################################
# Kill all server processes started by a worker specified with its var root
# directory
###########################################################################
# since we have only one worker at fixed directory we just want to stop all
function kill_servers()
{
  stop_all_mongo >/dev/null 2>&1 || true
  stop_all_pbm >/dev/null 2>&1 || true
}
#function kill_servers()
#{
#    local var_root=$1
#    local file
#
#    [ -d $var_root ] || return 0
#
#    cd $var_root
#
#    for file in mongod*.pid
#    do
#        if [ -f $file ]
#        then
#            vlog "Found a leftover mongod processes with PID `cat $file`, \
#stopping it"
#            kill -9 `cat $file` 2>/dev/null || true
#            rm -f $file
#        fi
#    done
#
#    cd - >/dev/null 2>&1
#}

###########################################################################
# Kill all server processes started by a worker specified with its number
###########################################################################
# since we have only one worker at fixed directory we just want to stop all
function kill_servers_for_worker()
{
  stop_all_mongo >/dev/null 2>&1 || true
  stop_all_pbm >/dev/null 2>&1 || true
}
#function kill_servers_for_worker()
#{
#    local worker=$1
#
#    kill_servers ${TEST_VAR_ROOT}/w$worker
#}

################################################################################
# Clean up all workers (except DEBUG_WORKER if set) We can't use worker* arrays
# here and examine the directory structure, because the same functions is called
# on startup when we want to cleanup all workers started on previous invokations
################################################################################
function cleanup_all_workers() { local worker

    for worker_dir in ${TEST_VAR_ROOT}/w+([0-9])
    do
        [ -d $worker_dir ] || continue
        [[ $worker_dir =~ w([0-9]+)$ ]] || continue

        worker=${BASH_REMATCH[1]}

        if [ "$worker" = "$DEBUG_WORKER" ]
        then
            echo
            echo "Skipping cleanup for worker #$worker due to debug mode."
            echo "You can do post-mortem analysis by examining test data in \
$worker_dir"
            echo "and the server process if it was running at the failure time."
            continue
        fi

        cleanup_worker $worker
    done
}
########################################################################
# Clean up a specified worker
########################################################################
function cleanup_worker()
{
    local worker=$1
    local tmpdir

    kill_servers_for_worker $worker >>$OUTFILE 2>&1

    # It is possible that a file is created while rm is in progress
    # which results in "rm: cannot remove ...: Directory not empty
    # hence the loop below
    while true
    do
        # Fix permissions as some tests modify them so the following 'rm' fails
        chmod -R 0700 ${TEST_VAR_ROOT}/w$worker >/dev/null 2>&1
        rm -rf ${TEST_VAR_ROOT}/w$worker && break
    done

    tmpdir=${worker_tmpdirs[$worker]:-""}
    if [ -n "$tmpdir" ]
    then
        rm -rf $tmpdir
    fi
}

########################################################################
# Return the number of seconds since the Epoch, UTC
########################################################################
function now()
{
    date '+%s'
}

########################################################################
# Process the exit code of a specified worker
########################################################################
function reap_worker()
{
    local worker=$1
    local pid=${worker_pids[$worker]}
    local skip_file=${worker_skip_files[$worker]}
    local tpath=${worker_names[$worker]}
    local tname=`basename $tpath .sh`
    local test_time=$((`now` - worker_stime[$worker]))
    local status_file=${worker_status_files[$worker]}
    local rc

    if [ -f "$status_file" ]
    then
        rc=`cat $status_file`
        # Assume exit code 1 if status file is empty
        rc=${rc:-"1"}
    else
        # Assume exit code 1 if status file does not exist
        rc="1"
    fi

    printf "%-40s w%d\t" $tname $worker

    ((TOTAL_TIME+=test_time))

    # Have to call subunit_start_test here, as currently tests cannot be
    # interleaved in the subunit output
    subunit_start_test $tpath "${worker_stime_txt[$worker]}" >> $SUBUNIT_OUT

    if [ $rc -eq 0 ]
    then
        echo "[passed]    $test_time"

        SUCCESSFUL_COUNT=$((SUCCESSFUL_COUNT + 1))
        subunit_pass_test $tpath >> $SUBUNIT_OUT

        cleanup_worker $worker
    elif [ $rc -eq $SKIPPED_EXIT_CODE ]
    then
        sreason=""
        test -r $skip_file && sreason=`cat $skip_file`

        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        SKIPPED_TESTS="$SKIPPED_TESTS $tname"

        echo "[skipped]   $sreason"

        subunit_skip_test $tpath >> $SUBUNIT_OUT

        cleanup_worker $worker
    else
        echo "[failed]    $test_time"

        (
            (echo "Something went wrong running $tpath. Exited with $rc";
                echo; echo; cat ${worker_outfiles[$worker]}
            ) | subunit_fail_test $tpath
        ) >> $SUBUNIT_OUT

       FAILED_COUNT=$((FAILED_COUNT + 1))
       FAILED_TESTS="$FAILED_TESTS $tname"

       # Return 0 on failed tests in the -f mode
       if [ -z "$force" ]
       then

           if [ -z "$DEBUG" ]
           then
               cleanup_worker $worker
           else
               DEBUG_WORKER=$worker
           fi

           return 1
       else
           cleanup_worker $worker

           return 0
       fi
    fi

}

#############################################################################
# Check if a specified worker has exceed TEST_TIMEOUT and if so, terminate it
#############################################################################
function check_timeout_for_worker()
{
    local worker=$1
    local tpath=${worker_names[$worker]}
    local tname=`basename $tpath .sh`

    if (( `now` - worker_stime[$worker] > TEST_TIMEOUT ))
    then
        kill_worker $worker
        printf "%-40s w%d\t" $tname $worker
        echo "[failed]    Timed out after $TEST_TIMEOUT seconds."

        (
            # Have to call subunit_start_test here, as currently tests cannot be
            # interleaved in the subunit output
            subunit_start_test $tpath "${worker_stime_txt[$worker]}"

            (echo "Timeout exceeded running $tpath.";
                echo; echo; cat ${worker_outfiles[$worker]}
            ) | subunit_fail_test $tpath
        ) >> $SUBUNIT_OUT

        FAILED_COUNT=$((FAILED_COUNT + 1))
        FAILED_TESTS="$FAILED_TESTS $tname"

        # Return 0 on failed tests in the -f mode
        if [ -z "$force" ]
        then

            if [ -z "$DEBUG" ]
           then
                cleanup_worker $worker
            else
               DEBUG_WORKER=$worker
           fi

            return 1
        else
            cleanup_worker $worker

            return 0
       fi
    fi
}
#########################################################################
# Wait for all currently running worker to finish
#########################################################################
function reap_all_workers()
{
    while true
    do
        found=""

        for ((i = 1; i <= NWORKERS; i++))
        do
            [ -z ${worker_pids[$i]:-""} ] && continue

            found="yes"

            # Check if it's alive
            if kill -0 ${worker_pids[$i]} >/dev/null 2>&1
            then
                check_timeout_for_worker $i || print_status_and_exit
                continue
            fi

            reap_worker $i || print_status_and_exit

            worker_pids[$i]=""
        done

        [ -z "$found" ] && break

        sleep 1
    done
}

########################################################################
# Release all port locks reserved by the current process
# Used by the EXIT trap (in both normal and abnormal shell termination)
########################################################################
function release_port_locks()
{
    local process=$1
    local lockfile

    # Suppress errors when no port lock files are found
    shopt -s nullglob

    for lockfile in /tmp/xtrabackup_port_lock.*
    do
        if [ "`cat $lockfile 2>/dev/null`" = $process ]
        then
            rm -rf $lockfile
        fi
    done

    shopt -u nullglob
}

########################################################################
# Report status and release port locks on exit
########################################################################
function cleanup_on_test_exit()
{
    local rc=$?

    echo $rc > $STATUS_FILE

    release_port_locks $$
}

########################################################################
# Script body
########################################################################

TEST_START_TIME=`now`

tname=""
XTRACE_OPTION=""
force=""
SUBUNIT_OUT=${TEST_RESULT_DIR}/test_results.subunit
NWORKERS=
DEBUG_WORKER=""

while getopts "fgh?:t:s:d:c:j:T:i:r:" options; do
        case $options in
            f ) force="yes";;
            t )

                tname="$OPTARG";
                if ! [ -r "$tname" ]
                then
                    echo "Cannot find test $tname."
                    exit -1
                fi
                ;;

            g ) DEBUG=on;;
            h ) usage; exit;;
            s ) tname="$OPTARG/*.sh";;
            d ) export MONGODB_PATH="$OPTARG";;
            c ) echo "Warning: -c does not have any effect and is only \
recognized for compatibility";;
            j )

                if [[ ! $OPTARG =~ ^[0-9]+$ || $OPTARG < 1 ]]
                then
                    echo "Wrong -j argument: $OPTARG"
                    exit -1
                fi
                NWORKERS="$OPTARG"
                ;;

            T )
                if [[ ! $OPTARG =~ ^[0-9]+$ ]]
                then
                    echo "Wrong -T argument: $OPTARG"
                    exit -1
                fi
                TEST_TIMEOUT="$OPTARG"
                ;;

            r )
                if [ ! -d $OPTARG ]
                then
                    echo "Wrong -r argument: $OPTARG make sure that directory exists"
                    exit -1
                fi
                TEST_BASEDIR="$OPTARG"
                TEST_VAR_ROOT="$TEST_BASEDIR/var"
                ;;

            ? ) echo "Use \`$0 -h' for the list of available options."
                    exit -1;;
        esac
done

set_vars

if [ -n "$tname" ]
then
   tests="$tname"
else
   tests="$TEST_BASEDIR/t/*.sh"
fi

export OUTFILE="${TEST_RESULT_DIR}/results/setup"

rm -rf ${TEST_RESULT_DIR}/results
mkdir ${TEST_RESULT_DIR}/results

cleanup_all_workers >>$OUTFILE 2>&1

echo "Using $TEST_VAR_ROOT as test root"
rm -rf ${TEST_VAR_ROOT} ${SUBUNIT_OUT}
mkdir -p ${TEST_VAR_ROOT}

# echo "Detecting server version..." | tee -a $OUTFILE

# if ! get_version_info
# then
#     echo "get_version_info failed. See $OUTFILE for details."
#     exit -1
# fi

# echo "Running against $MYSQL_FLAVOR $MYSQL_VERSION ($INNODB_FLAVOR $INNODB_VERSION)" |
#  tee -a $OUTFILE

# echo "Using '`basename $XB_BIN`' as xtrabackup binary" | tee -a $OUTFILE

[ -z "$NWORKERS" ] && autocalc_nworkers

if [ "$NWORKERS" -gt 1 ]
then
    echo "Using $NWORKERS parallel workers" | tee -a $OUTFILE
fi
echo | tee -a $OUTFILE

cat <<EOF
==============================================================================
TEST                                   WORKER    RESULT     TIME(s) or COMMENT
------------------------------------------------------------------------------
EOF

for t in $tests
do
   # Check if we have available workers
   found=""

   while [ -z "$found" ]
   do
       for ((i = 1; i <= NWORKERS; i++))
       do
           if [ -z ${worker_pids[$i]:-""} ]
           then
               found="yes"
               break
           else
               # Check if it's alive
               if kill -0 ${worker_pids[$i]} >/dev/null 2>&1
               then
                   check_timeout_for_worker $i || print_status_and_exit
                   continue
               fi
               reap_worker $i || print_status_and_exit

               worker_pids[$i]=""
               found="yes"

               break
           fi
       done

       if [ -z "$found" ]
       then
           sleep 1
       fi
   done

   worker=$i

   TOTAL_COUNT=$((TOTAL_COUNT+1))

   name=`basename $t .sh`
   worker_names[$worker]=$t
   worker_outfiles[$worker]="${TEST_RESULT_DIR}/results/$name.output"
   worker_skip_files[$worker]="${TEST_RESULT_DIR}/results/$name.skipped"
   worker_status_files[$worker]="${TEST_RESULT_DIR}/results/$name.status"
   # Create a unique TMPDIR for each worker so that it can be removed as a part
   # of the cleanup procedure. Server socket files will also be created there.
   worker_tmpdirs[$worker]="`mktemp -d -t xbtemp.XXXXXX`"

   (
       set -eu
       if [ -n "$DEBUG" ]
       then
           set -x
       fi

       trap "cleanup_on_test_exit" EXIT

       . ${PQA_PATH}/pbm-tests/inc/common.sh

       export OUTFILE=${worker_outfiles[$worker]}
       export SKIPPED_REASON=${worker_skip_files[$worker]}
       export TEST_VAR_ROOT=${TEST_RESULT_DIR}/var/w$worker
       export TMPDIR=${worker_tmpdirs[$worker]}
       export STATUS_FILE=${worker_status_files[$worker]}

       mkdir $TEST_VAR_ROOT

       # Execute the test in a subshell. This is required to catch syntax
       # errors, as otherwise $? would be 0 in cleanup_on_test_exit resulting in
       # passed test
       (. $t) || exit $?
   ) > ${worker_outfiles[$worker]} 2>&1 &

   worker_pids[$worker]=$!
   worker_stime[$worker]="`now`"
   # Used in subunit reports
   worker_stime_txt[$worker]="`date -u '+%Y-%m-%d %H:%M:%S'`"
done

# Wait for in-progress workers to finish
reap_all_workers

print_status_and_exit

