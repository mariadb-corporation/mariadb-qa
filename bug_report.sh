#!/bin/bash
# Created by Roel Van de Paar, MariaDB

set +H  # Disables history substitution and avoids  -bash: !: event not found  like errors

# User variables
ALSO_TEST_SAN_BUILD_FOR_NON_SAN_REPORTS=1
DEBUG_OUTPUT=0  # Set to 1 to see full output of test_all and kill_all (note: this generates lots of output, and it is in parallel threads, so it likely only useful for debugging major issues with test_all and/or kill_all, but it is likely better to check a ./test_all run in a BASEDIR directly). Default: 0, legacy default: 1 (i.e. before this option was implemented, all output was shown)

if [ ! -r /test/gendirs.sh ]; then
  echo 'Assert: /test/gendirs.sh not found, try running ~/mariadb-qa/linkit'
  exit 1
fi

# Script variables: do not change
SAN_BUILD_FOR_NON_SAN_REPORTS_OPT="/test/$(cd /test; ./gendirs.sh san | grep '10.1[0-9]' | grep 'opt' | sort -h | tail -n1)"
SAN_BUILD_FOR_NON_SAN_REPORTS_DBG="$(echo "${SAN_BUILD_FOR_NON_SAN_REPORTS_OPT}" | sed 's|\-opt|-dbg|')"

if [ "${ALSO_TEST_SAN_BUILD_FOR_NON_SAN_REPORTS}" -eq 1 ]; then
  if [ "${1}" != "SAN" ]; then
    if [ ! -d "${SAN_BUILD_FOR_NON_SAN_REPORTS_OPT}" ]; then
      echo "Assert: ALSO_TEST_SAN_BUILD_FOR_NON_SAN_REPORTS is enabled in the script (1), yet the directory SAN_BUILD_FOR_NON_SAN_REPORTS_OPT (${SAN_BUILD_FOR_NON_SAN_REPORTS_OPT}) does not exist"
      exit 1
    elif [ ! -d "${SAN_BUILD_FOR_NON_SAN_REPORTS_DBG}" ]; then
      echo "Assert: ALSO_TEST_SAN_BUILD_FOR_NON_SAN_REPORTS is enabled in the script (1), yet the directory SAN_BUILD_FOR_NON_SAN_REPORTS_DBG (${SAN_BUILD_FOR_NON_SAN_REPORTS_DBG}) does not exist"
      exit 1
    fi
  #else  # We do not need to display this, it is unecessary info
    #echo "ALSO_TEST_SAN_BUILD_FOR_NON_SAN_REPORTS is enabled (1), however this is a SAN run already, so ignoring this setting (safe)"
  fi
fi

# Terminate any other bug_report.sh scripts ongoing
# Does not work correctly TODO
#ps -ef | grep -v $$ | grep bug_report | grep -v grep | grep -v mass_bug_report | awk '{print $2}' | xargs kill -9 2>/dev/null

SAN_MODE=0
if [ -z "${PASS_MYEXTRA_TO_START_ONLY}" ]; then  # Check if an external script (like ~/b) has set this option. If not, set it here. If you want to use this option in combination with ~/b, set it there, or use export PASS_MYEXTRA_TO_START_ONLY=0 (or 1) before starting ~/b, or use ~/b0 or ~/b1 which are shortcuts
  PASS_MYEXTRA_TO_START_ONLY=1  # If 0, then MYEXTRA_OPT is passed to ./all (i.e. options take effect on init and start). If 1, then MYEXTRA_OPT is passed to ./start only (i.e. options take effect on start only, not init). When using for example --innodb_page_size=4 (an option needed for both server init + start), 0 is required. When using for example --innodb-force-recovery=1 or --innodb-read-only=1 (options that can only be used with start and not with init), 1 is required. TODO: this option can be automated 0/1 towards known options that require either 0 or 1 for this setting. Scan MYEXSTRA_OPT to do so
fi
export PASS_MYEXTRA_TO_START_ONLY=${PASS_MYEXTRA_TO_START_ONLY}
SHORTER_STOP_TIME=23   # TODO: this can be improved. Likely setting this smaller than 20 seconds is not a good idea, some cores/crashes may be missed (presumably on slow servers)

MYEXTRA_OPT="$*"
NOCORE=0
if [ "${1}" == "SAN" ]; then
  if [ -z "${TEXT}" ]; then   # Passed normally by ~/b preloader/wrapper sript
    echo "Assert: TEXT is empty, use export TEXT= to set it!"
    exit 1
  else
    echo "NOTE: SAN Mode: Looking for '${TEXT}' in the error log to validate issue occurence."
  fi
  MYEXTRA_OPT="$(echo "${MYEXTRA_OPT}" | sed 's|SAN||')"
  SAN_MODE=1
else
  if [ -z "${TEXT}" ]; then
    echo "NOTE: TEXT is empty; looking for corefiles, and not specific strings in the error log!"
    echo "If you want to scan for specific strings in the error log, then use:"
    echo "  export TEXT='your_search_text'  # to set it before running this script"
  else
    if [ "${TEXT}" == "BBB" ]; then
      echo "NOTE: Looking for crashes/asserts in the error log as well as core files to validate issue occurence."
    else
      echo "NOTE: Looking for '${TEXT}' in the error log to validate issue occurence."
    fi
  fi
fi
sleep 1
SCRIPT_PWD=$(cd "`dirname $0`" && pwd)
RUN_PWD=${PWD}

if [ ! -r bin/mysqld ]; then
  echo "Assert: bin/mysqld not available, please run this from a basedir which had the SQL executed against it an crashed"
  exit 1
fi

if [ "${1}" == "GAL" ]; then
  MYEXTRA_OPT="$(echo "${MYEXTRA_OPT}" | sed 's|GAL||')"
  if [ ! -r ./gal_no_cl ]; then  # Local
      echo "Assert: ./gal_no_cl not available, please run this from a basedir which was prepared with ${SCRIPT_PWD}/startup.sh"
      exit 1
  fi
else
  if [ ! -r ./all_no_cl ]; then  # Local
    echo "Assert: ./all_no_cl not available, please run this from a basedir which was prepared with ${SCRIPT_PWD}/startup.sh"
    exit 1
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

RANDOM=$(date +%s%N | cut -b10-19)  # Random entropy init
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
  ./all_no_cl ${MYEXTRA_OPT_CLEANED} >/dev/null 2>&1
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
if [ "${1}" == "SAN" ]; then
  ./test_all SAN ${MYEXTRA_OPT_CLEANED} ${REDIRECT}
elif [ "${1}" == "GAL" ]; then
  ./test_all GAL ${MYEXTRA_OPT_CLEANED} ${REDIRECT}
else
  ./test_all ${MYEXTRA_OPT_CLEANED} ${REDIRECT}
fi
echo "Ensuring all servers are gone..."
sync
if [ "${1}" == "SAN" ]; then
  ./kill_all SAN ${REDIRECT}
elif [ "${1}" == "GAL" ]; then
  ./kill_all GAL ${REDIRECT}
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
    CORE_OR_TEXT_COUNT_ALL=$(./gendirs.sh | xargs -I{} echo "ls {}/data/*core* 2>/dev/null" | xargs -I{} bash -c "{}" | wc -l)
  fi
else
  if [ "${1}" == "SAN" ]; then
    #echo "Searching error logs for the '=ERROR:|runtime error:|ThreadSanitizer:|LeakSanitizer:' (SAN mode enabled)"
    echo "TEXT set to '${TEXT}', searching error logs for the same (case insensitive, regex aware) (SAN mode enabled)"
    #CORE_OR_TEXT_COUNT_ALL=$(set +H; ./gendirs.sh SAN | xargs -I{} echo "grep -m1 -iE --binary-files=text '=ERROR:|runtime error:|ThreadSanitizer:|LeakSanitizer:' {}/log/master.err 2>/dev/null" | tr '\n' '\0' | xargs -0 -I{} bash -c "{}" | wc -l)
    CORE_OR_TEXT_COUNT_ALL=$(set +H; ./gendirs.sh SAN | xargs -I{} echo "grep -m1 -iE --binary-files=text '${TEXT}' {}/log/master.err 2>/dev/null" | tr '\n' '\0' | xargs -0 -I{} bash -c "{}" | wc -l)
  elif [ "${1}" == "GAL" ]; then
    echo "TEXT set to '${TEXT}', searching error logs for the same (case insensitive, regex aware)"
    CORE_OR_TEXT_COUNT_ALL=$(set +H; ./gendirs.sh GAL | xargs -I{} echo "grep -m1 -iE --binary-files=text '${TEXT}' {}/node1/node1.err 2>/dev/null" | tr '\n' '\0' | xargs -0 -I{} bash -c "{}" | wc -l)
  else
    echo "TEXT set to '${TEXT}', searching error logs for the same (case insensitive, regex aware)"
    CORE_OR_TEXT_COUNT_ALL=$(set +H; ./gendirs.sh | xargs -I{} echo "grep -m1 -iE --binary-files=text '${TEXT}' {}/log/master.err 2>/dev/null" | tr '\n' '\0' | xargs -0 -I{} bash -c "{}" | wc -l)
  fi
fi
cd - >/dev/null || exit 1

SOURCE_CODE_REV="$(grep -om1 --binary-files=text "Source control revision id for MariaDB source code[^ ]\+" bin/mysqld 2>/dev/null | tr -d '\0' | sed 's|.*source code||;s|Version||;s|version_source_revision||')"
if echo "${PWD}" | grep -q EMD ; then
  SERVER_VERSION="$(bin/mysqld --version | grep -om1 --binary-files=text '[0-9\.]\+-[0-9]-MariaDB' | sed 's|-MariaDB||')"
else
  SERVER_VERSION="$(bin/mysqld --version | grep -om1 --binary-files=text '[0-9\.]\+-MariaDB' | sed 's|-MariaDB||')"
fi
LAST_THREE="$(echo "${PWD}" | sed 's|.*\(...\)$|\1|')"
BUILD_TYPE=
if [ "${LAST_THREE}" == "opt" ]; then BUILD_TYPE="(Optimized)"; fi
if [ "${LAST_THREE}" == "dbg" ]; then BUILD_TYPE="(Debug)"; fi

# Check the current directory for outcome
if [ "${1}" == "GAL" ]; then
  CORE_COUNT=$(ls node1/*core* 2>/dev/null | wc -l)
  CORE_FILE=$(ls node1/*core* 2>/dev/null | head -1)
else
  CORE_COUNT=$(ls data/*core* 2>/dev/null | wc -l)
  CORE_FILE=$(ls data/*core* 2>/dev/null | head -1)
fi
if [ ${CORE_COUNT} -eq 0 ]; then
  echo "INFO: no cores found at data/*core*"
elif [ ${CORE_COUNT} -gt 1 ]; then
  echo "Assert: too many (${CORE_COUNT}) cores found at data/*core*, this should not happen (as ./all_no_cl was used which should have created a clean data directory)"
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
if [ ${SAN_MODE} -eq 0 ]; then
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
      echo -e "{noformat:title=${SERVER_VERSION} ${SOURCE_CODE_REV} ${BUILD_TYPE}}\n${ASSERT}\n{noformat}\n"
    fi
  fi

  echo "{noformat:title=${SERVER_VERSION} ${SOURCE_CODE_REV} ${BUILD_TYPE}}"
  if [ -r /tmp/${RANDF}.gdba ]; then
    grep --binary-files=text -A999 'Core was generated by' /tmp/${RANDF}.gdba | grep --binary-files=text -v '^(gdb)[ \t]*$' | grep --binary-files=text -v '^[0-9]\+.*No such file or directory.$' | sed 's|(gdb) (gdb) |(gdb) bt\n|' | sed 's|(gdb) (gdb) ||'
    rm -f /tmp/${RANDF}.gdba
  else
    NOCORE=1
    if [ "${1}" == "GAL" ]; then
      echo "THIS TESTCASE DID NOT CRASH ${SERVER_VERSION} (the version of the basedir in which you started this script), SO NO BACKTRACE IS SHOWN HERE. YOU CAN RE-EXECUTE THIS SCRIPT FROM ONE OF THE 'Bug confirmed present in' DIRECTORIES BELOW TO OBTAIN ONE, OR EXECUTE ./gal_no_cl; ./gal_test; ./stack FROM WITHIN THAT DIRECTORY TO GET A BACKTRACE ETC. MANUALLY!"
    else
      echo "THIS TESTCASE DID NOT CRASH ${SERVER_VERSION} (the version of the basedir in which you started this script), SO NO BACKTRACE IS SHOWN HERE. YOU CAN RE-EXECUTE THIS SCRIPT FROM ONE OF THE 'Bug confirmed present in' DIRECTORIES BELOW TO OBTAIN ONE, OR EXECUTE ./all_no_cl; ./test; ./stack FROM WITHIN THAT DIRECTORY TO GET A BACKTRACE ETC. MANUALLY!"
    fi
  fi
else
  echo "{noformat:title=${SERVER_VERSION} ${SOURCE_CODE_REV} ${BUILD_TYPE}}"
  grep -Ei --binary-files=text "${TEXT}" ./log/master.err | grep --binary-files=text -v "^[ \t]*$"
  # Check if a SAN stack is present and add it to output seperately
  if [ "$(grep -Ei --binary-files=text -A1 "${TEXT}" ./log/master.err | tail -n1 | grep -o '^[ ]*#0' | sed 's|[^#0]||g')" == "#0" ]; then
    LINE_BEFORE_SAN_STACK=$(grep -nEi --binary-files=text "${TEXT}" ./log/master.err | grep -o --binary-files=text '^[0-9]\+')
    if [ ! -z "${LINE_BEFORE_SAN_STACK}" ]; then
      echo '{noformat}'
      echo ''
      echo "{noformat:title=${SERVER_VERSION} ${SOURCE_CODE_REV} ${BUILD_TYPE}}"
      LINE_TO_READ=${LINE_BEFORE_SAN_STACK}
      while :; do  # Read stack line by line and print
        LINE_TO_READ=$[ ${LINE_TO_READ} + 1 ]
        LINE="$(head -n${LINE_TO_READ} ./log/master.err | tail -n1)"
        if [ -z "$(echo ${LINE} | sed 's|[ \t]||g')" ]; then break; fi
        echo "${LINE}"
        LINE=
      done
      LINE_TO_READ=
    fi
    LINE_BEFORE_SAN_STACK=
  fi
  # Check if a SAN stack is present in the alternative (dbg vs opt) and add it to output as well
  ALT_BASEDIR=
  ALT_BUILD_TYPE=
  if [[ "${PWD}" == *"opt" ]]; then
    ALT_BASEDIR="$(pwd | sed 's|opt$|dbg|')"
    ALT_BUILD_TYPE="(Debug)"
  elif [[ "${PWD}" == *"dbg" ]]; then
    ALT_BASEDIR="$(pwd | sed 's|dbg$|opt|')"
    ALT_BUILD_TYPE="(Optimized)"
  fi
  if [ ! -z "${ALT_BASEDIR}" -a "${ALT_BASEDIR}" != "${PWD}" ]; then
    if [ "$(grep -A1 --binary-files=text "${TEXT}" ${ALT_BASEDIR}/log/master.err | tail -n1 | grep -o '^[ ]*#0' | sed 's|[^#0]||g')" == "#0" ]; then
      LINE_BEFORE_SAN_STACK=$(grep -n "${TEXT}" ${ALT_BASEDIR}/log/master.err | grep -o '^[0-9]\+')
      if [ ! -z "${LINE_BEFORE_SAN_STACK}" ]; then
        echo '{noformat}'
        ALT_SOURCE_CODE_REV="$(grep -om1 --binary-files=text "Source control revision id for MariaDB source code[^ ]\+" ${ALT_BASEDIR}/bin/mysqld 2>/dev/null | tr -d '\0' | sed 's|.*source code||;s|Version||;s|version_source_revision||')"
        ALT_SERVER_VERSION="$(${ALT_BASEDIR}/bin/mysqld --version | grep -om1 '[0-9\.]\+-MariaDB' | sed 's|-MariaDB||')"
        echo ''
        echo "{noformat:title=${ALT_SERVER_VERSION} ${ALT_SOURCE_CODE_REV} ${ALT_BUILD_TYPE}}"
        ALT_SOURCE_CODE_REV=
        ALT_SERVER_VERSION=
        LINE_TO_READ=${LINE_BEFORE_SAN_STACK}
        while :; do  # Read stack line by line and print
          LINE_TO_READ=$[ ${LINE_TO_READ} + 1 ]
          LINE="$(head -n${LINE_TO_READ} ${ALT_BASEDIR}/log/master.err | tail -n1)"
          if [ -z "$(echo ${LINE} | sed 's|[ \t]||g')" ]; then break; fi
          echo "${LINE}"
          LINE=
        done
        LINE_TO_READ=
      fi
      LINE_BEFORE_SAN_STACK=
    fi
  fi
fi
if [ ${SAN_MODE} -eq 1 ]; then
  echo -e '{noformat}\n\nSetup:\n'
  echo '{noformat}'
  echo 'Compiled with GCC >=7.5.0 (I use GCC 9.4.0) and:'
  if grep -qm1 --binary-files=text 'ThreadSanitizer:' ../*SAN*/log/master.err; then  # TSAN
    echo '    -DWITH_TSAN=ON -DWSREP_LIB_WITH_TSAN=ON -DMUTEXTYPE=sys'
  fi
  if grep -qm1 --binary-files=text '=ERROR:' ../*SAN*/log/master.err; then  # UBSAN/ASAN (best not to split here, as options may interact: bug reproducibility max)
    echo '    -DWITH_ASAN=ON -DWITH_ASAN_SCOPE=ON -DWITH_UBSAN=ON -DWITH_RAPID=OFF -DWSREP_LIB_WITH_ASAN=ON'
  elif grep -qm1 --binary-files=text 'runtime error:' ../*SAN*/log/master.err; then  # UBSAN/ASAN (best not to split ASAN vs UBSAN build here, and to just leave both enabled, as these features, when both are enabled, may affect the server differently then only one is enabled: we thus maximize bug reproducibility through leaving the same options enabled as where there during testing)  # elif; avoids double printing
    echo '    -DWITH_ASAN=ON -DWITH_ASAN_SCOPE=ON -DWITH_UBSAN=ON -DWITH_RAPID=OFF -DWSREP_LIB_WITH_ASAN=ON'
  elif grep -qm1 --binary-files=text 'LeakSanitizer:' ../*SAN*/log/master.err; then  # LSAN: this was an ASAN (or UBSAN/ASAN) build
    echo '    -DWITH_ASAN=ON -DWITH_ASAN_SCOPE=ON -DWITH_UBSAN=ON -DWITH_RAPID=OFF -DWSREP_LIB_WITH_ASAN=ON'
  fi
  echo 'Set before execution:'
  if grep -qm1 --binary-files=text 'ThreadSanitizer:' ../*SAN*/log/master.err; then  # TSAN
    # A note on exitcode=0: whereas we do not use this in our runs, it is required to let MTR bootstrap succeed.
    # TODO: Once code becomes more stable add: halt_on_error=1
    echo '    export TSAN_OPTIONS=suppress_equal_stacks=1:suppress_equal_addresses=1:history_size=7:verbosity=1:exitcode=0'
  fi
  if grep -Eiqm1 --binary-files=text '=ERROR:|LeakSanitizer:' ../*SAN*/log/master.err; then  # ASAN
    # detect_invalid_pointer_pairs changed from 1 to 3 at start of 2021 (effectively used since)
    echo '    export ASAN_OPTIONS=quarantine_size_mb=512:atexit=1:detect_invalid_pointer_pairs=3:dump_instruction_bytes=1:abort_on_error=1:allocator_may_return_null=1'
    # check_initialization_order=1 cannot be used due to https://jira.mariadb.org/browse/MDEV-24546 TODO
    # detect_stack_use_after_return=1 will likely require thread_stack increase (check error log after ./all) TODO
    #echo '    export ASAN_OPTIONS=quarantine_size_mb=512:atexit=1:detect_invalid_pointer_pairs=3:dump_instruction_bytes=1:abort_on_error=1:allocator_may_return_null=1'
  fi
  if grep -qm1 --binary-files=text 'runtime error:' ../*SAN*/log/master.err; then  # UBSAN
    echo '    export UBSAN_OPTIONS=print_stacktrace=1'
  fi
fi
echo -e '{noformat}\n'
if [ -z "${TEXT}" ]; then
  if [ -r ../test.results ]; then
    cat ../test.results
  else
    echo "--------------------------------------------------------------------------------------------------------------"
    echo "ERROR: expected ../test.results to exist, but it did not. Running:  ./findbug+ 'BBB' (common crash strings are all scanned), though this may fail."
    echo "--------------------------------------------------------------------------------------------------------------"
    cd ..; ./findbug+ 'BBB'; cd - >/dev/null
  fi
else
  if [ "${1}" == "SAN" ]; then
    if [ -r ../test.results ]; then
      cat ../test.results
    else
      echo "--------------------------------------------------------------------------------------------------------------"
      echo "ERROR: expected ../test.results to exist, but it did not. Running:  ./findbug+ SAN '${TEXT}', though this may fail."
      echo "--------------------------------------------------------------------------------------------------------------"
      cd ..; ./findbug+ SAN "${TEXT}"; cd - >/dev/null
    fi
  elif [ "${1}" == "GAL" ]; then
    cd ..; ./findbug+ GAL "${TEXT}"; cd - >/dev/null
  else
    cd ..; ./findbug+ "${TEXT}"; cd - >/dev/null
  fi
fi
echo '-------------------- /BUG REPORT --------------------'
if [ "${1}" == "SAN" ]; then
  echo "TOTAL SAN OCCURENCES SEEN ACCROSS ALL VERSIONS: ${CORE_OR_TEXT_COUNT_ALL}"
elif [ "${1}" == "GAL" ]; then
  echo "TOTAL GALERA CORES SEEN ACCROSS ALL VERSIONS: ${CORE_OR_TEXT_COUNT_ALL}"
else
  echo "TOTAL CORES SEEN ACCROSS ALL VERSIONS: ${CORE_OR_TEXT_COUNT_ALL}"
fi
if [ "${1}" != "SAN" -a "${1}" != "GAL" ]; then
  if [ "${ALSO_TEST_SAN_BUILD_FOR_NON_SAN_REPORTS}" -eq 1 ]; then
    echo '----- SAN Execution of the testcase -----'
    test_san_build "${SAN_BUILD_FOR_NON_SAN_REPORTS_OPT}" opt
    test_san_build "${SAN_BUILD_FOR_NON_SAN_REPORTS_DBG}" dbg
    echo '-----------------------------------------'
  fi
fi
if [ ${CORE_OR_TEXT_COUNT_ALL} -gt 0 -o ${SAN_MODE} -eq 1 ]; then
  echo 'Remember to action:'
  echo '*) If no engine is specified, add ENGINE=InnoDB to table definitions and re-run the bug report'
  if [ ${NOCORE} -ne 1 -o ${SAN_MODE} -eq 1 ]; then
    cd ${RUN_PWD}
    TEXT=
    FINDBUG=
    if [ ${SAN_MODE} -eq 1 ]; then
      TEXT="$(${SCRIPT_PWD}/san_text_string.sh)"
      if [ ! -z "${TEXT}" ]; then
        echo "*) Add bug to ${SCRIPT_PWD}/known.strings.SAN, as follows (use ~/kba for quick access):"
        echo "${TEXT}"
        echo '*) Checking if this bug is already known:'
        FINDBUG="$(grep -Fi --binary-files=text "${TEXT}" ${SCRIPT_PWD}/known_bugs.strings.SAN | grep -v grep | grep -vE '^###|^[ ]*$')"
      fi
    else
      TEXT="$(${SCRIPT_PWD}/new_text_string.sh)"
      if [ ! -z "${TEXT}" ]; then
        echo "*) Add bug to ${SCRIPT_PWD}/known.strings, as follows (use ~/kb for quick access):"
        echo "${TEXT}"
        echo '*) Checking if this bug is already known:'
        FINDBUG="$(grep -Fi --binary-files=text "${TEXT}" ${SCRIPT_PWD}/known_bugs.strings | grep -v grep | grep -vE '^###|^[ ]*$')"
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
        if [ ${SAN_MODE} -eq 1 ]; then
          OUT2="$(grep -Fi --binary-files=text "${FRAMEX}" ${SCRIPT_PWD}/known_bugs.strings.SAN | grep -v grep | grep -vE '^###|^[ ]*$')"
        else
          OUT2="$(grep -Fi --binary-files=text "${FRAMEX}" ${SCRIPT_PWD}/known_bugs.strings | grep -v grep | grep -vE '^###|^[ ]*$')"
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
#    echo "https://jira.mariadb.org/browse/MDEV-21938?jql=text%20~%20%22%5C%22${FIRSTFRAME}%5C%22%22%20ORDER%20BY%20status%20ASC"
#    echo "https://www.google.com/search?q=site%3Amariadb.org+%22${FIRSTFRAME}%22"
#  else
#    echo "https://jira.mariadb.org/browse/MDEV-21938?jql=text%20~%20%22%5C%22\${FIRSTFRAME}%5C%22%22"
#    echo "https://www.google.com/search?q=site%3Amariadb.org+%22\${FIRSTFRAME}%22"
#    echo "Please swap \${FIRSTFRAME} in the above to the first frame name. Regrettably this script could not obtain it for you (ref 'THIS TESTCASE DID NOT...' note above), but you can choose to re-run it from one of the 'Bug confirmed present in' directories, and it will produce ready-made URL's for you."
#  fi
