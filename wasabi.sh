#!/bin/bash
# Created by Roel Van de Paar, MariaDB

# Wasabi: highly automated, high quality and seamless database testing. Created for MariaDB server, easy to adapt

# TODO List
# 0. Potentially it is a better choice to use pquery-run than reducer in fw mode for base runs
# 1. reducers have TEXT with no indent
#     set +H; ls --color=never *.string | sed 's|\.string||' | xargs -I{} echo "set +H; sed -i 's|TEXT=\"\"|TEXT=\"\\\$(cat \"{}.string\")\"|' {}.reducer.sh" | tr '\n' '\0' | xargs -0 -I{} bash -c "{}"; sed -i 's|^MODE=4|MODE=3|' *reducer.sh
# 2. reducers have MODE=4 set instead of MODE=3
# 3. reducers have USE_PQUERY=0 
#     sed -i 's|MULTI_THREADS=10|MULTI_THREADS=4|;s|USE_PQUERY=0|USE_PQUERY=1|' *reducer.sh
# 4. reducers have 10 threads set
# 5. reducers have FORCE_SKIPV=0
#     sed -i 's|^FORCE_SKIPV=0|FORCE_SKIPV=1|' *reducer.sh
# 6. reducers have USE_NEW_TEXT_STRING=0
#     sed -i 's|^USE_NEW_TEXT_STRING=0|USE_NEW_TEXT_STRING=1|' *reducer.sh
# 7. 1651298030055548371 files are written to the same directory, but it is by the newly created reducers (avoid?)
# 8. The main reducer does not show new subreducer finds
# 9. Large /dev/shm usage
# 10. Make XA optional
# 11. ~/ds is terminating fireworks instances (process tree root can be filtered)

# User configurable variables
WASABI_LOG='/data/wasabi/wasabi.log'  # Wasabi log, appended to once /data/wasabi/ (auto-created) exists
TERMINATE_ALL=1                       # Terminate all running processes on startup (destructive!)
VERSION_TO_TEST="10.9"                # The MariaDB version to test
USE_SQL_DIR="/data/fireworks"         # Use specified SQL input dir. If empty, ~/mariadb-qa/pquery/ is used
VERBOSE=1                             # Enable verbose output (on by default)
REGEX_SQL_FILTER='root|passw|drop.*mysql|shutdown|^use [^t]|^let|revoke|identified|release|dbug|kill|master_pos_wait'  # Problematic SQL filter

# ls *.sql | xargs -I{} echo "grep -viE 'root|passw|drop.*mysql|^use [^t]|^let|revoke|identified|release|dbug|kill|master_pos_wait' '{}' > '{}.new'" | tr '\n' '\0' | xargs -0 -I{} bash -c "{}" && ls *.new | xargs -I{} echo "mv {} {}" | sed 's|\.new$||' | xargs -I{} bash -c "{}"

# Internal variables and settings, do not change
USER="$(whoami)"                      # UserID capture for use in /home/${USER}/...
WIP_CLONE=0                           # Clone in progres 0/1
WIP_BLD_O=0                           # Build in progress 0/1 (optimized)
WIP_BLD_D=0                           # Build in progress 0/1 (debug)
set +H

echo 'Warning: this script will take over all server management, including the terminaton of active processes.'
echo 'Press enter twice to confirm, or CTRL+c to cancel startup.'
read -p '' && read -p ''

abort(){
  wecho 0 'Abort!' 'CTRL+c detected, terminating'
}
trap abort SIGINT

wecho(){
  local INLINE=''
  if [ "$1" -eq 0 -o "$1" -gt 0 -a "${VERBOSE}" -eq 1 ]; then
    if [ "$1" -gt 0 -a "${VERBOSE}" -eq 1 ]; then
      INLINE=' >'
    fi
    WECHO="$(date +'%F %T') [$2]${INLINE} $3"
    if [ ! -d /data/wasabi ]; then
      echo "${WECHO}" | tee -a ${WASABI_LOG}
    else
      echo "${WECHO}"
    fi
  fi
}

check_if_numeric(){
  if [ -z "${1}" ]; then
    wecho 0 'ASSERT' "The value passed to check_if_numeric() is empty, cannot continue"
    exit 1
  fi
  local NUMBERS_ONLY=''
  if [ "${2}" == 'allowdot' ]; then
    NUMBERS_ONLY="$(echo "${1}" | sed 's|[^0-9\.]||g')"
  else
    NUMBERS_ONLY="$(echo "${1}" | sed 's|[^0-9]||g')"
  fi
  if [ "${1}" != "${NUMBERS_ONLY}" ]; then
    wecho 0 'ASSERT' "Value '${1}' passed to check_if_numeric() is not numeric only, cannot continue"
    exit 1
  fi
}

check_if_numeric_nofail(){
  FAILED_CHECK=0
  if [ -z "${1}" ]; then
    FAILED_CHECK=1
  fi
  local NUMBERS_ONLY=''
  if [ "${2}" == 'allowdot' ]; then
    NUMBERS_ONLY="$(echo "${1}" | sed 's|[^0-9\.]||g')"
  else
    NUMBERS_ONLY="$(echo "${1}" | sed 's|[^0-9]||g')"
  fi
  if [ "${1}" != "${NUMBERS_ONLY}" ]; then
    FAILED_CHECK=1
  fi
}

secure_kill_proc(){
  if [ -z "${1}" ]; then
    wecho 0 'ASSERT' "The value passed to secure_kill_proc() is empty, cannot continue"
    exit 1
  fi
  if [ -z "$(ps -ef | grep "${1}" | grep ${USER} | grep -v grep)" ]; then
    if [ -z "$(ps -ef | grep "${1}" | grep -v grep)" ]; then
      wecho 0 'killpr' "** WARNING: process '${1}' passed to secure_kill_proc() did not exist"
    else
      wecho 0 'killpr' "*** ERROR: process '${1}' passed to secure_kill_proc() did not exist for user ${USER}, though did exist as a generic process, which is undefined behavior, cannot continue"
      exit 1
    fi
  fi
  for ((i=1; i<=10; i++)); do
    kill -9 ${CLONE_PID}
    sync
    sleep 1
    if [ -z "$(ps -ef | grep "${1}" | grep ${USER} | grep -v grep)" ]; then
      wecho 1 'killpr' "Process with PID ${1} terminated"
      break
    else
      wecho 1 'killpr' "** WARNING: secure_kill_proc(): process with PID ${1} still exists after ${i} kill attempt(s)"
    fi 
  done
  if [ ! -z "$(ps -ef | grep "${1}" | grep ${USER} | grep -v grep)" ]; then
    wecho 1 'killpr' "*** ERROR: secure_kill_proc(): process with PID ${1} still exists, cannot continue"
    exit 1
  fi
}

wasabi_startup_checks(){
  # Verify that mariadb-qa repo clone is present
  if [ ! -d "/home/${USER}/mariadb-qa" ]; then
    wecho '0' 'WStart' '*** ERROR: /home/${USER}/mariadb-qa not found, cannot continue'
    wecho '0' 'WStart' '*** Try:  cd ~ && git clone --depth=1 https://github.com/mariadb-corporation/mariadb-qa.git'
    exit 1
  fi
  # Verify we have a good clone
  if [ ! -r "/home/${USER}/mariadb-qa/reducer.sh" ]; then
    wecho '0' 'WStart' '*** ERROR: /home/${USER}/mariadb-qa/reducer.sh not found, cannot continue'
    wecho '0' 'WStart' '*** Try:  cd ~ && rm -Rf ./mariadb-qa && git clone --depth=1 https://github.com/mariadb-corporation/mariadb-qa.git'
    exit 1
  fi
  # Check that server is setup correctly
  if [ "$(grep -c 'unlimited' /etc/security/limits.conf)" -lt 20 ]; then
    wecho '0' 'WStart' "*** ERROR: /etc/security/limits.conf has less than 20x unlimited'; server not configured, cannot continue"
    wecho '0' 'WStart' "*** Try:  cd /home/${USER}/mariadb-qa && ./setup_server.sh"
    exit 1
  fi
  # Check that linkit was executed
  if [ ! -r "/home/${USER}/ka" ]; then
    wecho '0' 'WStart' "*** ERROR: /home/${USER}/ka not present, cannot continue"
    wecho '0' 'WStart' "*** Try:  cd /home/${USER}/mariadb-qa && ./linkit"
    exit 1
  fi
  # Check that /data and /test are present
  if [ ! -d "/data" -o ! -d "/test" ]; then
    wecho '0' 'WStart' '*** ERROR: /data or /test missing, cannot continue'
    wecho '0' 'WStart' "*** Try:  cd /home/${USER}/mariadb-qa && ./linkit"
    exit 1
  fi
  # Check that /test is in good shape
  if [ ! -r /test/clone.sh ]; then
    wecho '0' 'WStart' '*** ERROR: /test/clone.sh missing, cannot continue'
    wecho '0' 'WStart' "*** Try:  cd /home/${USER}/mariadb-qa && ./linkit"
    exit 1
  fi
  if [ -z "${VERSION_TO_TEST}" ]; then
    wecho '0' 'WStart' "*** ERROR: VERSION_TO_TEST is empty"
  fi
  check_if_numeric "${VERSION_TO_TEST}" 'allowdot'
  if [ "$(echo "${VERSION_TO_TEST}" | grep -oE '10.[1-9]|10.10')" != "${VERSION_TO_TEST}" ]; then
    wecho '0' 'WStart' "*** ERROR: VERSION_TO_TEST (${VERSION_TO_TEST}) is not in range 10.2-10.10, cannot continue"
    exit 1
  fi
  if [ -z "${USE_SQL_DIR}" ]; then
    wecho '0' 'WStart' "USE_SQL_DIR is unset, using ~/mariadb-qa/pquery/ for sql files"
    if [ ! -d /home/${USER}/mariadb-qa/pquery ]; then
      wecho '0' 'WStart' "*** ERROR: /home/${USER}/mariadb-qa/pquery missing, cannot continue"
      exit 1
    fi
    USE_SQL_DIR="/home/${USER}/mariadb-qa/pquery"
  fi
}

wasabi_startup(){
  if [ "${TERMINATE_ALL}" -eq 1 ]; then
    /home/${USER}/ka
  fi
}

wasabi_loop(){
  ##### Wasabi Init
  wecho 0 'W-Init' 'Checking essential data structures'
  if [ ! -d /data/wasabi ]; then
    echo 1 'W-Init' '/data/wasabi was not found, creating it'
    mkdir -p /data/wasabi
    if [ ! -d /data/wasabi ]; then
      wecho 0 'W-Init' '*** ERROR: /data/wasabi does not exist after creation attempt, cannot continue'
      exit 1
    fi
  fi
  if [ ! -d /data/wasabi/sql -o "$(ls /data/wasabi/sql/*.sql 2>/dev/null)" ]; then
    if [ ! -d /data/wasabi/sql ]; then
      echo 1 'W-Init' '/data/wasabi/sql not found, creating it'
      mkdir -p /data/wasabi/sql
      if [ ! -d /data/wasabi/sql ]; then
        wecho 0 'W-Init' '*** ERROR: /data/wasabi/sql does not exist after creation attempt, cannot continue'
        exit 1
      fi
    else
      echo 1 'W-Init' '/data/wasabi/sql found, but it did not contain any sql files, creating sql files'
      if [ ! -d "/home/${USER}/mariadb-qa/pquery/" ]; then
        wecho 0 'W-Init' "*** ERROR: /home/${USER}/mariadb-qa/pquery/ does not exist, cannot continue"
        exit 1
      fi

  ##### Resource Monitoring and Management
  wecho 0 'ResMon' 'Resource monitoring and management in progress'
  wecho 1 'ResMon' 'Checking if ~/ds is running'
  if [ -z "$(ps -ef | grep "/home/${USER}/ds" | grep -v grep)" ]; then
    if [ -r "/home/${USER}/ds" ]; then
      wecho 0 'ResMon' '~/ds was not running, starting it'
      screen -admS 'ds' "/home/${USER}/ds"
    else 
      wecho 0 'ResMon' "*** ERROR: /home/${USER}/ds not found, cannot continue"
      exit 1
    fi
  fi
  wecho 1 'ResMon' 'Checking if ~/memory is running'
  if [ -z "$(ps -ef | grep "/home/${USER}/memory" | grep -v grep)" ]; then
    if [ -r "/home/${USER}/memory" ]; then
      wecho 0 'ResMon' '~/memory was not running, starting it'
      screen -admS 'memory' "/home/${USER}/memory"
    else 
      wecho 0 'ResMon' "*** ERROR: /home/${USER}/memory not found, cannot continue"
      exit 1
    fi
  fi
  wecho 1 'ResMon' 'Checking available space on /data is >= 2Gb'
  if [ $(df -k -P 2>&1 | grep -E --binary-files=text -v "docker.devicemapper" | grep -E --binary-files=text "/data" | awk '{print $4}') -lt 2000000 ]; then
    wecho 0 'ResMon' "** WARNING: /data has < 2Gb available, pausing till issue is resolved (checks done every 15s)"
    while [ $(df -k -P 2>&1 | grep -E --binary-files=text -v "docker.devicemapper" | grep -E --binary-files=text "/data" | awk '{print $4}') -lt 2000000 ]; do
      sleep 15
    done
    wecho 0 'ResMon' 'Diskspace issue for /data resolved, continuing'
  fi
  wecho 1 'ResMon' 'Checking available space on /test is >= 3Gb'
  if [ $(df -k -P 2>&1 | grep -E --binary-files=text -v "docker.devicemapper" | grep -E --binary-files=text "/test" | awk '{print $4}') -lt 3000000 ]; then
    wecho 0 'ResMon' "** WARNING: /test has < 3Gb available, pausing till issue is resolved (checks done every 15s)"
    while [ $(df -k -P 2>&1 | grep -E --binary-files=text -v "docker.devicemapper" | grep -E --binary-files=text "/test" | awk '{print $4}') -lt 2000000 ]; do
      sleep 15
    done
    wecho 0 'ResMon' 'Diskspace issue for /test resolved, continuing'
  fi

  ##### Builds
  wecho 0 'Builds' 'Checking if it has been 25 hours since the last testable server build (if any)'
  local DOBUILD=0
  if [ -r /data/wasabi/lastbuild ]; then
    local LASTBUILD="$(cat /data/wasabi/lastbuild)"
    check_if_numeric_nofail "${LASTBUILD}"
    if [ "${FAILED_CHECK}" -eq 1 ]; then
      wecho 0 'Builds' '** WARNING: /data/wasabi/lastbuild existed but did not contain a valid epoch, deleting it'
      rm -f /data/wasabi/lastbuild
      if [ -r /data/wasabi/lastbuild ]; then
        wecho 0 'Builds' '*** ERROR: unable to delete /data/wasabi/lastbuild, cannot continue'
        exit 1
      fi
      wecho 0 'Builds' 'Writing new epoch to /data/wasabi/lastbuild to prevent problematic same-day builds'
      date +'%s' | tr -d '\n' > /data/wasabi/lastbuild
      # Check entry written
      LASTBUILD="$(cat /data/wasabi/lastbuild)"
      check_if_numeric_nofail "${LASTBUILD}"
      if [ "${FAILED_CHECK}" -eq 1 ]; then
        wecho 0 'Builds' '*** ERROR: /data/wasabi/lastbuild did not contain a valid epoch after creating it, cannot continue'
        exit 1
      fi
    else  # Valid lastbuild file/LASTBUILD var, check if new build is required (> 25h to prevent same-day builds)
      NOW="$(date +'%s' | tr -d '\n')"
      check_if_numeric "${NOW}"
      if [ $[ ${NOW} - ${LASTBUILD} ] -gt 90000 ]; then
        wecho 1 'Builds' 'New build required as previous build is more than 25h old'
        DOBUILD=1 
      else
        wecho 1 'Builds' "No new build required as previous build is less tahn 25h old ($[ ${NOW} - ${LASTBUILD} ]s)"
      fi
    fi
  else
    wecho 1 'Builds' 'New build required as no previous build was found (/data/wasabi/lastbuild not present)'
    DOBUILD=1
  fi
  if [ "${DOBUILD}" -eq 1 ]; then
    wecho 0 'Builds' "New MariaDB server version ${VERSION_TO_TEST} build: cloning in background thread"
    if [ -d "/test/${VERSION_TO_TEST}" ]; then
      rm -Rf "/test/${VERSION_TO_TEST}"
    fi
    screen -admS 'clone' "git clone --depth=1 --recurse-submodules -j10 --branch= https://github.com/MariaDB/server.git $1" &
    WIP_CLONE=1
    WIP_CLONE_START=$(date +'%s' | tr -d '\n')
  fi
  if [ "${WIP_CLONE}" -eq 1 ]; then  # Note that WIP_CLONE can only be 1 if DOBUILD=1
    wecho 0 'Builds' 'Existing clone in progress: checking for completion'
    if [ -z "$(screen -ls | grep 'clone')" ]; then
      wecho 1 'Builds' "Clone finished in $[ $(date +'%s' | tr -d '\n') - ${WIP_CLONE_START} ]s, checking clone quality"
      WIP_CLONE=0
      WIP_CLONE_START=
      sync  # Ensure clone is fully synced to disk
      if [ ! -d "/test/${VERSION_TO_TEST}" ]; then
        wecho 0 'Builds' "*** ERROR: /test/${VERSION_TO_TEST} does not exist after clone, will re-attempt clone"
        screen -admS 'clone' "git clone --depth=1 --recurse-submodules -j10 --branch= https://github.com/MariaDB/server.git $1" &
      elif [ ! -r "/test/${VERSION_TO_TEST}/VERSION" ]; then  # Clone directory present, check quality
        wecho 0 'Builds' "*** ERROR: /test/${VERSION_TO_TEST}/VERSION does not exist after clone, will re-attempt clone"
        rm -Rf "/test/${VERSION_TO_TEST}"
        screen -admS 'clone' "git clone --depth=1 --recurse-submodules -j10 --branch= https://github.com/MariaDB/server.git $1" &
      else  # Succesfull clone
        wecho 0 'Builds' 'Existing clone checks complete'
        wecho 0 'Builds' "Commencing build of MariaDB server version ${VERSION_TO_TEST} (opt) in a background thread"
        cd "/test/${VERSION_TO_TEST}"
        ~/mariadb-qa/build_mdpsms_opt.sh & WIP_BLD_O=1
        sleep 30 && sync  # Delay between builds to avoid directory conflicts before rename
        wecho 0 'Builds' "Commencing build of MariaDB server version ${VERSION_TO_TEST} (dbg) in a background thread" 
        ~/mariadb-qa/build_mdpsms_dbg.sh & WIP_BLD_D=1
        cd -
      fi
    else
      wecho 0 'Builds' "Existing clone still in progress after $[ $(date +'%s' | tr -d '\n') - ${WIP_CLONE_START} ] seconds"
      if [ $[ $(date +'%s' | tr -d '\n') - ${WIP_CLONE_START} ] -gt 900 ]; then
        wecho 0 'Builds' "*** ERROR: clone has taken more than 15 minutes, terminating thread, will re-attempt clone"
        local CLONE_PID=$(screen -ls | grep 'clone' | sed 's|\..*||' | grep -o '[0-9]\+')
        check_if_numeric "${CLONE_PID}"
        secure_kill_proc "${CLONE_PID}"
        CLONE_PID=
        rm -Rf "/test/${VERSION_TO_TEST}"
        sync
        screen -admS 'clone' "git clone --depth=1 --recurse-submodules -j10 --branch= https://github.com/MariaDB/server.git $1" &
      fi
    fi
  fi
  if [ "${WIP_BLD_O}" -eq 1 ]; then  # Note that WIP_BLD_O can only be one if WIP_CLONE was previously 1

  wecho 0 ''

  USE_SQL_DIR





}

main(){
  wasabi_startup_checks
  wasabi_startup
  wasabi_loop
} main

