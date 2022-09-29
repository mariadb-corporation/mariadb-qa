#!/bin/bash
# Created by Roel Van de Paar, MariaDB

VERSION=10.11                                                          # 10.9, 10.10, 10.11, etc.
DBG_OR_OPT='dbg'                                                       # Use 'dbg' or 'opt' only
RECLONE=0                                                              # Set to 1 to reclone a tree before starting
LAST_KNOWN_GOOD_COMMIT='fe1f8f2c6b6f3b8e3383168225f9ae7853028947'      # Revision of last known good commit
FIRST_KNOWN_BAD_COMMIT='8f9df08f02294f4828d40ef0a298dc0e72b01f60'      # Revision of first known bad commit
TESTCASE='/test/in.sql'                                                # The testcase to be tested
UNIQUEID=''                                                            # The UniqueID to scan for [Exclusive]
TEXT=''                                                                # The string to scan for in the error log [Exclusive]

die(){ 
  echo "$2"; exit $1 
}

if [ "${DBG_OR_OPT}" != 'dbg' -a "${DBG_OR_OPT}" != 'opt' ]; then
  echo "DBG_OR_OPT variable is incorrectly set: use 'dbg' or 'opt' only"
  exit 1
fi
if [[ "${VERSION}" != "10."* ]]; then
  echo "Version (${VERSION}) does not look correct"
  exit 1
fi
if [ ! -z "${UNIQUEID}" -a ! -z "${TEXT}" ]; then
  echo "Both UNIQUEID and TEXT were set. Please only specify one of them"
  exit 1
fi
if [ -z "${LAST_KNOWN_GOOD_COMMIT}" -o -z "${FIRST_KNOWN_BAD_COMMIT}" ]; then
  echo "LAST_KNOWN_GOOD_COMMIT or FIRST_KNOWN_BAD_COMMIT (or both) setting(s) missing"
  exit 1
fi
if [ ! -r "${HOME}/mariadb-qa/build_mdpsms_${DBG_OR_OPT}.sh" ]; then
  echo "${HOME}/mariadb-qa/build_mdpsms_${DBG_OR_OPT}.sh missing. Try cloning mariadb-qa again from Github into your home directory"
  exit 1
fi
if [ ! -r "${HOME}/start" ]; then
  echo "${HOME}/start missing. Try running ${HOME}/mariadb-qa/linkit"
  exit 1
fi

cd /test || die 1 '/test does not exist'
mkdir -p TMP_git-bisect || die 1 '/test/TMP_git-bisect could not be created'
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
else
  echo "Searching for Error log text Bug: '${TEXT}'"
fi
 
git reset --hard
git checkout "${VERSION}" 
git bisect start
git bisect bad  "${FIRST_KNOWN_BAD_COMMIT}"
git bisect good "${LAST_KNOWN_GOOD_COMMIT}"
git checkout "${VERSION}"  # Required to swap back to the right branch after the checkout enacted by the last two commands
while true; do
  echo "|> Building revision in a screen session named 'git-bisect': use screen -d -r 'git-bisect' to see the build process"
  screen -admS 'git-bisect' bash -c "${HOME}/mariadb-qa/build_mdpsms_${DBG_OR_OPT}.sh"
  if [ "${?}" -eq 1 ]; then
    echo "Build failure... try ~/mariadb-qa/build_mdpsms_${DBG_OR_OPT}.sh manually"
    # TODO: git bisect supports the 'git bisect skip' command when for example there is a build issue but the build issue is unrelated to the actual problem being searched for. If we have a lot of build that fail (currently 0 known) then the next like is likely better than just terminating the script
    # git bisect skip
    exit 1
  fi
  cd /test/TMP_git-bisect || die 1 'Could not change directory to /test/TMP_git-bisect'
  TEST_DIR="$(ls -ld MD$(date +'%d%m%y')*${VERSION}*${DBG_OR_OPT} 2>/dev/null)"
  if [ -z "${TEST_DIR}" ]; then
    echo "Assert: TEST_DIR is empty"
    exit 1
  elif [ ! -d "${TEST_DIR}" ]; then
    echo "Assert: TEST_DIR (${TEST_DIR}) does not exist"
    exit 1
  fi
  cd "${TEST_DIR}" || die 1 "Could not change directory to TEST_DIR (${TEST_DIR})"
  ${HOME}/start
  cp ${TESTCASE} ./in.sql
  ./all_no_cl >/dev/null || die 1 "Could not execute ./all_no_cl in ${PWD}"
  ./test_pquery >/dev/null || die 1 "Could not execute ./test_pquery in ${PWD}"
  if [ ! -z "${UNIQUEID}" ]; then
    if [ "$(${HOME}/t)" == "${UNIQUEID}" ]; then
      echo 'UniqueID Bug found, bad commit'
      git bisect bad
    else
      echo 'UniqueID Bug not found, good commit'
      git bisect good
    fi
  else
    if [ ! -z "$(grep "${TEXT}")" ]; then
      echo 'TEXT Bug found, bad commit'
      git bisect bad
    else
      echo 'TEXT Bug not found, good commit'
      git bisect good
    fi
  fi
done
