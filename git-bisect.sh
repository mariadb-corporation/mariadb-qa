#!/bin/bash
# Created by Roel Van de Paar, MariaDB

VERSION=10.11                                                       # 10.9, 10.10, 10.11, etc.
DBG_OR_OPT='dbg'                                                    # Use 'dbg' or 'opt' only
RECLONE=0                                                           # Set to 1 to reclone a tree before starting
LAST_KNOWN_GOOD_COMMIT='fe1f8f2c6b6f3b8e3383168225f9ae7853028947'   # Revision of last known good commit
FIRST_KNOWN_BAD_COMMIT='8f9df08f02294f4828d40ef0a298dc0e72b01f60'   # Revision of first known bad commit
TESTCASE='/test/in.sql'                                             # The testcase to be tested
UNIQUEID=''                                                         # The UniqueID to scan for [Exclusive]
TEXT=''                                                             # The string to scan for in the error log [Exclusive]
# Note: leave both UNIQUEID and TEXT empty to scan for core files instead

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
elif [ "${STY}" == "" ]; then
  echo "Not a screen, restarting myself inside a screen"
  screen -admS "git-bisect" bash -c "./$0"
  sleep 1
  screen -d -r "git-bisect"
  return 2> /dev/null; exit 0
fi

cd /test || die 1 '/test does not exist'
mkdir -p TMP_git-bisect || die 1 '/test/TMP_git-bisect could not be created'
echo 'Changing directory to /test/TMP_git-bisect'
cd TMP_git-bisect || die 1 'could not change directory to TMP_git-bisect'
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
  cd "/test/TMP_git-bisect/${VERSION}" || die 1 "Could not change directory to /test/TMP_git-bisect/${VERSION}"
  git bisect good
  if [ "${?}" -ne 0 ]; then
    echo "Finished"
    exit 0
  fi
}

bisect_bad(){
  cd "/test/TMP_git-bisect/${VERSION}" || die 1 "Could not change directory to /test/TMP_git-bisect/${VERSION}"
  git bisect bad
  if [ "${?}" -ne 0 ]; then
    echo "Finished"
    exit 0
  fi
}

git bisect reset  # Remove any previous bisect run data
git reset --hard  # Revert tree to mainline
git clean -xfd    # Cleanup tree
git checkout "${VERSION}"   # Ensure we've got the right version
git bisect start  # Start bisect run
git bisect bad  "${FIRST_KNOWN_BAD_COMMIT}"  # Starting point, bad
git bisect good "${LAST_KNOWN_GOOD_COMMIT}"  # Starting point, good
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
      git bisect skip
      continue
    else
      echo "|> ${CUR_COMMIT} is version ${CUR_VERSION}, proceeding..."
      break
    fi
  done
  while :; do
    echo "|> Cleaning up any previous version ${VERSION} builds in /test/TMP_git-bisect"
    rm -Rf /test/MD*${VERSION}*
    echo "|> Building revision in a screen session: use screen -d -r 'git-bisect-build' to see the build process"
    rm -f /tmp/git-bisect-build.exitcode
    screen -admS 'git-bisect-build' bash -c "${HOME}/mariadb-qa/build_mdpsms_${DBG_OR_OPT}.sh; echo \"\${?}\" > /tmp/git-bisect-build.exitcode"
    while [ "$(screen -ls | grep -o 'git-bisect-build')" == "git-bisect-build" ]; do
      sleep 2
    done
    sleep 2
    if [ "$(cat /tmp/git-bisect-build.exitcode | tr -d '\n')" -eq 1 ]; then
      echo "Build failure... Skipping revision ${CUR_COMMIT}"
      git bisect skip
      continue
    else
      echo "Build successful... Testing revision ${CUR_COMMIT}"
      break  # Successful build
    fi
    rm -f /tmp/git-bisect-build.exitcode
  done
  cd /test/TMP_git-bisect || die 1 'Could not change directory to /test/TMP_git-bisect'
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
  ./all_no_cl >/dev/null || die 1 "Could not execute ./all_no_cl in ${PWD}"  # wipe, start
  ./test_pquery >/dev/null || die 1 "Could not execute ./test_pquery in ${PWD}"  # ./in.sql exec test
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
