#!/bin/bash
# Created by Roel Van de Paar, MariaDB

set +H  # Disables history substitution and avoids  -bash: !: event not found  like errors
SCRIPT_PWD=$(dirname $(readlink -f "${0}"))
if [ "${1}" == "san" ]; then set "SAN" "${2}"; fi  # ${1} 'san' > 'SAN'
if [ "${1}" == "msan" ]; then set "MSAN" "${2}"; fi  # ${1} 'msan' > 'MSAN'

# User variables
ALSO_CHECK_REGULAR_TESTCASES_AGAINST_SAN_BUILDS=1
if [ "${1}" == "MSAN" ]; then ALSO_CHECK_REGULAR_TESTCASES_AGAINST_SAN_BUILDS=0; fi  # Preference ftm
DEBUG_OUTPUT=0  # Set to 1 to see full output of test_all and kill_all (note: this generates lots of output, and it is in parallel threads, so it likely only useful for debugging major issues with test_all and/or kill_all, but it is likely better to check a ./test_all run in a BASEDIR directly). Default: 0, legacy default: 1 (i.e. before this option was implemented, all output was shown)

if [ ! -r /test/gendirs.sh ]; then
  echo 'Assert: /test/gendirs.sh not found, try running ~/mariadb-qa/linkit'
  exit 1
fi

# Script variables: do not change
SAN_OPT_BUILD_FOR_REGULAR_TC_CHECK="/test/$(cd /test; ./gendirs.sh san | grep 'MD.*\-1[12].[0-9]' | grep 'opt' | sort -h | tail -n1)"
SAN_DBG_BUILD_FOR_REGULAR_TC_CHECK="/test/$(cd /test; ./gendirs.sh san | grep 'MD.*\-1[12].[0-9]' | grep 'dbg' | sort -h | tail -n1)"

if [ "${1}" != 'SAN' ]; then
  # If enabled (ALSO_CHECK_REGULAR_TESTCASES_AGAINST_SAN_BUILDS=1), then check what are deemed to be regular (i.e. non-*SAN) testcases against SAN builds also, as this often reveals new *SAN bugs additional to the original SIGSEGV/SIGABRT etc.
  if [ "${ALSO_CHECK_REGULAR_TESTCASES_AGAINST_SAN_BUILDS}" == '1' ]; then
    if [ ! -d "${SAN_OPT_BUILD_FOR_REGULAR_TC_CHECK}" ]; then
      echo "Assert: ALSO_CHECK_REGULAR_TESTCASES_AGAINST_SAN_BUILDS is enabled in the script (1), yet the directory SAN_OPT_BUILD_FOR_REGULAR_TC_CHECK (${SAN_OPT_BUILD_FOR_REGULAR_TC_CHECK}) does not exist"
      exit 1
    elif [ ! -d "${SAN_DBG_BUILD_FOR_REGULAR_TC_CHECK}" ]; then
      echo "Assert: ALSO_CHECK_REGULAR_TESTCASES_AGAINST_SAN_BUILDS is enabled in the script (1), yet the directory SAN_DBG_BUILD_FOR_REGULAR_TC_CHECK (${SAN_DBG_BUILD_FOR_REGULAR_TC_CHECK}) does not exist"
      exit 1
    fi
  #else  # We do not need to display this, it is unecessary info
    #echo "ALSO_CHECK_REGULAR_TESTCASES_AGAINST_SAN_BUILDS is enabled (1), however this is a SAN run already, so ignoring this setting (safe)"
  fi
fi

# Terminate any other bug_report.sh scripts ongoing
# Does not work correctly TODO
#ps -ef | grep -v $$ | grep bug_report | grep -v grep | grep -v mass_bug_report | awk '{print $2}' | xargs kill -9 2>/dev/null

MYEXTRA_OPT="$*"
NOCORE=0
SAN_MODE=0
MSAN_MODE=0
GAL_MODE=0
REPL_MODE=0
if [ -z "${PASS_MYEXTRA_TO_START_ONLY}" ]; then  # Check if an external script (like ~/b) has set this option. If not, set it here. If you want to use this option in combination with ~/b, set it there, or use export PASS_MYEXTRA_TO_START_ONLY=0 (or 1) before starting ~/b, or use ~/b0 or ~/b1 which are shortcuts
  PASS_MYEXTRA_TO_START_ONLY=1  # If 0, then MYEXTRA_OPT is passed to ./all (i.e. options take effect on init and start). If 1, then MYEXTRA_OPT is passed to ./start only (i.e. options take effect on start only, not init). When using for example --innodb_page_size=4 (an option needed for both server init + start), 0 is required. When using for example --innodb-force-recovery=1 or --innodb-read-only=1 (options that can only be used with start and not with init), 1 is required. TODO: this option can be automated 0/1 towards known options that require either 0 or 1 for this setting. Scan MYEXSTRA_OPT to do so
fi
export PASS_MYEXTRA_TO_START_ONLY=${PASS_MYEXTRA_TO_START_ONLY}
SHORTER_STOP_TIME=23   # TODO: this can be improved. Likely setting this smaller than 20 seconds is not a good idea, some cores/crashes may be missed (presumably on slow servers)

if [ "${1}" == "GAL" ]; then
  if [ -z "${TEXT}" ]; then   # Passed normally by ~/br preloader/wrapper sript
    echo "Assert: TEXT is empty, but BBB was expected. TODO: add 'export TEXT=...' support for Galera Cluster"
    exit 1
  elif [ "${TEXT}" != "BBB" ]; then
    echo "Assert: TEXT is set to '${TEXT}', but BBB was expected. TODO: add 'export TEXT=...' support for Galera Cluster"
    exit 1
  else  # BBB
    echo "NOTE: Looking for crashes/asserts in the galera node error logs as well as core files to validate issue occurrence."
  fi
  GAL_MODE=1
  MYEXTRA_OPT="$(echo "${MYEXTRA_OPT}" | sed 's|GAL||')"
elif [ "${1}" == "SAN" ]; then
  if [ -z "${TEXT}" ]; then   # Passed normally by ~/b preloader/wrapper sript
    echo "Assert: TEXT is empty, use export TEXT= to set it!"
    exit 1
  else
    echo "NOTE: SAN Mode: Looking for '${TEXT}' in the error log to validate issue occurrence."
    if [ "${ALSO_CHECK_SAN_BUILDS_FOR_CORES}" == '1' ]; then
      echo "NOTE: ALSO_CHECK_SAN_BUILDS_FOR_CORES[_SET]=1: Will also look for core files in *SAN dirs to validate issue occurence. It is recommended to leave this enabled."  # ... (as set in ~/bs), given that short testcases leading to a SIGSEGV/SIGABRT on *SAN builds are likely directly/immediately related to any *SAN issues they may produce otherwise
    fi
  fi
  SAN_MODE=1
  MYEXTRA_OPT="$(echo "${MYEXTRA_OPT}" | sed 's|SAN||')"
elif [ "${1}" == "MSAN" ]; then
  if [ -z "${TEXT}" ]; then   # Passed normally by ~/b preloader/wrapper sript
    echo "Assert: TEXT is empty, use export TEXT= to set it!"
    exit 1
  else
    echo "NOTE: MSAN Mode: Looking for '${TEXT}' in the error log to validate issue occurrence."
    if [ "${ALSO_CHECK_SAN_BUILDS_FOR_CORES}" == '1' ]; then
      echo "NOTE: ALSO_CHECK_SAN_BUILDS_FOR_CORES[_SET]=1: Will also look for core files in MSAN dirs to validate issue occurence. It is recommended to leave this enabled."  # ... (as set in ~/bm), given that short testcases leading to a SIGSEGV/SIGABRT on MSAN builds are likely directly/immediately related to any MSAN issues they may produce otherwise
    fi
  fi
  MSAN_MODE=1
  MYEXTRA_OPT="$(echo "${MYEXTRA_OPT}" | sed 's|MSAN||')"
elif [ "${1}" == "REPL" ]; then
  if [ -z "${TEXT}" ]; then   # Passed normally by ~/br preloader/wrapper sript
    echo "Assert: TEXT is empty, but BBB was expected. TODO: add 'export TEXT=...' support for replication"
    exit 1
  elif [ "${TEXT}" != "BBB" ]; then
    echo "Assert: TEXT is set to '${TEXT}', but BBB was expected. TODO: add 'export TEXT=...' support for replication"
    exit 1
  else  # BBB
    echo "NOTE: Looking for crashes/asserts in the master+slave error logs as well as core files to validate issue occurrence."
  fi
  REPL_MODE=1
  MYEXTRA_OPT="$(echo "${MYEXTRA_OPT}" | sed 's|REPL||')"
else
  if [ -z "${TEXT}" ]; then
    echo "NOTE: TEXT is empty; looking for corefiles, and not specific strings in the error log!"
    echo "If you want to scan for specific strings in the error log, then use:"
    echo "  export TEXT='your_search_text'  # to set it before running this script"
  else
    if [ "${TEXT}" == "BBB" ]; then
      echo "NOTE: Looking for crashes/asserts in the error log as well as core files to validate issue occurrence."
    else
      echo "NOTE: Looking for '${TEXT}' in the error log to validate issue occurrence."
    fi
  fi
fi
sleep 1
RUN_PWD=${PWD}

if [ ! -r bin/mysqld ]; then
  echo "Assert: bin/mysqld not available, please run this from a basedir which had the SQL executed against it an crashed"
  exit 1
fi

if [ "${GAL_MODE}" -eq 1 ]; then
  MYEXTRA_OPT="$(echo "${MYEXTRA_OPT}" | sed 's|GAL||')"
  if [ ! -r ./gal_no_cl ]; then  # Local
      echo "Assert: ./gal_no_cl not available, please run this from a basedir which was prepared with ${SCRIPT_PWD}/startup.sh"
      exit 1
  fi
else
  if [ "${REPL_MODE}" -eq 1 ]; then
    if [ ! -r ./start_replication ]; then  # Local
      echo "Assert: ./start_replication not available, please run this from a basedir which was prepared with ${SCRIPT_PWD}/startup.sh"
      exit 1
    fi
  else
    if [ ! -r ./all_no_cl ]; then  # Local
      echo "Assert: ./all_no_cl not available, please run this from a basedir which was prepared with ${SCRIPT_PWD}/startup.sh"
      exit 1
    fi
  fi
fi

if [ ! -r ../test_all ]; then  # Global
  echo "Assert: ../test_all not available - incorrect setup or structure"
  exit 1
fi

if [ ! -r ../kill_all ]; then  # Global
  echo "Assert: ../kill_all not available - incorrect setup or structure"
  exit 1
fi

if [ ! -r ../gendirs.sh ]; then  # Global
  echo "Assert: ../gendirs.sh not available - incorrect setup or structure"
  exit 1
fi

if [ ! -r ./in.sql ]; then  # Local
  echo "Assert: ./in.sql not available - incorrect setup or structure"
  exit 1
fi

echo 'Starting bug report generation for this SQL code (please check):'
echo '----------------------------------------------------------------'
cat in.sql | grep -v --binary-files=text '^$'
echo '----------------------------------------------------------------'

RANDOM=$(date +%s%N | cut -b10-19 | sed 's|^[0]\+||')  # Random entropy init
RANDF=$(echo $RANDOM$RANDOM$RANDOM$RANDOM | sed 's|.\(..........\).*|\1|')  # Random 10 digits filenr

if [ ! -r bin/mysqld ]; then
  echo "Assert: bin/mysqld not found!"
  exit 1
fi

grep --binary-files=text 'mysqld options required for replay:' ./in.sql | sed 's|.*mysqld options required for replay:[ ]||' > /tmp/options_bug_report.${RANDF}
echo ${MYEXTRA_OPT} >> /tmp/options_bug_report.${RANDF}
MYEXTRA_OPT_CLEANED=$(cat /tmp/options_bug_report.${RANDF} | sed 's|  | |g' | tr ' ' '\n' | sort -u | tr '\n' ' ')
if [ "$(echo "${MYEXTRA_OPT_CLEANED}" | sed 's|[ \t]||g')" != "" ]; then
  echo "Using the following options: ${MYEXTRA_OPT_CLEANED}"
else
  echo 'Note that any required mysqld options need to be listed, as exemplified on the next line, as the first line of the testcase:'
  echo '# mysqld options required for replay:  --someoption[=somevalue]'
fi
sleep 2.5  # For visual confirmation

test_san_build(){
  local TSB_PWD="${PWD}"
  cd "${1}" 
  cp ../in.sql .
  if [ ! -r ./start ]; then
    ~/start >/dev/null 2>&1
  fi
  if [ "${REPL_MODE}" -eq 1 ]; then
    ./start_replication ${MYEXTRA_OPT_CLEANED} >/dev/null 2>&1
  else
    ./all_no_cl ${MYEXTRA_OPT_CLEANED} >/dev/null 2>&1
  fi
  ./test_pquery >/dev/null 2>&1
  ./stop >/dev/null 2>&1
  sleep 1
  BUG_STRING="$(~/t)"
  VERSION="$(echo "${1}" | grep -o '10\.1[0-9]')"
  echo "${BUG_STRING}" | \
   if grep -Fq "no core file found" ; then echo "${VERSION} ${2}: No SAN issue detected"; \
   elif echo ${BUG_STRING} | cut -d '|' -f1 | grep -Fq "SAN"; then echo "${VERSION} ${2}: ${BUG_STRING}"; \
   else echo "${VERSION} ${2}: No SAN issue detected, though saw ${BUG_STRING}"; \
   fi
  cd "${TSB_PWD}"
}

rm -f ../in.sql
if [ -r ../in.sql ]; then echo "Assert: ../in.sql still available after it was removed!"; exit 1; fi
cp in.sql ..
if [ ! -r ../in.sql ]; then echo "Assert: ../in.sql not available after copy attempt!"; exit 1; fi
cd ..
echo "Testing all..."
REDIRECT=">/dev/null 2>&1"
if [ "${DEBUG_OUTPUT}" -eq 1 ]; then
  REDIRECT=
fi
if [ "${SAN_MODE}" -eq 1 ]; then
  ./test_all SAN ${MYEXTRA_OPT_CLEANED} ${REDIRECT}
elif [ "${MSAN_MODE}" -eq 1 ]; then
  ./test_all MSAN ${MYEXTRA_OPT_CLEANED} ${REDIRECT}
elif [ "${GAL_MODE}" -eq 1 ]; then
  ./test_all GAL ${MYEXTRA_OPT_CLEANED} ${REDIRECT}
elif [ "${REPL_MODE}" -eq 1 ]; then
  ./test_all REPL ${MYEXTRA_OPT_CLEANED} ${REDIRECT}
else
  ./test_all ${MYEXTRA_OPT_CLEANED} ${REDIRECT}
fi
echo "Ensuring all servers are gone..."
sync
if [ "${SAN_MODE}" -eq 1 ]; then
  ./kill_all SAN ${REDIRECT}
elif [ "${MSAN_MODE}" -eq 1 ]; then
  ./kill_all MSAN ${REDIRECT}
elif [ "${GAL_MODE}" -eq 1 ]; then
  ./kill_all GAL ${REDIRECT}
elif [ "${REPL_MODE}" -eq 1 ]; then
  ./kill_all REPL ${REDIRECT}
else
  ./kill_all ${REDIRECT}  # NOTE: Can not be executed as ../kill_all as it requires ./gendirs.sh
fi

if [ -z "${TEXT}" -o "${TEXT}" == "BBB" ]; then
  echo "TEXT not set, scanning for corefiles..."
  if [ "${1}" == "SAN" ]; then
    echo "Assert: SAN mode is enabled, but TEXT variable is not set!"
    exit 1
  elif [ "${1}" == "GAL" ]; then
    CORE_OR_TEXT_COUNT_ALL=$(./gendirs.sh GAL | xargs -I{} echo "ls {}/node1/*core* 2>/dev/null" | xargs -I{} bash -c "{}" | wc -l)
  else
    CORE_OR_TEXT_COUNT_ALL=$(./gendirs.sh | xargs -I{} echo "ls {}/data*/*core* 2>/dev/null" | xargs -I{} bash -c "{}" | wc -l)
  fi
else
  if [ "${1}" == "SAN" ]; then
    #echo "Searching error logs for the '^SUMMARY:|=ERROR:|runtime error:|AddressSanitizer:|ThreadSanitizer:|LeakSanitizer:|MemorySanitizer:' (SAN mode enabled)"  # This is now set in ~/b (when using ~/bs) - ref/use linkit if ~/b or ~/bs are not present
    echo "TEXT set to '${TEXT}', searching error logs for the same (case insensitive, regex aware) (SAN mode enabled)"
    CORE_OR_TEXT_COUNT_ALL=$(set +H; ./gendirs.sh SAN | xargs -I{} echo "grep -m1 -iE --binary-files=text '${TEXT}' {}/log/master.err 2>/dev/null" | tr '\n' '\0' | xargs -0 -I{} bash -c "{}" | wc -l)
  elif [ "${1}" == "MSAN" ]; then
    #echo "Searching error logs for the '^SUMMARY:|=ERROR:|MemorySanitizer:' (MSAN mode enabled)"  # This is now set in ~/b (when using ~/bm) - ref/use linkit if ~/b or ~/bm are not present
    echo "TEXT set to '${TEXT}', searching error logs for the same (case insensitive, regex aware) (SAN mode enabled)"
    CORE_OR_TEXT_COUNT_ALL=$(set +H; ./gendirs.sh MSAN | xargs -I{} echo "grep -m1 -iE --binary-files=text '${TEXT}' {}/log/master.err 2>/dev/null" | tr '\n' '\0' | xargs -0 -I{} bash -c "{}" | wc -l)
  elif [ "${1}" == "GAL" ]; then
    echo "TEXT set to '${TEXT}', searching error logs for the same (case insensitive, regex aware)"
    CORE_OR_TEXT_COUNT_ALL=$(set +H; ./gendirs.sh GAL | xargs -I{} echo "grep -m1 -iE --binary-files=text '${TEXT}' {}/node1/node1.err 2>/dev/null" | tr '\n' '\0' | xargs -0 -I{} bash -c "{}" | wc -l)
  else
    echo "TEXT set to '${TEXT}', searching error logs for the same (case insensitive, regex aware)"
    CORE_OR_TEXT_COUNT_ALL=$(set +H; ./gendirs.sh | xargs -I{} echo "grep -m1 -iE --binary-files=text '${TEXT}' {}/log/master.err 2>/dev/null" | tr '\n' '\0' | xargs -0 -I{} bash -c "{}" | wc -l)
  fi
fi
cd - >/dev/null || exit 1

# Call the version check helper script to set the following vars:
# BIN, SOURCE_CODE_REV, SVR, SERVER_VERSION, BUILD_TYPE, MDG
# Note: this helper script find/call code is universal; it will works for/from all scripts
if [ -r "${SCRIPT_PWD}/../version_chk_helper.source" ]; then
  source "${SCRIPT_PWD}/../version_chk_helper.source"
elif [ -r "${SCRIPT_PWD}/version_chk_helper.source" ]; then
  source "${SCRIPT_PWD}/version_chk_helper.source"
else 
  echo "Assert: version_chk_helper.source not found/readable by this script ($0)"
  exit 1
fi

# Check the current directory for outcome
if [ "${1}" == "GAL" ]; then
  CORE_COUNT=$(ls node1/*core* 2>/dev/null | wc -l)
  CORE_FILE=$(ls node1/*core* 2>/dev/null | head -1)
else
  CORE_COUNT=$(ls data*/*core* 2>/dev/null | wc -l)
  CORE_FILE=$(ls data*/*core* 2>/dev/null | head -1)
fi
if [ ${CORE_COUNT} -eq 0 ]; then
  echo "INFO: no cores found at data*/*core*"
elif [ ${CORE_COUNT} -gt 1 -a "${REPL_MODE}" -eq 0 ]; then
  echo "Assert: too many (${CORE_COUNT}) cores found at data*/*core*, this should not happen (as ./all_no_cl was used which should have created a clean data directory). A maximum of 1 core should be present."
  exit 1
elif [ ${CORE_COUNT} -gt 2 -a "${REPL_MODE}" -eq 1 ]; then
  echo "Assert: too many (${CORE_COUNT}) cores found at data*/*core*, this should not happen (as ./start_replication was used which should have created a clean data directory). A maximum of 2 cores (master+slave) should be present."
  exit 1
else
  # set print array on
  # set print array-indexes on
  # set print elements 0
  gdb -q bin/mysqld $(ls $CORE_FILE) >/tmp/${RANDF}.gdba 2>&1 << EOF
   set pagination off
   set print pretty on
   set print frame-arguments all
   bt
   quit
EOF
fi

echo '-------------------- BUG REPORT --------------------'
echo '{code:sql}'
cat in.sql | grep -v --binary-files=text '^$'
echo -e '{code}\n'
echo -e 'Leads to:\n'
# Assumes (which is valid for the pquery framework) that 1st assertion is also the last in the log
if [ ${SAN_MODE} -eq 0 -a ${MSAN_MODE} -eq 0 ]; then
  if [ "${1}" == "GAL" ]; then
    ERROR_LOG=$(ls node1/node1.err 2>/dev/null | head -n1)
  else
    ERROR_LOG=$(ls log/master.err 2>/dev/null | head -n1)
  fi
  if [ -n "${ERROR_LOG}" ]; then
    ASSERT="$(grep --binary-files=text -m1 'Assertion.*failed.$' ${ERROR_LOG} | head -n1)"
    if [ -z "${ASSERT}" ]; then
      ASSERT="$(grep --binary-files=text -m1 'Failing assertion:' ${ERROR_LOG} | head -n1)"
    fi
    if [ -n "${ASSERT}" ]; then
      echo -e "{noformat:title=${SVR} ${SERVER_VERSION} ${SOURCE_CODE_REV}${BUILD_TYPE} ${BUILD_DATE}}\n${ASSERT}\n{noformat}\n"
    fi
  fi

  # Update March/April 24: a system update now renders stacks as
  #10 0x0000562e73a837b4 in mysql_admin_table (thd=thd@entry=0x152110000d58,
  #    tables=tables@entry=0x152110016ac0,
  #    ...
  #    at /test/preview-11.5-preview_dbg/sql/sql_admin.cc:1116
  # The awk below fixes this by moving everything back into single lines
  # Also changed in stack.sh

  echo "{noformat:title=${SVR} ${SERVER_VERSION} ${SOURCE_CODE_REV}${BUILD_TYPE} ${BUILD_DATE}}"
  if [ -r /tmp/${RANDF}.gdba ]; then
    #The next line was temporarily used when there was an issue with stacks not having correct newlines
    #grep --binary-files=text -A999 'Core was generated by' /tmp/${RANDF}.gdba | grep --binary-files=text -v 'No such file or directory' | grep --binary-files=text -v '^(gdb)[ \t]*$' | sed 's|(gdb) (gdb) |(gdb) bt\n|' | sed 's|(gdb) (gdb) ||' | awk '{ if(/^    /) printf("%s", substr($0, 5)); else if(NR > 1) printf("\n%s", $0); else printf("%s", $0); } END { printf("\n"); }'
    # The next line is duplicated in stack.sh, update both if changing one 
    grep --binary-files=text -A999 'Core was generated by' /tmp/${RANDF}.gdba | grep --binary-files=text -v 'No such file or directory' | sed 's|(gdb) (gdb) |(gdb) bt\n|' | sed 's|(gdb) (gdb) ||' | awk '{ if(/^    /) printf("%s", substr($0, 5)); else if(NR > 1) printf("\n%s", $0); else printf("%s", $0); } END { printf("\n"); }' | grep --binary-files=text -v '^(gdb)[ \t]*$' | grep --binary-files=text -vi 'Downloading source file'
    rm -f /tmp/${RANDF}.gdba
  else
    NOCORE=1
    if [ "${1}" == "GAL" ]; then
      echo "THIS TESTCASE DID NOT CRASH ${SERVER_VERSION} (the version of the basedir in which you started this script), SO NO BACKTRACE IS SHOWN HERE. YOU CAN RE-EXECUTE THIS SCRIPT FROM ONE OF THE 'Bug confirmed present in' DIRECTORIES BELOW TO OBTAIN ONE, OR EXECUTE ./gal_no_cl; ./gal_test; ./stack FROM WITHIN THAT DIRECTORY TO GET A BACKTRACE ETC. MANUALLY!"
    else
      echo "THIS TESTCASE DID NOT CRASH ${SERVER_VERSION} (the version of the basedir in which you started this script), SO NO BACKTRACE IS SHOWN HERE. YOU CAN RE-EXECUTE THIS SCRIPT FROM ONE OF THE 'Bug confirmed present in' DIRECTORIES BELOW TO OBTAIN ONE, OR EXECUTE ./all_no_cl; ./test; ./stack FROM WITHIN THAT DIRECTORY TO GET A BACKTRACE ETC. MANUALLY!"
    fi
  fi
  echo '{noformat}'
else   # UBASAN/UBSAN/ASAN/TSAN/MSAN
  # START_LINE: the 1st line on which any *SAN issue shows (ref TEXT in ~/b), END_LINE: the last of either '^SUMMARY:' or '=ABORTING$'
  START_LINE=$(grep -n -m 1 -E "${TEXT}" ./log/master.err | cut -d: -f1)
  END_LINE=$(grep -n -E "^SUMMARY:|=ABORTING$" ./log/master.err | tail -1 | cut -d: -f1)
  if [ ! -z "${START_LINE}" ]; then
    if [ -z "${END_LINE}" ]; then END_LINE=10000; fi
    ${SCRIPT_PWD}/homedir_scripts/myver | head -n1
    sed -n "${START_LINE},${END_LINE}p" ./log/master.err
    echo '{noformat}'
  else
    echo "N/A"
  fi
  START_LINE=;END_LINE=
  # Check if a SAN stack is present in the alternative (dbg vs opt) and add it to output as well
  ALT_BASEDIR=
  if [[ "${PWD}" == *"opt" ]]; then
    ALT_BASEDIR="$(pwd | sed 's|opt$|dbg|')"
  elif [[ "${PWD}" == *"dbg" ]]; then
    ALT_BASEDIR="$(pwd | sed 's|dbg$|opt|')"
  fi
  if [ ! -z "${ALT_BASEDIR}" -a -d "${ALT_BASEDIR}" -a "${ALT_BASEDIR}" != "${PWD}" ]; then
    ALT_START_LINE=$(grep -n -m 1 -E "${TEXT}" ${ALT_BASEDIR}/log/master.err | cut -d: -f1)
    ALT_END_LINE=$(grep -n -E "^SUMMARY:|=ABORTING$" ${ALT_BASEDIR}/log/master.err | tail -1 | cut -d: -f1)
    if [ ! -z "${START_LINE}" ]; then
      if [ -z "${END_LINE}" ]; then END_LINE=10000; fi
      cd ${ALT_BASEDIR}
      ${SCRIPT_PWD}/homedir_scripts/myver | head -n1
      cd - >/dev/null
      sed -n "${ALT_START_LINE},${ALT_END_LINE}p" ${ALT_BASEDIR}/log/master.err
      echo '{noformat}'
    fi
    ALT_START_LINE=;ALT_END_LINE=
  fi
  ALT_BASEDIR=
  echo -e '\nSetup:\n'
  echo '{noformat}'
  if grep -q 'clang' "/test/$(cd /test/; ./gendirs.sh san | head -n1)/BUILD_CMD_CMAKE"; then  # Check if Clang was used for building the *SAN builds
    # TODO: consider use of dpkg --list | grep -o 'llvm-[0-9]\+' | sort -h -r | head -n1 | grep -o '[0-9]\+'
    echo "Compiled with a recent version of Clang and LLVM. Ubuntu instructions for Clang/LLVM 18:"
    echo "  # Note: It is strongly recommended to uninstall all old Clang & LLVM packages (ref  dpkg --list | grep -iE 'clang|llvm'  and use  apt purge  and  dpkg --purge  to remove the packages), before installing Clang/LLVM 18"
    # There now is a /usr/lib/llvm-18/lib/LLVMgold.so installed; llvm-17-linker-tools is no longer required
    #echo '     # Note: llvm-17-linker-tools installs /usr/lib/llvm-17/lib/LLVMgold.so, which is needed for compilation, and LLVMgold.so is no longer included in LLVM 18'
    #echo '     sudo apt install clang llvm-18 llvm-18-linker-tools llvm-18-runtime llvm-18-tools llvm-18-dev libstdc++-14-dev llvm-dev llvm-17-linker-tools'
    echo '     sudo apt install clang llvm-18 llvm-18-linker-tools llvm-18-runtime llvm-18-tools llvm-18-dev libstdc++-14-dev llvm-dev lld-18'
    #echo '     sudo ln -s /usr/lib/llvm-17/lib/LLVMgold.so /usr/lib/llvm-18/lib/LLVMgold.so'
    O_LEVEL_STMT=
    if [ -r ./BUILD_CMD_CMAKE ]; then
      O_LEVEL_STMT="$(grep -o '\-O[0-9g] ' ./BUILD_CMD_CMAKE)"
    fi
    if [ -z "${O_LEVEL_STMT}" ]; then
      O_LEVEL_STMT='-O1 ' # Commonly used for dbg builds
      if [[ "${PWD}" == *"opt" ]]; then O_LEVEL_STMT='-O2 '; fi  # For opt builds
    fi
    echo "Compiled with: \"-DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_CXX_COMPILER=/usr/bin/clang++ -DCMAKE_C{,XX}_FLAGS='${O_LEVEL_SMT}-march=native -mtune=native'\" and:"
  else
    echo "Compiled with a recent version of GCC (I used GCC $(gcc --version | head -n1 | sed 's|.* ||')) and:"
  fi
  if grep -Eiqm1 --binary-files=text 'ThreadSanitizer:' ../*SAN*/log/master.err; then  # TSAN
    # A note on exitcode=0: whereas we do not use this in our runs, it is required to let MTR bootstrap succeed.
    # TODO: Once code becomes more stable add: halt_on_error=1
    echo '    -DWITH_TSAN=ON -DWSREP_LIB_WITH_TSAN=ON -DMUTEXTYPE=sys'
    echo 'Set before execution:'
    echo '    export TSAN_OPTIONS=suppress_equal_stacks=1:suppress_equal_addresses=1:history_size=7:verbosity=1:exitcode=0'
  fi
  if grep -Eiqm1 --binary-files=text 'runtime error:|=ERROR:|LeakSanitizer:|AddressSanitizer:' ../*SAN*/log/master.err; then  # UBSAN/ASAN/LSAN(ASAN) (best not to split ASAN vs UBSAN build here, and to just leave both enabled, as these features, when both are enabled, may affect the server differently then only one is enabled: we thus maximize bug reproducibility through leaving the same options enabled as where there during testing)  # elif; avoids double printing
    echo '    -DWITH_ASAN=ON -DWITH_ASAN_SCOPE=ON -DWITH_UBSAN=ON -DWSREP_LIB_WITH_ASAN=ON'
    UBFLAG=0
    if grep -Eiqm1 --binary-files=text 'runtime error:' ../*SAN*/log/master.err; then  # UBSAN
      UBFLAG=1
      echo 'Set before execution:'
      echo "    export UBSAN_OPTIONS=print_stacktrace=1:report_error_type=1   # And you may also want to supress UBSAN startup issues using 'suppressions=UBSAN.filter' in UBSAN_OPTIONS. For an example of UBSAN.filter, which includes current startup issues see: https://github.com/mariadb-corporation/mariadb-qa/blob/master/UBSAN.filter"
    fi
    if grep -Eiqm1 --binary-files=text '=ERROR:|LeakSanitizer:|AddressSanitizer:' ../*SAN*/log/master.err; then  # ASAN
      # detect_invalid_pointer_pairs changed from 1 to 3 at start of 2021 (effectively used since)
      if [ "${UBFLAG}" != "1" ]; then  # Avoid double 'Set ...'
        echo 'Set before execution:'
      fi
      echo "    export ASAN_OPTIONS=quarantine_size_mb=512:atexit=0:detect_invalid_pointer_pairs=3:dump_instruction_bytes=1:abort_on_error=1:allocator_may_return_null=1"
      # check_initialization_order=1 cannot be used due to https://jira.mariadb.org/browse/MDEV-24546 TODO
      # detect_stack_use_after_return=1 will likely require thread_stack increase (check error log after ./all) TODO
      #echo "    export ASAN_OPTIONS=quarantine_size_mb=512:atexit=0:detect_invalid_pointer_pairs=3:dump_instruction_bytes=1:abort_on_error=1:allocator_may_return_null=1"
    fi
  fi
  if grep -Eiqm1 --binary-files=text 'MemorySanitizer:' ../*SAN*/log/master.err; then  # MSAN
    echo '    -DWITH_MSAN=ON  # Note: WITH_MSAN=ON is auto-ignored when not using clang (MDEV-20377)'
    echo 'Set before execution:'
    echo '    export MSAN_OPTIONS=abort_on_error=1:poison_in_dtor=0'
  fi
  echo '{noformat}'
fi
echo ''
# The test_all script auto-runs ./findbug_new which generates ../test.results[.san/.gal]. 
# If it does not exist, something went wrong
if [ "${1}" == "SAN" ]; then
  if [ -r ../test.results.san ]; then
    cat ../test.results.san
  else
    echo "ERROR: expected ../test.results.san to exist, but it did not. Please re-run bug_report.sh and/or debug any issues"
    exit 1
  fi
elif [ "${1}" == "MSAN" ]; then
  if [ -r ../test.results.san ]; then
    cat ../test.results.san
  else
    echo "ERROR: expected ../test.results.san to exist, but it did not. Please re-run bug_report.sh and/or debug any issues"
    exit 1
  fi
elif [ "${1}" == "GAL" ]; then
  if [ -r ../test.results.gal ]; then
    cat ../test.results.gal
  else
    echo "ERROR: expected ../test.results.gal to exist, but it did not. Please re-run bug_report.sh and/or debug any issues"
    exit 1
  fi
else
  if [ -r ../test.results ]; then
    cat ../test.results
  else
    echo "ERROR: expected ../test.results to exist, but it did not. Please re-run bug_report.sh and/or debug any issues"
    exit 1
  fi
fi
echo '-------------------- /BUG REPORT --------------------'
if [ "${1}" == "SAN" ]; then
  echo "TOTAL SAN OCCURRENCES SEEN ACCROSS ALL VERSIONS: ${CORE_OR_TEXT_COUNT_ALL}"
elif [ "${1}" == "MSAN" ]; then
  echo "TOTAL MSAN OCCURRENCES SEEN ACCROSS ALL VERSIONS: ${CORE_OR_TEXT_COUNT_ALL}"
elif [ "${1}" == "GAL" ]; then
  echo "TOTAL GALERA CORES SEEN ACCROSS ALL VERSIONS: ${CORE_OR_TEXT_COUNT_ALL}"
elif [ "${REPL_MODE}" -eq 1 ]; then
  echo "TOTAL CORES SEEN ACCROSS ALL VERSIONS (MASTERS+SLAVES): ${CORE_OR_TEXT_COUNT_ALL}"
else
  echo "TOTAL CORES SEEN ACCROSS ALL VERSIONS: ${CORE_OR_TEXT_COUNT_ALL}"
fi
if [ "${ALSO_CHECK_REGULAR_TESTCASES_AGAINST_SAN_BUILDS}" -eq 1 ]; then
  if [ "${1}" != "SAN" -a "${1}" != "GAL" ]; then  # Exclude UBASAN builds from self-running again (unnecessary duplication)
    echo "----- UBASAN Execution of the testcase ----- (Builds used: ${SAN_OPT_BUILD_FOR_REGULAR_TC_CHECK} and _dbg)"
    test_san_build "${SAN_OPT_BUILD_FOR_REGULAR_TC_CHECK}" opt
    test_san_build "${SAN_DBG_BUILD_FOR_REGULAR_TC_CHECK}" dbg
    echo '-----------------------------------------'
  fi
fi
if [ ${CORE_OR_TEXT_COUNT_ALL} -gt 0 -o ${SAN_MODE} -eq 1 -o ${MSAN_MODE} -eq 1 ]; then
  echo 'Remember to action:'
  echo "*) Check the 'SAN Execution of the testcase' mini-report just above. If a *SAN (i.e. 'ASAN|...', 'UBSAN|...' or 'TBSAN|...' etc.) UniqueID was seen in a SAN build, then please run a 'bs' report using the same in.sql testcase in that SAN build also. Copy the full resulting SAN matrix (and info on how to create/build a similar SAN build) into the bug report as well"
  echo '*) If no engine is specified, add ENGINE=InnoDB to table definitions and re-run the bug report'
  if [ ${NOCORE} -ne 1 -o ${SAN_MODE} -eq 1 -o ${MSAN_MODE} -eq 1 ]; then
    cd ${RUN_PWD}
    TEXT=
    FINDBUG=
    if [ ${SAN_MODE} -eq 1 -o ${MSAN_MODE} -eq 1 ]; then
      TEXT="$(${SCRIPT_PWD}/san_text_string.sh)"
      if [ ! -z "${TEXT}" ]; then
        echo "*) Add bug to ${SCRIPT_PWD}/known.strings.SAN, as follows (use ~/kba for quick access):"
        echo "${TEXT}"
        echo '*) Checking if this bug is already known:'
        FINDBUG="$(set +H; grep -Fi --binary-files=text "${TEXT}" ${SCRIPT_PWD}/known_bugs.strings.SAN | grep -v grep | grep -vE '^###|^[ ]*$')"
      fi
    else
      TEXT="$(${SCRIPT_PWD}/new_text_string.sh)"
      if [ ! -z "${TEXT}" ]; then
        echo "*) Add bug to ${SCRIPT_PWD}/known.strings, as follows (use ~/kb for quick access):"
        echo "${TEXT}"
        echo '*) Checking if this bug is already known:'
        FINDBUG="$(set +H; grep -Fi --binary-files=text "${TEXT}" ${SCRIPT_PWD}/known_bugs.strings | grep -v grep | grep -vE '^###|^[ ]*$')"
      fi
    fi
    if [ ! -z "${FINDBUG}" ]; then
      if [ "$(echo "${FINDBUG}" | sed 's|[ \t]*\(.\).*|\1|')" != "#" ]; then  # If true, then this is not a previously fixed bugs. If false (i.e. leading char is "#") then this is a previouly fixed bug remarked with a leading '#' in the known bugs file.
        # Do NOT change the text in the next echo line, it is used by mariadb-qa/move_known.sh
        echo "FOUND: This is an already known, and potentially not fixed yet, bug!"
        echo "${FINDBUG}"
      else
        echo "*** FOUND: This is an already known bug, but it was previously fixed! Research further! ***"
        echo "${FINDBUG}"
      fi
    elif [ ! -z "${TEXT}" ]; then
      FRAMEX="$(echo "${TEXT}" | sed 's/.*|\(.*\)|.*|.*$/\1/')"
      if [ "${FRAMEX}" == "mysql_execute_command" ]; then
        echo "BUG NOT FOUND (IDENTICALLY) IN KNOWN BUGS LIST! HOWEVER, A PARTIAL MATCH BASED ON THE 1st FRAME ('${FRAMEX}') WAS FOUND, BUT AS THAT STRING IS TOO GENERIC (AND THERE ARE THUS TOO MANY MATCHES), NO OUTPUT IS SHOWN HERE"
      else
        OUT2=
        if [ ${SAN_MODE} -eq 1 -o ${MSAN_MODE} -eq 1 ]; then
          OUT2="$(set +H; grep -Fi --binary-files=text "${FRAMEX}" ${SCRIPT_PWD}/known_bugs.strings.SAN | grep -v grep | grep -vE '^###|^[ ]*$')"
        else
          OUT2="$(set +H; grep -Fi --binary-files=text "${FRAMEX}" ${SCRIPT_PWD}/known_bugs.strings | grep -v grep | grep -vE '^###|^[ ]*$')"
        fi
        if [ -z "${OUT2}" ]; then
          echo "NOT FOUND: Bug not found yet in known_bugs.strings!"
          echo "*** THIS IS POSSIBLY A NEW BUG; BUT CHECK NEXT TODO ITEM BELOW FIRST! ***"
        else
          echo "BUG NOT FOUND (IDENTICALLY) IN KNOWN BUGS LIST! HOWEVER, A PARTIAL MATCH BASED ON THE 1st FRAME ('${FRAMEX}') WAS FOUND, AS FOLLOWS: (PLEASE CHECK IT IS NOT THE SAME BUG):"
          echo "${OUT2}"
        fi
        OUT2=
      fi
      FRAMEX=
    fi
    FINDBUG=
  fi
  if [ ! -z "${TEXT}" ]; then
    echo "*) Check for duplicates before logging bug, see handy search URL's below (can also be obtained by executing ~/tt from within the basedir of a failed instance)"
  else
    echo "*) Check for duplicates before logging bug; run ~/tt from within the basedir of a failed instance"
  fi
fi

# OLD
#  if [ ${NOCORE} -ne 1 ]; then
#    cd ${RUN_PWD}
#    FIRSTFRAME=$(${SCRIPT_PWD}/new_text_string.sh FRAMESONLY | sed 's/|.*//')
#    echo "https://jira.mariadb.org/browse/MDEV-21938?jql=text%20~%20%22%5C%22${FIRSTFRAME}%5C%22%22%20ORDER%20BY%20status%20ASC%2Cupdated%20DESC
#    echo "https://www.google.com/search?q=site%3Amariadb.org+%22${FIRSTFRAME}%22"
#  else
#    echo "https://jira.mariadb.org/browse/MDEV-21938?jql=text%20~%20%22%5C%22\${FIRSTFRAME}%5C%22%22"
#    echo "https://www.google.com/search?q=site%3Amariadb.org+%22\${FIRSTFRAME}%22"
#    echo "Please swap \${FIRSTFRAME} in the above to the first frame name. Regrettably this script could not obtain it for you (ref 'THIS TESTCASE DID NOT...' note above), but you can choose to re-run it from one of the 'Bug confirmed present in' directories, and it will produce ready-made URL's for you."
#  fi
