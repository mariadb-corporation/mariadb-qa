#!/bin/bash
# Created by Roel Van de Paar, MariaDB
set +H

# Note: if this script is terminated, you can still see the bisect log with:  git bisect log  (run in the correct VERSION dir). You can also review the main log file (ref MAINLOG variable) i.e. bisect.log

# User variables
DBG_OR_OPT='opt'                                                    # Use 'dbg' or 'opt' only
VERSION=12.0                                                        # Use the earliest major version affected by the bug
ES=0                                                                # If set to 1, MariaDB Enterprise Server will be used instead of MariaDB Community Server
SKIP_NON_SAME_VERSION=0                                             # Skip commits which are not of the VERSION version. If you are confident you know what version a bug was introduced in, and this version is specified in VERSION above, set this to 1, otherwise set it to 0. Also, if there are build errors in older revisions, setting this to 0 may help. Recommended in any case: 0, especially in older versions, which regularly yield build issues on newer systems; it may make the bisect quicker/better/easier in such cases
FEATURETREE=''                                                      # Leave blank to use /test/git-bisect/${VERSION} or set to use a feature tree in the same location (the VERSION option will be ignored)
RECLONE=1                                                           # Set to 1 to reclone a tree before starting
UPDATETREE=1                                                        # Set to 1 to update the tree (git pull) before starting
BISECT_REPLAY=0                                                     # Set to 1 to do a replay rather than good/bad commit
BISECT_REPLAY_LOG='/test/git-bisect/git-bisect'                     # As manually saved with:  git bisect log > git-bisect
# WARNING: Take care to use commits from the same MariaDB server version (i.e. both from for example 10.10 etc.)
#  UPDATE: This has proven to work as well when using commits from an earlier, and older, version for the last known good commit as compared to the first known bad commit. For example, a March 2023 commit from 11.0 as the last known good commit, with a April 11.1 commit as the first known bad commit. TODO: may be good to check if disabling the "${VERSION}" match check would improve failing commit resolution. However, this would also slow down the script considerably and it may lead to more errors while building: make it optional. It would be useful in cases where the default "${VERSION}" based matching did not work or is not finegrained enough.
LAST_KNOWN_GOOD_COMMIT='22efc2c784e1b7199fb5804e6330168277ea7dce'   # Revision of last known good commit
FIRST_KNOWN_BAD_COMMIT='f1102da37a3dcdc8b92e0205f0a8bd878704b168'   # Revision of first known bad commit
# To obtain the first commit for a given branch/version, some examples (after full branch checkouts): 
# /test/git-bisect/12.1 $ git log origin/12.0..12.1 --oneline | tail -1
# 72b666b837eb16819f8f3de3e739a582dbbf4b53  # This is the first 12.1 commit
# /test/git-bisect/12.0 $ git log origin/11.8..12.0 --oneline | tail -1
# c92add291e636c797e6d6ddca605905541b2a441  # This is the first 12.0 commit
# Use git checkout --recurse-submodules --force c92add291e636c797e6d6ddca605905541b2a441 to obtain this
TESTCASE='/test/in37.sql'                                           # The testcase to be tested
UBASAN=0                                                            # Set to 1 to use UBASAN builds instead (UBSAN+ASAN)
REPLICATION=0                                                       # Set to 1 to use replication (./start_replication)
USE_PQUERY=0                                                        # Uses pquery if set to 1, otherwise the CLI is used
UNIQUEID=""                                                         # The UniqueID to scan for [Exclusive]
TEXT=""                                                             # The string to scan for in the error log [Exclusive]
CLI_TEXT="Write_rows_v1"                                                         # The string to scan for in CLI output [Exclusive]
# [Exclusive]: UNIQUEID, TEXT and CLI_TEXT are all mutually exclusive: setting one should exclude all others (i.e. set empty)
# Finally, leave all three (UNIQUEID, TEXT and CLI_TEXT) empty to scan for core files instead
# i.e. 4 different modes in total: UNIQUEID, TEXT, CLI_TEXT or core files scan
# Note that TEXT and CLI_TEXT are regex-capable and case-sensitive

# Script variables, do not change
RANDOM=$(date +%s%N | cut -b10-19 | sed 's|^[0]\+||')
SEED="${RANDOM}${RANDOM}"
MAINLOG="/test/git-bisect/bisect.log"
TMPLOG1="/tmp/git-bisect-${SEED}.out"
TMPLOG2="/tmp/git-bisect-build_${SEED}.exitcode"
SEEN_ONCE=''
export ENV_GIT_BISECT='1'

clear_env(){
  export ENV_GIT_BISECT=
  export -n ENV_GIT_BISECT
  ENV_GIT_BISECT=
}

die(){
  echo "$2"
  clear_env
  exit $1
}

# Variable checks
if [ "${ES}" -eq 1 ]; then
  CHS="../credentials_helper.source"
  if [ ! -r "${CHS}" ]; then CHS="/test/credentials_helper.source"; fi
  if [ ! -r "${CHS}" ]; then
    echo "ES=1 and ../credentials_helper.source nor /test/credentials_helper.source were found - please fix your install"
    clear_env; exit 1
  fi
  source "${CHS}"  # Call the credentials check helper script to check ~/.git-credentials provisioning
fi
MODES_SELECTED_COUNT=0
if [ ! -z "${UNIQUEID}" ]; then MODES_SELECTED_COUNT=$[ ${MODES_SELECTED_COUNT} + 1 ]; fi
if [ ! -z "${TEXT}" ]; then MODES_SELECTED_COUNT=$[ ${MODES_SELECTED_COUNT} + 1 ]; fi
if [ ! -z "${CLI_TEXT}" ]; then MODES_SELECTED_COUNT=$[ ${MODES_SELECTED_COUNT} + 1 ]; fi
if [ "${ES}" -eq 1 -a ! -z "${FEATURETREE}" ]; then
  echo "TODO: please add ES=1 with FEATURETREE='xyz' functionality, not implemented yet"
  clear_env; exit 1
elif [ "${DBG_OR_OPT}" != 'dbg' -a "${DBG_OR_OPT}" != 'opt' ]; then
  echo "DBG_OR_OPT variable is incorrectly set: use 'dbg' or 'opt' only"
  clear_env; exit 1
elif [[ "${VERSION}" != "10."* && "${VERSION}" != "11."* && "${VERSION}" != "12."* && "${FEATURETREE}" == "" ]]; then
  echo "Version (${VERSION}) does not look correct"
  clear_env; exit 1
elif [ ${MODES_SELECTED_COUNT} -gt 1 ]; then
  echo "Assert: too many bug scan modes set! (# set: ${MODES_SELECTED_COUNT})"
  echo "4 Specific bug scan modes are supported: Mode 1) Scan for core files (all the following mode 2/3/4 options are empty; none are set), Mode 2) UNIQUEID set; scan for specified UniqueID's, Mode 3) TEXT set; scan for specific strings in the error log, Mode 4) CLI_TEXT set; scan for specific strings in the client output"
  echo "Please ensure that only one of the [UNIQUEID, TEXT or CLI_TEXT] modes are set, or specify none of them (i.e. empty; '') to scan for core files instead"
  echo "Currently, ${MODES_SELECTED_COUNT} different modes are set, which is an impossible combination"
  clear_env; exit 1
elif [ "${USE_PQUERY}" -eq 1 -a ! -z "${CLI_TEXT}" ]; then
  echo "USE_PQUERY=1 and CLI_TEXT is set. This is not supported yet (feel free to add it). For the moment, only the vanilla mariadb/mysql client is supported (USE_PQUERY=0)."
  clear_env; exit 1
elif [ -z "${LAST_KNOWN_GOOD_COMMIT}" -o -z "${FIRST_KNOWN_BAD_COMMIT}" ]; then
  echo "LAST_KNOWN_GOOD_COMMIT or FIRST_KNOWN_BAD_COMMIT (or both) setting(s) missing"
  clear_env; exit 1
elif [ ! -r "${HOME}/mariadb-qa/build_mdpsms_${DBG_OR_OPT}.sh" ]; then
  echo "${HOME}/mariadb-qa/build_mdpsms_${DBG_OR_OPT}.sh missing. Try cloning mariadb-qa again from Github into your home directory"
  if [ "${UBASAN}" -eq 1 ]; then
    echo "(note: UBASAN=1 so a UBASAN build would have been used to build the server in any case, however the script looks for this script above, as a simple verification whetter mariadb-qa was cloned and is generally ready to be used)"
  fi
  clear_env; exit 1
elif [ ! -r "${HOME}/start" ]; then
  echo "${HOME}/start missing. Try running ${HOME}/mariadb-qa/linkit"
  clear_env; exit 1
elif [ "${BISECT_REPLAY}" -eq 1 -a ! -r "${BISECT_REPLAY_LOG}" ]; then
  echo "BISECT_REPLAY Enabled, yet BISECT_REPLAY_LOG (${BISECT_REPLAY_LOG}) cannot read by this script"
  clear_env; exit 1
elif [ ! -r "${TESTCASE}" ]; then
  echo "The testcase specified; '${TESTCASE}' is not readable"
  clear_env; exit 1
elif [ "${STY}" == "" ]; then
  echo "Not a screen, restarting myself inside a screen"
  screen -admS "git-bisect" bash -c "export ENV_GIT_BISECT='1';$0;bash"
  sleep 1
  screen -d -r "git-bisect"
  clear_env
  return 2> /dev/null; exit 0
fi

rm -f "${MAINLOG}"
echo "Testing testcase ${TESTCASE}:"
echo '--------------------------------------------';
cat ${TESTCASE} | grep -v '^[ \t]*$'
echo '--------------------------------------------';
echo "|> [*] A leading '[*]', like to the one in this comment, shows that git-bisect.sh saw the bug reproduced in-run at least once"
echo "|> If you do not observe this '[*]' marker during the bisect run, then please make sure your testcase (${TESTCASE}) is correctly triggering a bug in at least your first indicated bad commit ${FIRST_KNOWN_BAD_COMMIT}, in version ${VERSION}, build as an ${DBG_OR_OPT} build (with/while using UBASAN: ${UBASAN}, REPLICATION: ${REPLICATION}, USE_PQUERY: ${USE_PQUERY}) (1: yes, 0: no). You may also want to verify that the correct failure type/mode is being used; cores (none of the following options set), or [UNIQUEID, TEXT or TEXT_CLI] (one of them set)."
sleep 3  # Give user time to see the output
echo "|> Commencing Bisect"
cd /test || die 1 '/test does not exist'
mkdir -p git-bisect || die 1 '/test/git-bisect could not be created'
echo 'Changing directory to /test/git-bisect' | tee -a "${MAINLOG}"
cd git-bisect || die 1 'could not change directory to git-bisect'
if [ ! -z "${FEATURETREE}" ]; then
  VERSION="${FEATURETREE}"
fi
if [ "${RECLONE}" -eq 1 ]; then
  if [ "${ES}" -eq 1 ]; then
    rm -Rf "${VERSION}"
    git clone --recurse-submodules -j20 --branch="${VERSION}-enterprise" https://github.com/mariadb-corporation/MariaDBEnterprise "${VERSION}"  # We clone the ES branch into ./${VERSION} for simplicity in later handling
    cd "${VERSION}" || die 1 "Version ${VERSION} does not exist, or could not be cloned, or similar"
  else
    rm -Rf "${VERSION}"
    if [ "${VERSION}" == "12.0" ]; then  # Update as trunk changes to a new version 
      git clone --recurse-submodules -j20 https://github.com/MariaDB/server.git "${VERSION}"
    else
      git clone --recurse-submodules -j20 --branch="${VERSION}" https://github.com/MariaDB/server.git "${VERSION}"
    fi
    cd "${VERSION}" || die 1 "Version ${VERSION} does not exist, or could not be cloned, or similar"
  fi
else
  if [ -d ${VERSION} ]; then
    cd "${VERSION}" || die 1 "While version ${VERSION} directory existed, this script could not change directory to it"
  else  # RECLONE=0 but we do not have the directory in any case; clone it
    if [ "${ES}" -eq 1 ]; then
      git clone --recurse-submodules -j20 --branch="${VERSION}-enterprise" https://github.com/mariadb-corporation/MariaDBEnterprise "${VERSION}"  # Idem as above
      cd "${VERSION}" || die 1 "Version ${VERSION} does not exist, or could not be cloned, or similar"
    else
      git clone --recurse-submodules -j20 --branch="${VERSION}" https://github.com/MariaDB/server.git "${VERSION}"
      cd "${VERSION}" || die 1 "Version ${VERSION} does not exist, or could not be cloned, or similar"
    fi
  fi
fi

if [ ! -z "${UNIQUEID}" ]; then
  echo "Searching for UniqueID Bug: '${UNIQUEID}'" | tee -a "${MAINLOG}"
elif [ ! -z "${TEXT}" ]; then
  echo "Searching for Error log text Bug: '${TEXT}'" | tee -a "${MAINLOG}"
elif [ ! -z "${CLI_TEXT}" ]; then
  echo "Searching for CLI output text Bug: '${CLI_TEXT}'" | tee -a "${MAINLOG}"
else
  echo "Searching for core files in the data directory to validate issue occurrence" | tee -a "${MAINLOG}"
fi

bisect_good(){
  cd "/test/git-bisect/${VERSION}" || die 1 "Could not change directory to /test/git-bisect/${VERSION}"
  rm -f ${TMPLOG1}
  git bisect good 2>&1 | grep -v 'warning: unable to rmdir' | tee ${TMPLOG1}
  # Always init/update submodules after each git bisect good/bad as those commands update the revision set
  git submodule update --init --recursive
  cat "${TMPLOG1}" >> "${MAINLOG}"
  if grep -qi 'first bad commit' ${TMPLOG1}; then
    rm -f ${TMPLOG1}
    echo "Finished. Use 'cd /test/git-bisect/${VERSION} && git bisect log' to see the full git bisect log" | tee -a "${MAINLOG}"
    clear_env; exit 0
  fi
  rm -f ${TMPLOG1}
}

bisect_bad(){
  cd "/test/git-bisect/${VERSION}" || die 1 "Could not change directory to /test/git-bisect/${VERSION}"
  rm -f ${TMPLOG1}
  git bisect bad 2>&1 | grep -v 'warning: unable to rmdir' | tee ${TMPLOG1}
  SEEN_ONCE='[*] '
  # Always init/update submodules after each git bisect good/bad as those commands update the revision set
  git submodule update --init --recursive
  cat "${TMPLOG1}" >> "${MAINLOG}"
  if grep -qi 'first bad commit' ${TMPLOG1}; then
    echo "Finished: $(grep 'first bad commit' ${TMPLOG1})" | tee -a "${MAINLOG}"
    grep -A5 '^commit' /test/git-bisect/bisect.log
    echo '--'
    echo "Use 'cat ${MAINLOG}' to see the full git-bisect.sh log'" | tee -a "${MAINLOG}"
    echo "Use 'cd /test/git-bisect/${VERSION} && git bisect log' to see the actual git bisect log" | tee -a "${MAINLOG}"
    rm -f ${TMPLOG1}
    clear_env; exit 0
  fi
  rm -f ${TMPLOG1}
}

# Git setup
git bisect reset 2>&1 | grep -v 'We are not bisecting' | tee -a "${MAINLOG}"  # Remove any previous bisect run data
git reset --hard | tee -a "${MAINLOG}"  # Revert tree to mainline
if [ "${?}" != "0" ]; then
  echo "Assert: git reset --hard failed with a non-0 exit status, please check the output above or the logfile ${MAINLOG}"
  clear_env; exit 1
fi
git clean -xfd | tee -a "${MAINLOG}"    # Cleanup tree
if [ "${?}" != "0" ]; then
  echo "Assert: git clean -xfd failed with a non-0 exit status, please check the output above or the logfile ${MAINLOG}"
  clear_env; exit 1
fi
# Ensure we have the right version
if [ "${ES}" == "1" ]; then
  git checkout --recurse-submodules --force "${VERSION}-enterprise" | tee -a "${MAINLOG}"
  if [ "${?}" != "0" ]; then
    echo "Assert: git checkout --recurse-submodules --force '${VERSION}-enterprise' failed with a non-0 exit status, please check the output above or in the logfile ${MAINLOG}"
    clear_env; exit 1
  fi
else
  git checkout --recurse-submodules --force "${VERSION}" | tee -a "${MAINLOG}"
  if [ "${?}" != "0" ]; then
    echo "Assert: git checkout --recurse-submodules --force '${VERSION}' failed with a non-0 exit status, please check the output above or in the logfile ${MAINLOG}"
    clear_env; exit 1
  fi
fi
if [ "${UPDATETREE}" -eq 1 ]; then
  git pull --recurse-submodules | tee -a "${MAINLOG}"  # Ensure we have the latest version
  if [ "${?}" != "0" ]; then
    echo "Assert: git pull --recurse-submodules failed with a non-0 exit status, please check the output above or the logfile ${MAINLOG}"
    clear_env; exit 1
  fi
fi
git bisect start | tee -a "${MAINLOG}"  # Start bisect run
if [ "${?}" != "0" ]; then
  echo "Assert: git bisect start failed with a non-0 exit status, please check the output above or the logfile ${MAINLOG}"
  clear_env; exit 1
fi
if [ "${BISECT_REPLAY}" -eq 1 ]; then
  git bisect replay "${BISECT_REPLAY_LOG}" | tee -a "${MAINLOG}"
  if [ "${?}" != "0" ]; then
    echo "git bisect replay \"${BISECT_REPLAY_LOG}\" failed. Terminating for manual debugging." | tee -a "${MAINLOG}"
    clear_env; exit 1
  else
    echo "git bisect replay \"${BISECT_REPLAY_LOG}\" succeeded. Proceding with regular git bisecting." | tee -a "${MAINLOG}"
  fi
else
  git bisect bad "${FIRST_KNOWN_BAD_COMMIT}" | tee -a "${MAINLOG}"  # Starting point, bad
  if [ "${?}" != "0" ]; then
    echo "Bad revision input failed. Terminating for manual debugging. Possible reasons: you may have used a revision of a feature branch, not trunk, have a typo in the revision, or the current tree being used is not recent enough (try 'git pull' or set RECLONE=1 inside the script)."
    clear_env; exit 1
  fi
  # Always init/update submodules after each git bisect good/bad as those commands update the revision set
  git submodule update --init --recursive
  git bisect good "${LAST_KNOWN_GOOD_COMMIT}" | tee -a "${MAINLOG}"  # Starting point, good
  if [ "${?}" != "0" ]; then
    echo "Good revision input failed. Terminating for manual debugging. Possible reasons: you may have used a revision of a feature branch, not trunk, have a typo in the revision, or the current tree being used is not recent enough (try 'git pull' or set RECLONE=1 inside the script)."
    clear_env; exit 1
  fi
  # Always init/update submodules after each git bisect good/bad as those commands update the revision set
  git submodule update --init --recursive
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
  COUNT_SAME_VERSION=0
  while :; do
    source ./VERSION
    CUR_VERSION="${MYSQL_VERSION_MAJOR}.${MYSQL_VERSION_MINOR}"
    CUR_COMMIT="$(git log | head -n1 | tr -d '\n')"
    CUR_DATE="$(git log | head -n4 | grep '^Date:' | head -n1 | sed 's|Date:[ \t]*||;s|[ \t]*+.*||' | tr -d '\n')"
    if [ "${CUR_VERSION}" != "${VERSION}" ]; then
      if [ "${SKIP_NON_SAME_VERSION}" == "1" ]; then
        echo "|> ${SEEN_ONCE}${CUR_COMMIT} (${CUR_DATE}) is ver ${CUR_VERSION}, and SKIP_NON_SAME_VERSION=1: skipping.." | tee -a "${MAINLOG}"
        git bisect skip 2>&1 | grep -v 'warning: unable to rmdir' | tee -a "${MAINLOG}"  # rmdir: ref above (idem)
      else
        echo "|> ${SEEN_ONCE}${CUR_COMMIT} (${CUR_DATE}) is ver ${CUR_VERSION}, and SKIP_NON_SAME_VERSION=0: proceeding.." | tee -a "${MAINLOG}"
        break
      fi
      if grep -qiE 'There are only.*skip.*ped commits left to test|The first bad commit could be any of' "${MAINLOG}"; then
        echo '|> Consider re-running SKIP_NON_SAME_VERSION=0, or manually test the remaining commits if there are only a few'
        clear_env; exit 1
        break
      fi
      continue
    elif [ "${CUR_COMMIT}" == "${LAST_TESTED_COMMIT}" ]; then
      echo "|> ${SEEN_ONCE}${CUR_COMMIT} is the same as the last tested commit ${LAST_TESTED_COMMIT}"
      COUNT_SAME_VERSION=$[ ${COUNT_SAME_VERSION} + 1 ]
      if [ ${COUNT_SAME_VERSION} -gt 2 ]; then
        echo "|> ${SEEN_ONCE}${CUR_COMMIT} is the same as the last tested commit ${LAST_TESTED_COMMIT}, and this has happened trice consecutively: finishing.." | tee -a "${MAINLOG}"
        git bisect skip 2>&1 | grep -v 'warning: unable to rmdir' | tee -a "${MAINLOG}"  # rmdir: ref above (idem)
        if grep -qiE 'There are only.*skip.*ped commits left to test|The first bad commit could be any of' "${MAINLOG}"; then
          echo '|> Consider re-running SKIP_NON_SAME_VERSION=0, or manually test the remaining commits if there are only a few'
        fi
        clear_env; exit 1
        break
      fi
    else
      echo "|> ${SEEN_ONCE}${CUR_COMMIT} (${CUR_DATE}) is version ${CUR_VERSION}, proceeding.." | tee -a "${MAINLOG}"
      LAST_TESTED_COMMIT="${CUR_COMMIT}"
      break
    fi
  done
  if grep -qiE 'There are only.*skip.*ped commits left to test|The first bad commit could be any of' "${MAINLOG}"; then
    clear_env; exit 1
    break
  fi
  CONTINUE_MAIN_LOOP=0
  OUTCOME_BUILD=
  SCREEN_NAME=
  while :; do
    echo "|> ${SEEN_ONCE}Cleaning up any previous builds in /test/git-bisect" | tee -a "${MAINLOG}"
    rm -Rf /test/git-bisect/*MD*mariadb*
    SCREEN_NAME="git-bisect-build.${SEED}"
    echo "|> ${SEEN_ONCE}Building revision in a screen session: use  screen -d -r '${SCREEN_NAME}'  to see the build process" | tee -a "${MAINLOG}"
    rm -f ${TMPLOG2}
    if [ "${UBASAN}" -eq 1 ]; then
      screen -admS "${SCREEN_NAME}" bash -c "${HOME}/mariadb-qa/build_mdpsms_${DBG_OR_OPT}_san.sh; echo \"\${?}\" > ${TMPLOG2}"
    else
      screen -admS "${SCREEN_NAME}" bash -c "${HOME}/mariadb-qa/build_mdpsms_${DBG_OR_OPT}.sh; echo \"\${?}\" > ${TMPLOG2}"
    fi
    while [ "$(screen -ls | grep -o "${SCREEN_NAME}")" == "${SCREEN_NAME}" ]; do
      sleep 1
    done
    sleep 3 && sync
    OUTCOME_BUILD="$(cat ${TMPLOG2} 2>/dev/null | head -n1 | tr -d '\n')"
    if [ "${OUTCOME_BUILD}" != "0" ]; then
      echo "|> ${SEEN_ONCE}Build failure.. Skipping revision ${CUR_COMMIT}" | tee -a "${MAINLOG}"
      git bisect skip 2>&1 | grep -v 'warning: unable to rmdir' | tee -a "${MAINLOG}"  # The 'unable to rmdir' is just for 3rd party/plugins etc. - it is not a fatal error
      CONTINUE_MAIN_LOOP=1
      break  # Failed build, CONTINUE_MAIN_LOOP=1 set, break, then 'continue' in main loop for next revision
    else
      rm -f ${TMPLOG2}  # Only delete log if build succeeded
      echo "|> ${SEEN_ONCE}Build successful.. Testing revision ${CUR_COMMIT}" | tee -a "${MAINLOG}"
      break  # Successful build, continue with test (CONTINUE_MAIN_LOOP=0)
    fi
  done
  if [ "${CONTINUE_MAIN_LOOP}" != "0" ]; then
    CONTINUE_MAIN_LOOP=0
    while [ -d /test/git-bisect/${VERSION}_${DBG_OR_OPT} ]; do
      # 'rm: cannot remove '12.0_dbg': Directory not empty' errors appear from time to time when there were build failures, possibly related to previous failed builds or compile threads (-j) still going while the main script has already ended. This ensures the build dir is gone
      echo "|> ${SEEN_ONCE}Part of the build dir /test/git-bisect/${VERSION}_${DBG_OR_OPT} was not deleted correctly, retrying..."
      rm -Rf /test/git-bisect/${VERSION}_${DBG_OR_OPT} 2>/dev/null
      sleep 2 && sync
    done
    continue
  fi
  cd /test/git-bisect || die 1 'Could not change directory to /test/git-bisect'
  sleep 1
  # Find the TEST_DIR name by taking the name of the tarball created in the last two minutes and removing .tar.gz
  TEST_DIR="$(find . -maxdepth 1 -type f -mmin -2 -name "*.tar.gz" -exec bash -c 'basename "{}" .tar.gz' \;)"
  if [ -z "${TEST_DIR}" ]; then
    echo "Assert: TEST_DIR is empty (no .tar.gz was created in the last two minutes by the build script)" | tee -a "${MAINLOG}"
    echo "Will try and recover by using git skip for this commit. Bisecting may fail" | tee -a "${MAINLOG}"
    cd "${VERSION}" || die 1 "Script could not change directory to ${VERSION}"
    git bisect skip 2>&1 | grep -v 'warning: unable to rmdir' | tee -a "${MAINLOG}"  # rmdir: ref above (idem)
    continue
  elif [ "$(echo "${TEST_DIR}" | wc -l)" -ne "1" ]; then
    echo "Assert: TEST_DIR does not contain exactly one line; this should not happen. The current value is:" | tee -a "${MAINLOG}"
    echo "${TEST_DIR}" | tee -a "${MAINLOG}"
    clear_env; exit 1
    break
  elif [ ! -d "${TEST_DIR}" ]; then
    echo "Assert: TEST_DIR ${TEST_DIR} does not exits" | tee -a "${MAINLOG}"
    echo "Will try and recover by using git skip for this commit. Bisecting may fail" | tee -a "${MAINLOG}"
    cd "${VERSION}" || die 1 "Script could not change directory to ${VERSION}"
    git bisect skip 2>&1 | grep -v 'warning: unable to rmdir' | tee -a "${MAINLOG}"  # rmdir: ref above (idem)
    continue
  fi
  cd "${TEST_DIR}" || die 1 "Could not change directory to TEST_DIR (${TEST_DIR})"
  ${HOME}/start 2>&1 | grep -vE 'To get a |^Note: |Adding scripts: '  # Init BASEDIR with runtime scripts
  cp ${TESTCASE} ./in.sql
  # TODO: Not all options are directly passable to 'anc' (as it has wipe and start, not just start), like some InnoDB startup options, though most are. A staged startup would resolve this for most, if not all, cases.
  # TODO: ./start_replication does not have option provisoning yet, except what is provided here as part of "# mysqld options required for replay:", but ideally it would have full master+slave etc. option handling
  OPTIONS_TO_PASS="$(grep --binary-files=text "^# mysqld options required for replay:" ./in.sql | sed 's|# mysqld options required for replay:[ ]*||' | sed 's|\t| |g;s| [ ]\+| |g;s|^[ ]\+||;s|[ ]\+$||')"
  if [ ! -z "${OPTIONS_TO_PASS}" ]; then
    if [ "${REPLICATION}" -eq 0 ]; then
      echo "Passing options '${OPTIONS_TO_PASS}' to all_no_cl"
    else
      echo "Passing options '${OPTIONS_TO_PASS}' to start_replication"
    fi
  fi
  if [ "${REPLICATION}" -eq 0 ]; then
    ./all_no_cl ${OPTIONS_TO_PASS} >>"${MAINLOG}" 2>&1 || die 1 "Could not execute ./all_no_cl ${OPTIONS} in ${PWD}"  # wipe, start
    #DEBUG# read -p 'all_no_cl done'
    if [ "${USE_PQUERY}" -eq 1 ]; then
      ./test_pquery >>"${MAINLOG}" 2>&1 || die 1 "Could not execute ./test_pquery in ${PWD}"  # ./in.sql exec test
    else
      ./test >>"${MAINLOG}" 2>&1 || die 1 "Could not execute ./test in ${PWD}"  # ./in.sql exec test
    fi
    #DEBUG# read -p 'test done'
    echo "$(./stop 2>&1)" >/dev/null 2>&1  # Output is removed as otherwise it may contain, for example, 'bin/mariadb-admin: connect to server at 'localhost' failed' if the server already crashed due to testcase exec
    sleep 1
    ./kill >/dev/null 2>&1
  else
    export SRNOCL=1  # No CLI when using ./start_replication
    ./start_replication ${OPTIONS_TO_PASS} 2>&1 | grep -vE 'To get a |^Note: |Adding scripts: '
    if [ "${USE_PQUERY}" -eq 1 ]; then
      ./test_pquery >>"${MAINLOG}" 2>&1 || die 1 "Could not execute ./test_pquery in ${PWD}"  # ./in.sql exec test
    else
      ./test >>"${MAINLOG}" 2>&1 || die 1 "Could not execute ./test in ${PWD}"  # ./in.sql exec test
    fi
    ./stop_replication >/dev/null 2>&1 # Output is removed, ref above
    sleep 1
    ./kill_replication >/dev/null 2>&1
  fi
  if [ ! -z "${UNIQUEID}" ]; then
    UNIQUEID_CHECK="$(${HOME}/t)"
    if [ "${UNIQUEID_CHECK}" == "${UNIQUEID}" ]; then
      echo "UniqueID Bug found: ${UNIQUEID_CHECK} -> bad commit (${CUR_COMMIT})" | tee -a "${MAINLOG}"
      bisect_bad
    else
      echo "UniqueID Bug not found: '$(echo "${UNIQUEID_CHECK}" | sed 's|Assert: n|N|;s|found.*, and|found, and|;s| for all logs.*||')' seen versus target '${UNIQUEID}' -> good commit (${CUR_COMMIT})" | tee -a "${MAINLOG}"
      bisect_good
    fi
    UNIQUEID_CHECK=
  elif [ ! -z "${TEXT}" ]; then
    if [ ! -z "$(grep -E "${TEXT}" log/master.err)" ]; then
      echo "TEXT Bug found; bad commit (${CUR_COMMIT})" | tee -a "${MAINLOG}"
      bisect_bad
    else
      echo "TEXT Bug not found; good commit (${CUR_COMMIT})" | tee -a "${MAINLOG}"
      bisect_good
    fi
  elif [ ! -z "${CLI_TEXT}" ]; then
    if [ ! -z "$(grep -E "${CLI_TEXT}" mysql.out)" ]; then
      echo "CLI_TEXT Bug found; bad commit (${CUR_COMMIT})" | tee -a "${MAINLOG}"
      bisect_bad
    else
      echo "CLI_TEXT Bug not found; good commit (${CUR_COMMIT})" | tee -a "${MAINLOG}"
      bisect_good
    fi
  else
    if [ $(ls -l data/*core* 2>/dev/null | wc -l) -ge 1 ]; then
      echo "Core file found in ./data; bad commit (${CUR_COMMIT})" | tee -a "${MAINLOG}"
      bisect_bad
    else
      echo "No core file found in ./data; good commit (${CUR_COMMIT})" | tee -a "${MAINLOG}"
      bisect_good
    fi
  fi
done

# For for example checking YACC compilation errors, you can use 'git bisect run':
# For automatic good/bad selection based on exit code, use 'git bisect run ./command_which_provides_exit_code':
# git bisect reset && git bisect start
# git bisect bad ...rev...
# git submodule update --init --recursive
# git bisect good ...rev...
# git submodule update --init --recursive
# git bisect run yacc -Wother -Wyacc -Wdeprecated --verbose sql/sql_yacc.yy 2>/dev/null  # 1 on error
# This will very quickly find the revision where the YACC error was introduced
