#!/bin/bash
# Created by Roel Van de Paar, MariaDB

# Note: if this script is terminated, you can still see the bisect log with:  git bisect log  # in the correct VERSION dir, or review the main log file (ref MAINLOG variable)

# User variables
VERSION=11.7                                                        # Use the earliest major version affected by the bug
SKIP_NON_SAME_VERSION=0                                             # Skip commits which are not of the VERSION version
FEATURETREE=''                                                      # Leave blank to use /test/git-bisect/${VERSION} or set to use a feature tree in the same location (the VERSION option will be ignored)
DBG_OR_OPT='opt'                                                    # Use 'dbg' or 'opt' only
RECLONE=0                                                           # Set to 1 to reclone a tree before starting
UPDATETREE=1                                                        # Set to 1 to update the tree (git pull) before starting
BISECT_REPLAY=0                                                     # Set to 1 to do a replay rather than good/bad commit
BISECT_REPLAY_LOG='/test/git-bisect/git-bisect'                     # As manually saved with:  git bisect log > git-bisect
# WARNING: Take care to use commits from the same MariaDB server version (i.e. both from for example 10.10 etc.)
#  UPDATE: This has proven to work as well when using commits from an earlier, and older, version for the last known good commit as compared to the first known bad commit. For example, a March 2023 commit from 11.0 as the last known good commit, with a April 11.1 commit as the first known bad commit. TODO: may be good to check if disabling the "${VERSION}" match check would improve failing commit resolution. However, this would also slow down the script considerably and it may lead to more errors while building: make it optional. It would be useful in cases where the default "${VERSION}" based matching did not work or is not finegrained enough.  #LAST_KNOWN_GOOD_COMMIT='a4ef05d0d5e9aeb5c919af88db2879a19092259a'   # Revision of last known good commit
LAST_KNOWN_GOOD_COMMIT='09049fe496eea1c19cd3ce80a788fa4b75d9609e'   # Revision of last known good commit
FIRST_KNOWN_BAD_COMMIT='2447dda2c004fdc996372da32aeff2c7a871c70e'   # Revision of first known bad commit
TESTCASE='/test/in18.sql'                                           # The testcase to be tested
UBASAN=0                                                            # Set to 1 to use UBASAN builds instead (UBSAN+ASAN)
REPLICATION=0                                                       # Set to 1 to use replication (./start_replication)
USE_PQUERY=0                                                        # Uses pquery if set to 1, otherwise the CLI is used
UNIQUEID='SIGSEGV|list_delete|hp_close|heap_close|closefrm'         # The UniqueID to scan for [Exclusive]
TEXT=''                                                             # The string to scan for in the error log [Exclusive]
# [Exclusive]: i.e. UNIQUEID and TEXT are mutually exclusive: do not set both
# And, leave both UNIQUEID and TEXT empty to scan for core files instead
# i.e. 3 different modes in total: UNIQUEID, TEXT or core files scan

# Script variables, do not change
RANDOM=$(date +%s%N | cut -b10-19 | sed 's|^[0]\+||')
SEED="${RANDOM}${RANDOM}"
MAINLOG="/test/git-bisect/bisect.log"
TMPLOG1="/tmp/git-bisect-${SEED}.out"
TMPLOG2="/tmp/git-bisect-build_${SEED}.exitcode"

die(){
  echo "$2"; exit $1
}

if [ "${DBG_OR_OPT}" != 'dbg' -a "${DBG_OR_OPT}" != 'opt' ]; then
  echo "DBG_OR_OPT variable is incorrectly set: use 'dbg' or 'opt' only"
  exit 1
elif [[ "${VERSION}" != "10."* && "${VERSION}" != "11."* && "${FEATURETREE}" == "" ]]; then
  echo "Version (${VERSION}) does not look correct"
  exit 1
elif [ ! -z "${UNIQUEID}" -a ! -z "${TEXT}" ]; then
  echo "Both UNIQUEID and TEXT were set. Please only specify one of them"
  exit 1
elif [ -z "${LAST_KNOWN_GOOD_COMMIT}" -o -z "${FIRST_KNOWN_BAD_COMMIT}" ]; then
  echo "LAST_KNOWN_GOOD_COMMIT or FIRST_KNOWN_BAD_COMMIT (or both) setting(s) missing"
  exit 1
elif [ ! -r "${HOME}/mariadb-qa/build_mdpsms_${DBG_OR_OPT}.sh" ]; then
  echo "${HOME}/mariadb-qa/build_mdpsms_${DBG_OR_OPT}.sh missing. Try cloning mariadb-qa again from Github into your home directory"
  if [ "${UBASAN}" -eq 1 ]; then
    echo "(note: UBASAN=1 so a UBASAN build would have been used to build the server in any case, however the script looks for this script above, as a simple verification whetter mariadb-qa was cloned and is generally ready to be used)"
  fi
  exit 1
elif [ ! -r "${HOME}/start" ]; then
  echo "${HOME}/start missing. Try running ${HOME}/mariadb-qa/linkit"
  exit 1
elif [ "${BISECT_REPLAY}" -eq 1 -a ! -r "${BISECT_REPLAY_LOG}" ]; then
  echo "BISECT_REPLAY Enabled, yet BISECT_REPLAY_LOG (${BISECT_REPLAY_LOG}) cannot read by this script"
  exit 1
elif [ ! -r "${TESTCASE}" ]; then
  echo "The testcase specified; '${TESTCASE}' is not readable"
  exit 1
elif [ "${STY}" == "" ]; then
  echo "Not a screen, restarting myself inside a screen"
  screen -admS "git-bisect" bash -c "$0;bash"
  sleep 1
  screen -d -r "git-bisect"
  return 2> /dev/null; exit 0
fi

rm -f "${MAINLOG}"
cd /test || die 1 '/test does not exist'
mkdir -p git-bisect || die 1 '/test/git-bisect could not be created'
echo 'Changing directory to /test/git-bisect' | tee -a "${MAINLOG}"
cd git-bisect || die 1 'could not change directory to git-bisect'
if [ ! -z "${FEATURETREE}" ]; then
  VERSION="${FEATURETREE}"
fi
if [ "${RECLONE}" -eq 1 ]; then
  rm -Rf "${VERSION}"
  git clone --recurse-submodules -j20 --branch="${VERSION}" https://github.com/MariaDB/server.git "${VERSION}"
  cd "${VERSION}" || die 1 "Version ${VERSION} does not exist, or could not be cloned, or similar"
else
  if [ -d ${VERSION} ]; then
    cd "${VERSION}" || die 1 "While version ${VERSION} directory existed, we could not change directory to it"
  else
    git clone --recurse-submodules -j20 --branch="${VERSION}" https://github.com/MariaDB/server.git "${VERSION}"
    cd "${VERSION}" || die 1 "Version ${VERSION} does not exist, or could not be cloned, or similar"
  fi
fi

if [ ! -z "${UNIQUEID}" ]; then
  echo "Searching for UniqueID Bug: '${UNIQUEID}'" | tee -a "${MAINLOG}"
elif [ ! -z "${TEXT}" ]; then
  echo "Searching for Error log text Bug: '${TEXT}'" | tee -a "${MAINLOG}"
else
  echo "Searching for core files in the data directory to validate issue occurrence" | tee -a "${MAINLOG}"
fi

bisect_good(){
  cd "/test/git-bisect/${VERSION}" || die 1 "Could not change directory to /test/git-bisect/${VERSION}"
  rm -f ${TMPLOG1}
  git bisect good 2>&1 | grep -v 'warning: unable to rmdir' | tee ${TMPLOG1}
  cat "${TMPLOG1}" >> "${MAINLOG}"
  if grep -qi 'first bad commit' ${TMPLOG1}; then
    rm -f ${TMPLOG1}
    echo "Finished. Use 'cd /test/git-bisect/${VERSION} && git bisect log' to see the full git bisect log" | tee -a "${MAINLOG}"
    exit 0
  fi
  rm -f ${TMPLOG1}
}

bisect_bad(){
  cd "/test/git-bisect/${VERSION}" || die 1 "Could not change directory to /test/git-bisect/${VERSION}"
  rm -f ${TMPLOG1}
  git bisect bad 2>&1 | grep -v 'warning: unable to rmdir' | tee ${TMPLOG1}
  cat "${TMPLOG1}" >> "${MAINLOG}"
  if grep -qi 'first bad commit' ${TMPLOG1}; then
    echo "Finished: $(grep 'first bad commit' ${TMPLOG1})" | tee -a "${MAINLOG}"
    grep -A5 '^commit' /test/git-bisect/bisect.log
    echo '--'
    echo "Use 'cat ${MAINLOG}' to see the full git-bisect.sh log'" | tee -a "${MAINLOG}"
    echo "Use 'cd /test/git-bisect/${VERSION} && git bisect log' to see the actual git bisect log" | tee -a "${MAINLOG}"
    rm -f ${TMPLOG1}
    exit 0
  fi
  rm -f ${TMPLOG1}
}

# Git setup
git bisect reset 2>&1 | grep -v 'We are not bisecting' | tee -a "${MAINLOG}"  # Remove any previous bisect run data
git reset --hard | tee -a "${MAINLOG}"  # Revert tree to mainline
if [ "${?}" != "0" ]; then
  echo "Assert: git reset --hard failed with a non-0 exit status, please check the output above or the logfile ${MAINLOG}"
  exit 1
fi
git clean -xfd | tee -a "${MAINLOG}"    # Cleanup tree
if [ "${?}" != "0" ]; then
  echo "Assert: git clean -xfd failed with a non-0 exit status, please check the output above or the logfile ${MAINLOG}"
  exit 1
fi
git checkout --force --recurse-submodules "${VERSION}" | tee -a "${MAINLOG}"  # Ensure we have the right version
if [ "${?}" != "0" ]; then
  echo "Assert: git checkout --force --recurse-submodules '${VERSION}' failed with a non-0 exit status, please check the output above or the logfile ${MAINLOG}"
  exit 1
fi
if [ "${UPDATETREE}" -eq 1 ]; then
  git pull --recurse-submodules | tee -a "${MAINLOG}"  # Ensure we have the latest version
  if [ "${?}" != "0" ]; then
    echo "Assert: git pull --recurse-submodules failed with a non-0 exit status, please check the output above or the logfile ${MAINLOG}"
    exit 1
  fi
fi
git bisect start | tee -a "${MAINLOG}"  # Start bisect run
if [ "${?}" != "0" ]; then
  echo "Assert: git bisect start failed with a non-0 exit status, please check the output above or the logfile ${MAINLOG}"
  exit 1
fi
if [ "${BISECT_REPLAY}" -eq 1 ]; then
  git bisect replay "${BISECT_REPLAY_LOG}" | tee -a "${MAINLOG}"
  if [ "${?}" != "0" ]; then
    echo "git bisect replay \"${BISECT_REPLAY_LOG}\" failed. Terminating for manual debugging." | tee -a "${MAINLOG}"
    exit 1
  else
    echo "git bisect replay \"${BISECT_REPLAY_LOG}\" succeeded. Proceding with regular git bisecting." | tee -a "${MAINLOG}"
  fi
else
  git bisect bad  "${FIRST_KNOWN_BAD_COMMIT}" | tee -a "${MAINLOG}"  # Starting point, bad
  if [ "${?}" != "0" ]; then
    echo "Bad revision input failed. Terminating for manual debugging. Possible reasons: you may have used a revision of a feature branch, not trunk, have a typo in the revision, or the current tree being used is not recent enough (try 'git pull' or set RECLONE=1 inside the script)."
    exit 1
  fi
  git bisect good "${LAST_KNOWN_GOOD_COMMIT}" | tee -a "${MAINLOG}"  # Starting point, good
  if [ "${?}" != "0" ]; then
    echo "Good revision input failed. Terminating for manual debugging. Possible reasons: you may have used a revision of a feature branch, not trunk, have a typo in the revision, or the current tree being used is not recent enough (try 'git pull' or set RECLONE=1 inside the script)."
    exit 1
  fi
fi

# Note that the starting point may not point git to a valid commit to test. i.e. git bisect may jump to a commit
# which was done via a merge in the tree where the current branch is the second parent and not the first one, with
# the result that the tree version (as seen in the VERSION file) is different from the $VERSION needing to be tested.
# For this, the script (ref below) will use 'git bisect skip' until it has located a commit with the correct $VERSION,
# Unless SKIP_NON_SAME_VERSION=1 in which case all commits will be tested and none will be skipped, even if the
# version of the commit at hand does not match $VERSION
LAST_TESTED_COMMIT=
while :; do
  CUR_VERSION=;CUR_COMMIT=
  while :; do
    source ./VERSION
    CUR_VERSION="${MYSQL_VERSION_MAJOR}.${MYSQL_VERSION_MINOR}"
    CUR_COMMIT="$(git log | head -n1 | tr -d '\n')"
    CUR_DATE="$(git log | head -n4 | tail -n1 | sed 's|Date:[ \t]*||;s|[ \t]*+.*||' | tr -d '\n')"
    if [ "${CUR_VERSION}" != "${VERSION}" ]; then
      if [ "${SKIP_NON_SAME_VERSION}" == "1" ]; then
        echo "|> ${CUR_COMMIT} (${CUR_DATE}) is version ${CUR_VERSION}, skipping..." | tee -a "${MAINLOG}"
        git bisect skip 2>&1 | grep -v 'warning: unable to rmdir' | tee -a "${MAINLOG}"
      else
        echo "|> ${CUR_COMMIT} (${CUR_DATE}) is version ${CUR_VERSION}, and SKIP_NON_SAME_VERSION=0, proceeding..." | tee -a "${MAINLOG}"
        break
      fi
      if grep -qiE 'There are only.*skip.*ped commits left to test|The first bad commit could be any of' "${MAINLOG}"; then
        exit 1
        break
      fi
      continue
    elif [ "${CUR_COMMIT}" == "${LAST_TESTED_COMMIT}" ]; then
      # This seems to happen when for example a patch was attempted to be applied but did not apply correctly or source files were changed - i.e. the tree state is not clean anymore. TODO: this is a provisional patch; it may not work. Setting RECLONE=1 is another way to work around such issues (full reclone)
      echo "|> ${CUR_COMMIT} is the same as the last tested commit ${LAST_TESTED_COMMIT}, skipping..." | tee -a "${MAINLOG}"
      git bisect skip 2>&1 | grep -v 'warning: unable to rmdir' | tee -a "${MAINLOG}"
    else
      echo "|> ${CUR_COMMIT} (${CUR_DATE}) is version ${CUR_VERSION}, proceeding..." | tee -a "${MAINLOG}"
      LAST_TESTED_COMMIT="${CUR_COMMIT}"
      break
    fi
  done
  if grep -qiE 'There are only.*skip.*ped commits left to test|The first bad commit could be any of' "${MAINLOG}"; then
    exit 1
    break
  fi
  CONTINUE_MAIN_LOOP=0
  OUTCOME_BUILD=
  SCREEN_NAME=
  while :; do
    echo "|> Cleaning up any previous builds in /test/git-bisect" | tee -a "${MAINLOG}"
    rm -Rf /test/git-bisect/MD*
    SCREEN_NAME="git-bisect-build.${SEED}"
    echo "|> Building revision in a screen session: use  screen -d -r '${SCREEN_NAME}'  to see the build process" | tee -a "${MAINLOG}"
    rm -f ${TMPLOG2}
    if [ "${UBASAN}" -eq 1 ]; then
      screen -admS "${SCREEN_NAME}" bash -c "${HOME}/mariadb-qa/build_mdpsms_${DBG_OR_OPT}_san.sh; echo \"\${?}\" > ${TMPLOG2}"
    else
      screen -admS "${SCREEN_NAME}" bash -c "${HOME}/mariadb-qa/build_mdpsms_${DBG_OR_OPT}.sh; echo \"\${?}\" > ${TMPLOG2}"
    fi
    while [ "$(screen -ls | grep -o "${SCREEN_NAME}")" == "${SCREEN_NAME}" ]; do
      sleep 2
    done
    sleep 2
    OUTCOME_BUILD="$(cat ${TMPLOG2} 2>/dev/null | head -n1 | tr -d '\n')"
    if [ "${OUTCOME_BUILD}" != "0" ]; then
      echo "|> Build failure... Skipping revision ${CUR_COMMIT}" | tee -a "${MAINLOG}"
      git bisect skip 2>&1 | grep -v 'warning: unable to rmdir' | tee -a "${MAINLOG}"  # The 'unable to rmdir' is just for 3rd party/plugins etc. it not a fatal error
      CONTINUE_MAIN_LOOP=1
      break  # Failed build, CONTINUE_MAIN_LOOP=1 set, break, then 'continue' in main loop for next revision
    else
      rm -f ${TMPLOG2}  # Only delete log if build succeeded
      echo "|> Build successful... Testing revision ${CUR_COMMIT}" | tee -a "${MAINLOG}"
      break  # Successful build, continue with test (CONTINUE_MAIN_LOOP=0)
    fi
  done
  if [ "${CONTINUE_MAIN_LOOP}" != "0" ]; then
    CONTINUE_MAIN_LOOP=0
    continue
  fi
  cd /test/git-bisect || die 1 'Could not change directory to /test/git-bisect'
  if [ "${SKIP_NON_SAME_VERSION}" == "1" ]; then
    if [ "${UBASAN}" -eq 1 ]; then
      TEST_DIR="$(ls -d UBASAN_MD$(date +'%d%m%y')*${VERSION}*${DBG_OR_OPT} 2>/dev/null)"
    else
      TEST_DIR="$(ls -d MD$(date +'%d%m%y')*${VERSION}*${DBG_OR_OPT} 2>/dev/null)"
    fi
  else
    if [ "${UBASAN}" -eq 1 ]; then
      TEST_DIR="$(ls -d UBASAN_MD$(date +'%d%m%y')*${CUR_VERSION}*${DBG_OR_OPT} 2>/dev/null)"
    else
      TEST_DIR="$(ls -d MD$(date +'%d%m%y')*${CUR_VERSION}*${DBG_OR_OPT} 2>/dev/null)"
    fi
  fi
  if [ -z "${TEST_DIR}" ]; then
    echo "Assert: TEST_DIR is empty" | tee -a "${MAINLOG}"
    exit 1
  elif [ ! -d "${TEST_DIR}" ]; then
    echo "Assert: TEST_DIR (${TEST_DIR}) does not exist" | tee -a "${MAINLOG}"
    exit 1
  fi
  cd "${TEST_DIR}" || die 1 "Could not change directory to TEST_DIR (${TEST_DIR})"
  ${HOME}/start 2>&1 | grep -vE 'To get a |^Note: |Adding scripts: '  # Init BASEDIR with runtime scripts
  cp ${TESTCASE} ./in.sql
  if [ "${REPLICATION}" -eq 0 ]; then
    ./all_no_cl >>"${MAINLOG}" 2>&1 || die 1 "Could not execute ./all_no_cl in ${PWD}"  # wipe, start
    #DEBUG# read -p 'all_no_cl done'
    if [ "${USE_PQUERY}" -eq 1 ]; then
      ./test_pquery >>"${MAINLOG}" 2>&1 || die 1 "Could not execute ./test_pquery in ${PWD}"  # ./in.sql exec test
    else
      ./test >>"${MAINLOG}" 2>&1 || die 1 "Could not execute ./test in ${PWD}"  # ./in.sql exec test
    fi
    #DEBUG# read -p 'test done'
    echo "$(./stop 2>&1)" >/dev/null 2>&1  # Output is removed as otherwise it may contain, for example, 'bin/mariadb-admin: connect to server at 'localhost' failed' if the server already crashed due to testcase exec
    ./kill >/dev/null 2>&1
  else
    export SRNOCL=1  # No CLI when using ./start_replication
    ./start_replication 2>&1 | grep -vE 'To get a |^Note: |Adding scripts: '
    if [ "${USE_PQUERY}" -eq 1 ]; then
      ./test_pquery >>"${MAINLOG}" 2>&1 || die 1 "Could not execute ./test_pquery in ${PWD}"  # ./in.sql exec test
    else
      ./test >>"${MAINLOG}" 2>&1 || die 1 "Could not execute ./test in ${PWD}"  # ./in.sql exec test
    fi
    ./stop_replication >/dev/null 2>&1 # Output is removed, ref above
    ./kill_replication >/dev/null 2>&1
  fi
  if [ ! -z "${UNIQUEID}" ]; then
    UNIQUEID_CHECK="$(${HOME}/t)"
    if [ "${UNIQUEID_CHECK}" == "${UNIQUEID}" ]; then
      echo "UniqueID Bug found: ${UNIQUEID_CHECK} -> bad commit" | tee -a "${MAINLOG}"
      bisect_bad
    else
      echo "UniqueID Bug not found: '$(echo "${UNIQUEID_CHECK}" | sed 's|Assert: n|N|;s|found.*, and|found, and|;s| for all logs.*||')' seen versus target '${UNIQUEID}' -> good commit" | tee -a "${MAINLOG}"
      bisect_good
    fi
    UNIQUEID_CHECK=
  elif [ ! -z "${TEXT}" ]; then
    if [ ! -z "$(grep "${TEXT}" log/master.err)" ]; then
      echo 'TEXT Bug found; bad commit' | tee -a "${MAINLOG}"
      bisect_bad
    else
      echo 'TEXT Bug not found; good commit' | tee -a "${MAINLOG}"
      bisect_good
    fi
  else
    if [ $(ls -l data/*core* 2>/dev/null | wc -l) -ge 1 ]; then
      echo 'Core file found in ./data; bad commit' | tee -a "${MAINLOG}"
      bisect_bad
    else
      echo 'No core file found in ./data; good commit' | tee -a "${MAINLOG}"
      bisect_good
    fi
  fi
done

# For for example checking YACC compilation errors, you can use 'git bisect run':
# For automatic good/bad selection based on exit code, use 'git bisect run ./command_which_provides_exit_code':
# git bisect reset && git bisect start
# git bisect bad ...rev...
# git bisect good ...rev...
# git bisect run yacc -Wother -Wyacc -Wdeprecated --verbose sql/sql_yacc.yy 2>/dev/null  # 1 on error
# This will very quickly find the revision where the YACC error was introduced
