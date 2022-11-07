#!/bin/bash
# Created by Roel Van de Paar, MariaDB

# User variables
VERSION=10.11                                                       # 10.9, 10.10, 10.11, etc.
DBG_OR_OPT='dbg'                                                    # Use 'dbg' or 'opt' only
RECLONE=0                                                           # Set to 1 to reclone a tree before starting
UPDATETREE=1                                                        # Set to 1 to update the tree (git pull) before starting
BISECT_REPLAY=0                                                     # Set to 1 to do a replay rather than good/bad commit
BISECT_REPLAY_LOG='/test/git-bisect/git-bisect'                     # As manually saved with:  git bisect log > git-bisect
# WARNING: Take care to use commits from the same MariaDB server version (i.e. both from for example 10.10 etc.)
LAST_KNOWN_GOOD_COMMIT='b3df1ec97aacc27678c44eefe56ea8680456d608'   # Revision of last known good commit
FIRST_KNOWN_BAD_COMMIT='50c5743adc87e1cdec1431a02558f6540fe5a6d5'   # Revision of first known bad commit
TESTCASE='/test/in2.sql'                                            # The testcase to be tested
UNIQUEID=''                                                         # The UniqueID to scan for [Exclusive]
TEXT='my_time_packed_to_binary'                                     # The string to scan for in the error log [Exclusive]
# [Exclusove]: Note that UNIQUEID and TEXT are mutually exclusive: do not set both
# Leave both UNIQUEID and TEXT empty to scan for core files instead

# Script variables, do not change
RANDOM=$(date +%s%N | cut -b10-19)
TMPLOG1="/tmp/git-bisect-${RANDOM}${RANDOM}.out"
TMPLOG2="/tmp/git-bisect-build_${RANDOM}${RANDOM}.exitcode"

die(){
  echo "$2"; exit $1
}

if [ "${DBG_OR_OPT}" != 'dbg' -a "${DBG_OR_OPT}" != 'opt' ]; then
  echo "DBG_OR_OPT variable is incorrectly set: use 'dbg' or 'opt' only"
  exit 1
elif [[ "${VERSION}" != "10."* ]]; then
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
  exit 1
elif [ ! -r "${HOME}/start" ]; then
  echo "${HOME}/start missing. Try running ${HOME}/mariadb-qa/linkit"
  exit 1
elif [ "${BISECT_REPLAY}" -eq 1 -a ! -r "${BISECT_REPLAY_LOG}" ]; then
  echo "BISECT_REPLAY Enabled, yet BISECT_REPLAY_LOG (${BISECT_REPLAY_LOG}) cannot read by this script"
  exit 1
elif [ "${STY}" == "" ]; then
  echo "Not a screen, restarting myself inside a screen"
  screen -admS "git-bisect" bash -c "$0;bash"
  sleep 1
  screen -d -r "git-bisect"
  return 2> /dev/null; exit 0
fi

cd /test || die 1 '/test does not exist'
mkdir -p git-bisect || die 1 '/test/git-bisect could not be created'
echo 'Changing directory to /test/git-bisect'
cd git-bisect || die 1 'could not change directory to git-bisect'
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
  echo "Searching for UniqueID Bug: '${UNIQUEID}'"
elif [ ! -z "${TEXT}" ]; then
  echo "Searching for Error log text Bug: '${TEXT}'"
else
  echo "Searching for core files in the data directory to validate issue occurence"
fi

bisect_good(){
  cd "/test/git-bisect/${VERSION}" || die 1 "Could not change directory to /test/git-bisect/${VERSION}"
  rm -f ${TMPLOG1}
  git bisect good 2>&1 | grep -v 'warning: unable to rmdir' | tee ${TMPLOG1}
  if grep -qi 'first bad commit' ${TMPLOG1}; then
    rm -f ${TMPLOG1}
    echo "Finished. Use 'cd /test/git-bisect/${VERSION} && git bisect log' to see the full git bisect log"
    exit 0
  fi
  rm -f ${TMPLOG1}
}

bisect_bad(){
  cd "/test/git-bisect/${VERSION}" || die 1 "Could not change directory to /test/git-bisect/${VERSION}"
  rm -f ${TMPLOG1}
  git bisect bad 2>&1 | grep -v 'warning: unable to rmdir' | tee ${TMPLOG1}
  if grep -qi 'first bad commit' ${TMPLOG1}; then
    rm -f ${TMPLOG1}
    echo "Finished. Use 'cd /test/git-bisect/${VERSION} && git bisect log' to see the full git bisect log"
    exit 0
  fi
  rm -f ${TMPLOG1}
}

# Git setup
git bisect reset 2>&1 | grep -v 'We are not bisecting'  # Remove any previous bisect run data
git reset --hard  # Revert tree to mainline
git clean -xfd    # Cleanup tree
git checkout "${VERSION}"   # Ensure we have the right version
if [ "${UPDATETREE}" -eq 1 ]; then
  git pull        # Ensure we have the latest version
fi
git bisect start  # Start bisect run
if [ "${BISECT_REPLAY}" -eq 1 ]; then
  git bisect replay "${BISECT_REPLAY_LOG}" 
  if [ "${?}" -ne 0 ]; then 
    echo "git bisect replay \"${BISECT_REPLAY_LOG}\" failed. Terminating for manual debugging."
    exit 1
  else
    echo "git bisect replay \"${BISECT_REPLAY_LOG}\" succeeded. Proceding with regular git bisecting."
  fi
else
  git bisect bad  "${FIRST_KNOWN_BAD_COMMIT}"  # Starting point, bad
  if [ "${?}" -ne 0 ]; then 
    echo "Bad revision input failed. Terminating for manual debugging. Possible reasons: you may have used a revision of a feature branch, not trunk, have a typo in the revision, or the current tree being used is not recent enough (try 'git pull' or set RECLONE=1 inside the script)."
    exit 1
  fi
  git bisect good "${LAST_KNOWN_GOOD_COMMIT}"  # Starting point, good
  if [ "${?}" -ne 0 ]; then 
    echo "Good revision input failed. Terminating for manual debugging. Possible reasons: you may have used a revision of a feature branch, not trunk, have a typo in the revision, or the current tree being used is not recent enough (try 'git pull' or set RECLONE=1 inside the script)."
    exit 1
  fi
fi

# Note that the starting points may not point git to a valid commit to test. i.e. git bisect may jump to a commit
# which was done via a merge in the tree where the current branch is the second parent and not the first one, with
# the result that the tree version (as seen in the VERSION file) is different from the $VERSION needing to be tested.
# For this, the script (ref below) will use 'git bisect skip' until it has located a commit with the correct $VERSION
while :; do
  echo "|> Validating revision"
  CUR_VERSION=;CUR_COMMIT=
  while :; do
    source ./VERSION
    CUR_VERSION="${MYSQL_VERSION_MAJOR}.${MYSQL_VERSION_MINOR}"
    CUR_COMMIT="$(git log | head -n1 | tr -d '\n')"
    if [ "${CUR_VERSION}" != "${VERSION}" ]; then
      echo "|> ${CUR_COMMIT} is version ${CUR_VERSION}, skipping..."
      git bisect skip 2>&1 | grep -v 'warning: unable to rmdir'
      continue
    else
      echo "|> ${CUR_COMMIT} is version ${CUR_VERSION}, proceeding..."
      break
    fi
  done
  while :; do
    echo "|> Cleaning up any previous version ${VERSION} builds in /test/git-bisect"
    rm -Rf /test/git-bisect/MD*${VERSION}*
    echo "|> Building revision in a screen session: use screen -d -r 'git-bisect-build' to see the build process"
    rm -f ${TMPLOG2}
    screen -admS 'git-bisect-build' bash -c "${HOME}/mariadb-qa/build_mdpsms_${DBG_OR_OPT}.sh; echo \"\${?}\" > ${TMPLOG2}"
    while [ "$(screen -ls | grep -o 'git-bisect-build')" == "git-bisect-build" ]; do
      sleep 2
    done
    sleep 2
    if [ -z "$(cat ${TMPLOG2} 2>/dev/null | tr -d '\n')" ]; then
      echo "|> Build failure... Skipping revision ${CUR_COMMIT}"
      git bisect skip 2>&1 | grep -v 'warning: unable to rmdir'
      continue
    elif [ "$(cat ${TMPLOG2} 2>/dev/null | tr -d '\n')" -eq 1 ]; then
      echo "|> Build failure... Skipping revision ${CUR_COMMIT}"
      git bisect skip 2>&1 | grep -v 'warning: unable to rmdir'
      continue
    else
      echo "|> Build successful... Testing revision ${CUR_COMMIT}"
      break  # Successful build
    fi
    rm -f ${TMPLOG2}
  done
  cd /test/git-bisect || die 1 'Could not change directory to /test/git-bisect'
  TEST_DIR="$(ls -d MD$(date +'%d%m%y')*${VERSION}*${DBG_OR_OPT} 2>/dev/null)"
  if [ -z "${TEST_DIR}" ]; then
    echo "Assert: TEST_DIR is empty"
    exit 1
  elif [ ! -d "${TEST_DIR}" ]; then
    echo "Assert: TEST_DIR (${TEST_DIR}) does not exist"
    exit 1
  fi
  cd "${TEST_DIR}" || die 1 "Could not change directory to TEST_DIR (${TEST_DIR})"
  ${HOME}/start  # Init BASEDIR with runtime scripts
  cp ${TESTCASE} ./in.sql
  ./all_no_cl >/dev/null 2>&1 || die 1 "Could not execute ./all_no_cl in ${PWD}"  # wipe, start
  ./test_pquery >/dev/null 2>&1 || die 1 "Could not execute ./test_pquery in ${PWD}"  # ./in.sql exec test
  if [ ! -z "${UNIQUEID}" ]; then
    if [ "$(${HOME}/t)" == "${UNIQUEID}" ]; then
      echo 'UniqueID Bug found; bad commit'
      bisect_bad
    else
      echo 'UniqueID Bug not found; good commit'
      bisect_good
    fi
  elif [ ! -z "${TEXT}" ]; then
    if [ ! -z "$(grep "${TEXT}" log/master.err)" ]; then
      echo 'TEXT Bug found; bad commit'
      bisect_bad
    else
      echo 'TEXT Bug not found; good commit'
      bisect_good
    fi
  else
    if [ $(ls -l data/*core* 2>/dev/null | wc -l) -ge 1 ]; then
      echo 'Core file found in ./data; bad commit'
      bisect_bad
    else
      echo 'No core file found in ./data; good commit'
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
