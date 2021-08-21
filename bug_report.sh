#!/bin/bash
# Created by Roel Van de Paar, MariaDB

# Terminate any other bug_report.sh scripts ongoing
# Does not work correctly
#ps -ef | grep -v $$ | grep bug_report | grep -v grep | grep -v mass_bug_report | awk '{print $2}' | xargs kill -9 2>/dev/null

SAN_MODE=0
USE_WIPE_AND_START=0   # Use ./kill, ./wipe and ./start with mysqld options passed to ./start only. This can be handy when for example using --innodb-force-recovery=x which only should be passed to ./start and will fail when used with ./all_no_cl. IOW instead of ./all_no_cl, ./kill, ./wipe and ./start are used and instead of passing all options to the init called by ./all_no_cl they are not passed to the init when this option is set to 1. Note that the reverse requirement can be required too; for example when using --innodb_page_size=4k, this should be set to 0 as that option is definitely required in the init startup (as arranged by ./all_no_cl). For general use, leave set to 0. For specific use (like --innodb-force-recovery=x set to 1).
SHORTER_STOP_TIME=23   # TODO: this can be improved. Likely setting this smaller than 20 seconds is not a good idea, some cores/crashes may be missed (presumably on slow servers)

MYEXTRA_OPT="$*"
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
  echo 'Note that any mysqld options need to be listed as follows on the first line in the testcase (as shown above):'
  echo '# mysqld options required for replay:  --someoption[=somevalue]'
fi
sleep 2.5  # For visual confirmation

# Note that the following may do a duplicate run of the testcase on the current PWD basedir directory, which at first glance seems unnessary duplication. If the current PWD basedir directory is part of gendirs that is likely true. However, if it not (like for example a special build) then the code below will still test the testcase against this current PWD basedir directory and make a bug report on that (whilst also reporting on all other versions/dirs listed in gendirs). TODO this can then (if that reasoning about past reasons is correct) be slightly shortened by checking if the current PWD basedir is in gendirs and skip the re-test in such case, and just use the results already present in the current dir as created by test_all. 
if [ ${SAN_MODE} -eq 0 ]; then
  if [ "${1}" == "GAL" ]; then
    ./gal_no_cl ${MYEXTRA_OPT_CLEANED}
    ./gal_test
    timeout -k${SHORTER_STOP_TIME} -s9 ${SHORTER_STOP_TIME}s ./gal_stop; sleep 0.2; ./kill 2>/dev/null; sleep 0.2
    CORE_COUNT=$(ls node1/*core* 2>/dev/null | wc -l)
    CORE_FILE=$(ls node1/*core* 2>/dev/null | head -1)
  else
    if [ ${USE_WIPE_AND_START} -eq 1 ]; then
      ./kill
      ./wipe  # Note that the init called here does not use MYEXTRA options, unlike when ./all_no_cl is used
      ./start ${MYEXTRA_OPT_CLEANED}
    else
      ./all_no_cl ${MYEXTRA_OPT_CLEANED}
    fi
    ./test
    timeout -k${SHORTER_STOP_TIME} -s9 ${SHORTER_STOP_TIME}s ./stop; sleep 0.2; ./kill 2>/dev/null; sleep 0.2
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
fi

rm -f ../in.sql
if [ -r ../in.sql ]; then echo "Assert: ../in.sql still available after it was removed!"; exit 1; fi
cp in.sql ..
if [ ! -r ../in.sql ]; then echo "Assert: ../in.sql not available after copy attempt!"; exit 1; fi
cd ..
echo "Testing all..."
if [ "${1}" == "SAN" ]; then
  ./test_all SAN ${MYEXTRA_OPT_CLEANED}
elif [ "${1}" == "GAL" ]; then
  ./test_all GAL ${MYEXTRA_OPT_CLEANED}
else
  ./test_all ${MYEXTRA_OPT_CLEANED}
fi
echo "Ensuring all servers are gone..."
sync
if [ "${1}" == "SAN" ]; then
  ./kill_all SAN
elif [ "${1}" == "GAL" ]; then
  ./kill_all GAL
else
  ./kill_all # NOTE: Can not be executed as ../kill_all as it requires ./gendirs.sh
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
    echo "TEXT set to '${TEXT}', searching error logs for the same (case insensitive, regex aware) (SAN mode enabled)"
    CORE_OR_TEXT_COUNT_ALL=$(set +H; ./gendirs.sh SAN | xargs -I{} echo "grep -m1 -iE --binary-files=text '${TEXT}' {}/log/master.err 2>/dev/null" | xargs -I{} bash -c "{}" | wc -l)
  elif [ "${1}" == "GAL" ]; then
    echo "TEXT set to '${TEXT}', searching error logs for the same (case insensitive, regex aware)"
    CORE_OR_TEXT_COUNT_ALL=$(set +H; ./gendirs.sh GAL | xargs -I{} echo "grep -m1 -iE --binary-files=text '${TEXT}' {}/node1/node1.err 2>/dev/null" | xargs -I{} bash -c "{}" | wc -l)
  else
    echo "TEXT set to '${TEXT}', searching error logs for the same (case insensitive, regex aware)"
    CORE_OR_TEXT_COUNT_ALL=$(set +H; ./gendirs.sh | xargs -I{} echo "grep -m1 -iE --binary-files=text '${TEXT}' {}/log/master.err 2>/dev/null" | xargs -I{} bash -c "{}" | wc -l)
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
  NOCORE=0
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
  grep -Ei --binary-files=text "${TEXT}" ./log/master.err
  # Check if a SAN stack is present and add it to output seperately
  if [ "$(grep -Ei --binary-files=text -A1 "${TEXT}" ./log/master.err | tail -n1 | grep -o '^[ ]*#0' | sed 's|[^#0]||g')" == "#0" ]; then
    LINE_BEFORE_SAN_STACK=$(grep -nEi --binary-files=text "${TEXT}" ./log/master.err | grep -o --binary-files=text '^[0-9]\+')
    if [ ! -z "${LINE_BEFORE_SAN_STACK}" ]; then
      echo ''
      echo '{noformat}'
      echo ''
      echo "{noformat:title=${SERVER_VERSION} ${SOURCE_CODE_REV} ${BUILD_TYPE}}"
      LINE_TO_READ=$[ ${LINE_BEFORE_SAN_STACK} + 1 ]
      while true; do  # Read stack line by line and print
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
        LINE_TO_READ=$[ ${LINE_BEFORE_SAN_STACK} + 1 ]
        while true; do  # Read stack line by line and print
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
  echo 'Compiled with GCC >=7.5.0 (I use GCC 9.3.0) and:'
  if grep -qm1 --binary-files=text 'ThreadSanitizer:' ./log/master.err; then  # TSAN
    echo '    -DWITH_TSAN=ON -DWSREP_LIB_WITH_TSAN=ON -DMUTEXTYPE=sys'
  fi
  if grep -qm1 --binary-files=text '=ERROR:' ./log/master.err; then  # UBSAN/ASAN (best not to split here, as options may interact: bug reproducibility max)
    echo '    -DWITH_ASAN=ON -DWITH_ASAN_SCOPE=ON -DWITH_UBSAN=ON -DWITH_RAPID=OFF -DWSREP_LIB_WITH_ASAN=ON'
  fi
  echo 'Set before execution:'
  if grep -qm1 --binary-files=text 'ThreadSanitizer:' ./log/master.err; then  # TSAN
    # A note on exitcode=0: whereas we do not use this in our runs, it is required to let MTR bootstrap succeed.
    # TODO: Once code becomes more stable add: halt_on_error=1
    echo '    export TSAN_OPTIONS=suppress_equal_stacks=1:suppress_equal_addresses=1:history_size=7:verbosity=1:exitcode=0'
  fi
  if grep -qm1 --binary-files=text '=ERROR:' ./log/master.err; then  # ASAN
    # detect_invalid_pointer_pairs changed from 1 to 3 at start of 2021 (effectively used since)
    echo '    export ASAN_OPTIONS=quarantine_size_mb=512:atexit=1:detect_invalid_pointer_pairs=3:dump_instruction_bytes=1:abort_on_error=1'
    # check_initialization_order=1 cannot be used due to https://jira.mariadb.org/browse/MDEV-24546 TODO
    # detect_stack_use_after_return=1 will likely require thread_stack increase (check error log after ./all) TODO
    #echo '    export ASAN_OPTIONS=quarantine_size_mb=512:atexit=1:detect_invalid_pointer_pairs=3:dump_instruction_bytes=1:check_initialization_order=1:detect_stack_use_after_return=1:abort_on_error=1'
  fi
  if grep -qm1 --binary-files=text 'runtime error:' ./log/master.err; then  # UBSAN
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
if [ ${SAN_MODE} -eq 0 ]; then
  if [ ${CORE_OR_TEXT_COUNT_ALL} -gt 0 ]; then
    echo 'Remember to action:'
    echo '1) If no engine is specified, add ENGINE=InnoDB'
    echo '2) Double check noformat version strings for non-10.5/10.6 issues to see if it is correctly formatted'
    if [ ${NOCORE} -ne 1 ]; then
      echo '3A) Add bug to known.strings, as follows:'
      cd ${RUN_PWD}
      TEXT="$(${SCRIPT_PWD}/new_text_string.sh)"
      echo "${TEXT}"
      echo '3B) Checking if this bug is already known:'
      set +H  # Disables history substitution and avoids  -bash: !: event not found  like errors
      FINDBUG="$(grep -Fi --binary-files=text "${TEXT}" ${SCRIPT_PWD}/known_bugs.strings)"
      if [ ! -z "${FINDBUG}" ]; then
        if [ "$(echo "${FINDBUG}" | sed 's|[ \t]*\(.\).*|\1|')" != "#" ]; then  # If true, then this is not a previously fixed bugs. If false (i.e. leading char is "#") then this is a previouly fixed bug remarked with a leading '#' in the known bugs file.
          # Do NOT change the text in the next echo line, it is used by mariadb-qa/move_known.sh
          echo "FOUND: This is an already known, and potentially not fixed yet, bug!"
          echo "${FINDBUG}"
        else
          echo "*** FOUND: This is an already known bug, but it was previously fixed! Research further! ***"
          echo "${FINDBUG}"
        fi
      else
        FRAMEX="$(echo "${TEXT}" | sed 's/.*|\(.*\)|.*|.*$/\1/')"
        OUT2="$(grep -Fi --binary-files=text "${FRAMEX}" ${SCRIPT_PWD}/known_bugs.strings)"
        if [ -z "${OUT2}" ]; then
          echo "NOT FOUND: Bug not found yet in known_bugs.strings!"
          echo "*** THIS IS POSSIBLY A NEW BUG; BUT CHECK #4 BELOW FIRST! ***"
        else
          echo "BUG NOT FOUND (IDENTICALLY) IN KNOWN BUGS LIST! HOWEVER, A PARTIAL MATCH BASED ON THE 1st FRAME ('${FRAMEX}') WAS FOUND, AS FOLLOWS: (PLEASE CHECK IT IS NOT THE SAME BUG):"
          echo "${OUT2}"
        fi
        FRAMEX=
        OUT2=
      fi
      FINDBUG=
    else
      echo "3) Add bug to known.strings, using ${SCRIPT_PWD}/new_text_string.sh in the basedir of a crashed instance"
    fi
    echo '4) Check for duplicates before logging bug by executing ~/tt from within the basedir of a crashed instance and following the search url/instructions there'
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
