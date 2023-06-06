#!/bin/bash
# Created by Roel Van de Paar, MariaDB
# Expanded by Ramesh Sivaraman, MariaDB

# This script (new_text_string.sh) generates a UniqueID for a given crash, assert, ASAN, UBSAN, LSAN or TSAN issue
# It is generall executed from within a BASEDIR which has experienced a failure of any of these types

# Exit codes in this script are significant; used by reducer.sh and potentially other scripts
# First option to this script can be;
# ./new_text_string.sh 'FRAMESONLY'    # Used in automation, ref mass_bug_report.sh
# ./new_text_string.sh "${mysqld_loc}" # Where mysqld

# Quick check to see if sleep can be skipped for *SAN issues (much faster output and automation)
if [ $(grep -m1 --binary-files=text -E "=ERROR:|ThreadSanitizer:|runtime error:|LeakSanitizer:" ./log/master.err 2>/dev/null | wc -l) -eq 0 ]; then  # If no such issue found (count is 0), sleep x seconds to allow core, if any, to finish writing
  # Whilst 2 seconds is almost surely not sufficient for all cores to finish writing on heavily loaded machines,
  # There is a tradeoff here - this script is very often called during automation and all sorts of other processing,
  # thus many things are affected even by a single second more. On the flip side, more failures may be observed
  # with a shorter sleep duration. Test over time. 3 Seconds was the original setting and this worked reasonably,
  # now testing with a shorter 2 seconds sleep
  sleep 2  # Do not remove, sometimes cores are slow to write!
fi

SCRIPT_PWD=$(dirname $(readlink -f "${0}"))
if [ "${SCRIPT_PWD}" == "${HOME}" -a -r "${HOME}/mariadb-qa/new_text_string.sh" ]; then  # Provision for ~/t symlink
  SCRIPT_PWD="${HOME}/mariadb-qa"
fi
FRAMESONLY=0
SHOWINFO=0
ERROR_LOG=
MYSQLD=
TRIAL=
LOC=${PWD}

if [ $(df -k -P /tmp | grep -E --binary-files=text -v "Mounted" | awk '{print $4}') -lt 400000 ]; then
  echo 'Error: /tmp does not have enough free space (400Mb free space required for temporary files and any ongoing programs)'
  echo "Terminating now."
  exit 1
fi

if [ ! -z "${1}" ]; then
  if [ "${1}" == "SHOWINFO" -a ! -z "${2}" ]; then  # Used in automation, ref mariadb-qa/fuzzer/process_testcases
    SHOWINFO=1
    SHOWTEXT="${2}"
  elif [ "${1}" == "FRAMESONLY" ]; then  # Used in automation, ref mass_bug_report.sh
    FRAMESONLY=1
  elif [ -f "${1}" -a -x "${1}" ]; then
    if [ "$(readlink -f "${1}" | xargs file | grep -o 'ELF 64-bit LSB')" == "ELF 64-bit LSB" ]; then
      MYSQLD="${1}"
    else
      echo "Assert: an option (${1}) was passed to this script, but that option does not make sense to this script [ref #1]"
      exit 1
    fi
  elif [ -d "${1}" -a "$(echo "${1}" | grep -o '[0-9]\+')" == "${1}" ]; then
    TRIAL="${1}"
    LOC="${PWD}/${TRIAL}"
  elif grep --binary-files=text -q '#[0-9]  ' "${1}"; then  # Likely raw GDB trace was passed, parse as such
    echo "$(cat "${1}" | grep --binary-files=text -v '^[ \t]*$' | tr '\n' ' ' | sed 's|\(#[0-9]\+[ ]\+\)|\n\1|g' | grep --binary-files=text -v '^[ \t]*$' | head -n4 | sed 's|^#[0-9]\+[ ]\+||;s|^0x[0-9A-Fa-f]\+[ ]\+||;s| [^ ]\+$||;s|[ ]*(.*||' | tr '\n' '|' | sed 's/|$/\n/' | sed 's/^/RAW_GDB_UID|/' )"  # Output is based on GDB trace only (not a true UniqueID)
    exit 0
  else
    echo "Assert: an option (${1}) was passed to this script, but that option does not make sense to this script [ref #2]"
    exit 1
  fi
fi

if [ -z "${MYSQLD}" ]; then
  if [ -r ./bin/mariadbd -a ! -d ./bin/mariadbd ]; then  # For direct use in BASEDIR, like ~/tt
    MYSQLD="./bin/mariadbd"
  elif [ -r ./bin/mysqld -a ! -d ./bin/mysqld ]; then  # For direct use in BASEDIR, like ~/tt
    MYSQLD="./bin/mysqld"
  elif [ -r ./mysqld/mariadbd -a ! -z "${TRIAL}" ]; then  # For trial sub dirs in workdirs
    MYSQLD="./mysqld/mariadbd"
  elif [ -r ./mysqld/mysqld -a ! -z "${TRIAL}" ]; then  # For trial sub dirs in workdirs
    MYSQLD="./mysqld/mysqld"
  elif [ -r ../bin/mariadbd -a ! -d ../bin/mariadbd ]; then  # Used by pquery-run.sh when analyzing trial cores in-run
    MYSQLD="../bin/mariadbd"
  elif [ -r ../mariadbd -a ! -d ../mariadbd ]; then  # Used by pquery-run.sh when analyzing trial cores in-run
    MYSQLD="../mariadbd"
  elif [ -r ../mysqld -a ! -d ../mysqld ]; then  # Used by pquery-run.sh when analyzing trial cores in-run
    MYSQLD="../mysqld"
  elif [ -r ../bin/mysqld -a ! -d ../bin/mysqld ]; then  # Used by pquery-run.sh when analyzing trial cores in-run
    MYSQLD="../bin/mysqld"
  elif [ -r ../mysqld/mariadbd -a ! -d ../mysqld/mariadbd ]; then  # For direct use inside trial directories
    MYSQLD="../mysqld/mariadbd"
  elif [ -r ../mysqld/mysqld -a ! -d ../mysqld/mysqld ]; then  # For direct use inside trial directories
    MYSQLD="../mysqld/mysqld"
  elif [ -r ../../mysqld/mariadbd -a ! -d ../../mysqld/mariadbd ]; then  # Used by pquery-pre-red.sh to re-generate MYBUG string with valid input
    MYSQLD="../../mysqld/mariadbd"
  elif [ -r ../../mysqld/mysqld -a ! -d ../../mysqld/mysqld ]; then  # Used by pquery-pre-red.sh to re-generate MYBUG string with valid input
    MYSQLD="../../mysqld/mysqld"
  elif [ -r ../../../../../bin/mariadbd -a ! -d ../../../../../bin/mariadbd ]; then  # Used with/for MTR 
    mariadbd="../../../../../bin/mariadbd"
  elif [ -r ../../../../../bin/mysqld -a ! -d ../../../../../bin/mysqld ]; then  # Used with/for MTR 
    MYSQLD="../../../../../bin/mysqld"
  elif [ -r ./log/master.err ]; then
    POTENTIAL_MYSQLD="$(grep "ready for connections" ./log/master.err | sed 's|: .*||;s|^.* ||' | head -n1)"
    if [ -r ${POTENTIAL_MYSQLD} ]; then
      MYSQLD="${POTENTIAL_MYSQLD}"
    fi
  elif [ -r ./node1/node1.err ]; then
    POTENTIAL_MYSQLD="$(grep "ready for connections" ./node1/node1.err | sed 's|: .*||;s|^.* ||' | head -n1)"
    if [ -f ${POTENTIAL_MYSQLD} -a -r ${POTENTIAL_MYSQLD} ]; then
      MYSQLD="${POTENTIAL_MYSQLD}"
    fi
  elif [ -r ./node2/node2.err ]; then
    POTENTIAL_MYSQLD="$(grep "ready for connections" ./node2/node2.err | sed 's|: .*||;s|^.* ||' | head -n1)"
    if [ -f ${POTENTIAL_MYSQLD} -a -r ${POTENTIAL_MYSQLD} ]; then
      MYSQLD="${POTENTIAL_MYSQLD}"
    fi
  else
    echo "Assert: mysqld not found at ./bin/mysqld, nor ../mysqld, nor ../mysqld/mysqld nor other potential mysqld's extracted from any logs at ./log/master.err or ./node1/node1.err"
    exit 1
  fi
fi

if [ "${MDG}" != "1" ]; then
  if [ ! -z "$(ls --color=never ./node*/node*.err 2>/dev/null)" ]; then
    MDG=1
  fi
fi

if [[ ${MDG} -eq 1 ]]; then
  ERROR_LOG=${GALERA_ERROR_LOG}
  LATEST_CORE=${GALERA_CORE_LOC}
  if [ -z "${ERROR_LOG}" ]; then  # Interactive call from basedir
    if [ -r ${LOC}/node1/node1.err ]; then
      ERROR_LOG="${LOC}/node1/node1.err"
    elif [ -r ${LOC}/node2/node2.err ]; then
      ERROR_LOG="${LOC}/node2/node2.err"
    else
      echo "Assert: no error log found for Galera run!"
      exit 1
    fi
  fi
  if [ -z "${LATEST_CORE}" ]; then  # Interactive call from basedir
    LATEST_CORE="$(ls -t --color=never ${LOC}/node*/*core* 2>/dev/null)"
  fi
else
  ERROR_LOG=$(ls ${LOC}/log/master.err 2>/dev/null | head -n1)
  LATEST_CORE=$(ls -t ${LOC}/*/*core* 2>/dev/null | grep -v 'PREV' | head -n1)  # Exclude data.PREV
fi

if [ -z "${ERROR_LOG}" ]; then
  if [ -r "../../mysqld.1.err" ]; then
    ERROR_LOG="../../mysqld.1.err"
  elif [ -r "./var/log/mysqld.1.err" ]; then  # For MTR, default ./mtr test runs (e.g. testcase in main/test.test)
    ERROR_LOG="./var/log/mysqld.1.err"
  # TODO: add auto-discovery of correct log to use for below entries, or better: merge logs into one temporary file for overall scan 
  elif [ -r "./var/log/mysqld.3.1.err" ]; then  # For MTR Spider (and other) test runs (may not be correct one)
    ERROR_LOG="./var/log/mysqld.3.1.err"
  elif [ -r "./var/log/mysqld.2.1.err" ]; then  # For MTR Spider (and other) test runs (may not be correct one)
    ERROR_LOG="./var/log/mysqld.2.1.err"
  elif [ -r "./var/log/mysqld.1.1.err" ]; then  # For MTR Spider (and other) test runs (may not be correct one)
    ERROR_LOG="./var/log/mysqld.1.1.err"
  else
    echo "Assert: no error log found - exiting"
    exit 1
  fi
fi

if [ ! -r "${ERROR_LOG}" ]; then
  echo "Assert: ${ERROR_LOG} set but not readable (this should not happen!)"
  exit 1
fi

find_other_possible_issue_strings(){
  # If all else failed, check if there are other interesting issues
  # TODO, over time, it may make sense to rotate the issues below in to a different order. The benefit of this is increased
  # coverage of issues which may appear together in a single trial, thereby maskign the other etc.
  # sed 's|: [0-9]\+||': Remove the number of of bytes, as often this significantly increases reproducibility of the SQL
  MEMNOTFREED="$(grep -i 'Warning: Memory not freed' "${ERROR_LOG}" | head -n1 | sed 's|: [0-9]\+||' | tr -d '\n')"
  if [ ! -z "${MEMNOTFREED}" ]; then
    TEXT="MEMORY_NOT_FREED|${MEMNOTFREED}"
    echo "${TEXT}"
    exit 0
  fi
  GOTERROR="$(grep -io 'mysqld: Got error[^"]\+"[^"]\+"' "${ERROR_LOG}" | head -n1 | tr -d '\n' | sed 's|"||g' | sed "s|'||g" | grep -io 'Got error [0-9]\+[^\.]\+' | sed 's/Got error \([0-9]\+\)[ ]*/Got error \1|/i')"
  if [ ! -z "${GOTERROR}" ]; then
    TEXT="GOT_ERROR|${GOTERROR}"
    echo "${TEXT}"
    exit 0
  else
    GOTERROR="$(grep -io 'Got error.*' "${ERROR_LOG}" | head -n1 | sed "s|when reading table '.*|when reading table|" | sed 's/Got error \([0-9]\+\)[ ]*/Got error \1|/i')"
    if [ ! -z "${GOTERROR}" ]; then
      TEXT="GOT_ERROR|${GOTERROR}"
      echo "${TEXT}"
      exit 0
    fi
  fi
  MARKEDASCRASHED="$(grep -io 'mysqld: Table.*is marked as crashed and should be repaired' "${ERROR_LOG}" | head -n1 | tr -d '\n' | sed 's|"||g' | sed "s|'||g" )"
  if [ ! -z "${MARKEDASCRASHED}" ]; then
    TEXT="MARKED_AS_CRASHED|${MARKEDASCRASHED}"
    echo "${TEXT}"
    exit 0
  fi
  MDERRORCODE="$(grep -io 'MariaDB error code: [0-9]\+' "${ERROR_LOG}" | head -n1 | tr -d '\n')"
  if [ ! -z "${MDERRORCODE}" ]; then
    TEXT="MARIADB_ERROR_CODE|${MDERRORCODE}"
    echo "${TEXT}"
    exit 0
  fi
  MEMNOTFREED=;GOTERROR=;MARKEDASCRASHED=;MDERRORCODE=;
  # RV-27/08/22 If none of these issues was found present, then the script will continue and such continuations will always result in exit 1 as find_other_possible_issue_strings is a final attempt at returning a useful string if all other checks have already failed. It provides for several of the exit_code!=0 by mariadbd/mysyqld, previously reported as 'no core found' and similar, yet now covered.
}

# Check first if this is an ASAN/UBSAN/TSAN issue
SAN_BUG=0
if [ $(grep -m1 --binary-files=text "=ERROR:" ${ERROR_LOG} 2>/dev/null | wc -l) -ge 1 ]; then
  SAN_BUG=1
elif [ $(grep -im1 --binary-files=text "ThreadSanitizer:" ${ERROR_LOG} 2>/dev/null | wc -l) -ge 1 ]; then
  SAN_BUG=1
elif [ $(grep -im1 --binary-files=text "runtime error:" ${ERROR_LOG} 2>/dev/null | wc -l) -ge 1 ]; then
  SAN_BUG=1
elif [ $(grep -im1 --binary-files=text "LeakSanitizer:" ${ERROR_LOG} 2>/dev/null | wc -l) -ge 1 ]; then
  SAN_BUG=1
fi
if [ "${SAN_BUG}" -eq 1 ]; then
  TEXT="$(~/mariadb-qa/san_text_string.sh ${ERROR_LOG})"
  if [ "${SHOWINFO}" -eq 1 ]; then # Squirrel/process_testcases (to stderr)
    1>&2 echo "${SHOWTEXT}"
  fi
  echo "${TEXT}"
  exit 0
fi

# Note: all asserts below exclude any 'PREV' directories, like data.PREV
if [ -z "${LATEST_CORE}" ]; then
  if [ -f ${SCRIPT_PWD}/fallback_text_string.sh -a -r ${SCRIPT_PWD}/fallback_text_string.sh ]; then
    if [[ "${PWD}" != *"SAN"* ]]; then  # [*] When SAN is used, no cores are generated. As such, we don't want to produce a FALLBACK string here from the error log as they will be almost always dud's and there will be many of them (all the same issues which already have UniqueID's and are already logged etc.)
      if grep -qi 'signal' "${ERROR_LOG}"; then
        TEXT="$(${SCRIPT_PWD}/fallback_text_string.sh "${ERROR_LOG}")"
        if [ "${SHOWINFO}" -eq 1 ]; then # Squirrel/process_testcases (to stderr)
          1>&2 echo "${SHOWTEXT}"
        fi
        if [[ "${TEXT}" == *"No relevant strings were found"* ]]; then
        TEXT=
        fi
        if [ -z "${TEXT}" ]; then
          find_other_possible_issue_strings
          # If find_other_possible_issue_strings did not terminate the script with exit 0, it failed
          echo "Assert: no core file found in */*core*, and fallback_text_string.sh returned an empty output"
          exit 1
        else
          echo "${TEXT}"
          exit 0
        fi
      else
        if [ "${SHOWINFO}" -eq 1 ]; then # Squirrel/process_testcases (to stderr)
          1>&2 echo "${SHOWTEXT}"
        fi
        find_other_possible_issue_strings
        # If find_other_possible_issue_strings did not terminate the script with exit 0, it failed
        echo "Assert: no core file found in */*core*, and no 'signal' found in the error log, so fallback_text_string.sh was not attempted"
        exit 1
      fi
    else  # This is a SAN build, so do not run a FALLBACK string generation attempt, but do try find_other_possible_issue_strings
      if [ "${SHOWINFO}" -eq 1 ]; then # Squirrel/process_testcases (to stderr)
        1>&2 echo "${SHOWTEXT}"
      fi
      find_other_possible_issue_strings
      # If find_other_possible_issue_strings did not terminate the script with exit 0, it failed
      echo "Assert: no core file found in */*core*, and this is a SAN build, so fallback_text_string.sh was not attempted"  # See above for the reason [*]
      exit 1
    fi
  else  # FALLBACK string script not found (should not happen!)
    echo "Assert: no core file found in */*core*, and fallback_text_string.sh was not found, or is not readable"
    exit 1
  fi
fi

RANDOM=$(date +%s%N | cut -b10-19 | sed 's|^[0]\+||')  # Random entropy init
RANDF=$(echo $RANDOM$RANDOM$RANDOM$RANDOM | sed 's|.\(..........\).*|\1|')  # Random 10 digits filenr

rm -f /tmp/${RANDF}.gdb*
gdb -q ${MYSQLD} ${LATEST_CORE} >/tmp/${RANDF}.gdb1 2>&1 << EOF
  set pagination off
  set trace-commands off
  set frame-info short-location
  bt
  set print frame-arguments none
  set print repeats 0
  set print max-depth 0
  set print null-stop
  set print demangle on
  set print object off
  set print static-members off
  set print address off
  set print symbol-filename off
  set print symbol off
  set filename-display basename
  set print array off
  set print array-indexes off
  set print elements 1
  set logging file /tmp/${RANDF}.gdb2
  set logging on
  bt
  set logging off
  quit
EOF

# Cleanup (gdb) markers to allow frame #0 to be read
sed -i 's|^(gdb)[ ]*||' /tmp/${RANDF}.gdb2

touch /tmp/${RANDF}.gdb3
TEXT=

# Assertion catch
# Assumes (which is valid for the pquery framework) that 1st assertion is also the last in the log
ASSERT="$(grep --binary-files=text -om1 'Assertion.*failed.$' ${ERROR_LOG} | sed "s|\.$||;s|^Assertion [\`]||;s|['] failed$||" | head -n1)"
if [ -z "${ASSERT}" ]; then
  ASSERT="$(grep --binary-files=text -m1 'Failing assertion:' ${ERROR_LOG} | sed "s|.*Failing assertion:[ \t]*||" | head -n1)"
fi
if [ ! -z "${ASSERT}" ]; then
  TEXT="${ASSERT}"
fi

# Signal catch
if grep -E --binary-files=text -iq 'Program terminated with' /tmp/${RANDF}.gdb1; then
  # sed 's|^\([^,]\+\),.*$|\1|' in the next line removes ", Segmentation fault" if "SIGSEGV" is present before it (and similar for other signals)
  SIG="$(grep 'Program terminated with' /tmp/${RANDF}.gdb1 | grep --binary-files=text -o 'with signal.*' | sed 's|with signal ||;s|\.$||' | sed 's|^\([^,]\+\),.*$|\1|' | head -n1)"
  if [ -z "${TEXT}" ]; then TEXT="${SIG}"; else TEXT="${TEXT}|${SIG}"; fi
elif grep -E --binary-files=text -iq '(sig=[0-9]+)' /tmp/${RANDF}.gdb1; then
  SIG="$(grep -o --binary-files=text '(sig=[0-9]\+)' /tmp/${RANDF}.gdb1 | sed 's|(||;s|)||' | head -n1)"
  if [ -z "${TEXT}" ]; then TEXT="${SIG}"; else TEXT="${TEXT}|${SIG}"; fi
fi
rm -f /tmp/${RANDF}.gdb1

# Stack catch
IMPROVE_FLAG=''
FRAMES_FILTER='std::terminate.*from|__pthread_kill_.*|__GI___pthread_kill|__GI_raise |__GI_abort |__GI___assert_fail |__assert_fail_base |memmove|memcpy|\?\? \(\)|\(gdb\)|signal handler called|uw_update_context_1|uw_init_context_1|_Unwind_Resume|Warning: .set logging off|Use .set logging enabled'
grep --binary-files=text -A100 'signal handler called' /tmp/${RANDF}.gdb2 | grep --binary-files=text -vEi "${FRAMES_FILTER}" | sed 's|^#[0-9]\+[ \t]\+||' | sed 's|(.*) at ||;s|:[ 0-9]\+$||' > /tmp/${RANDF}.gdb4
if [ "$(wc -m /tmp/${RANDF}.gdb4 2>/dev/null | sed 's| .*||')" == "0" ]; then
  # 'signal handler called' was not found, try another method
  grep --binary-files=text -m1 -A100 '^#0' /tmp/${RANDF}.gdb2 | grep --binary-files=text -vEi "${FRAMES_FILTER}" | sed 's|^#[0-9]\+[ \t]\+||' | sed 's|(.*) at ||;s|:[ 0-9]\+$||' > /tmp/${RANDF}.gdb4
fi
if [ "$(wc -m /tmp/${RANDF}.gdb4 2>/dev/null | sed 's| .*||')" == "0" ]; then
  # '#0' was not found, which is unlikely to happen, but improvements may be possible, set flag
  IMPROVE_FLAG=' (may be improved upon)'
fi
rm -f /tmp/${RANDF}.gdb2

# Cleanup do_command and higher frames, provided sufficient frames will remain
DC_LINE="$(grep --binary-files=text -n '^do_command' /tmp/${RANDF}.gdb4)"
DC_CLEANED=0
if [ ! -z "${DC_LINE}" ]; then
  DC_LINE=$(echo ${DC_LINE} | grep --binary-files=text -o '^[0-9]\+')
  if [ ! -z "${DC_LINE}" ]; then
    # Reduce stack lenght if there are at least 5 descriptive frames
    if [ ${DC_LINE} -ge 5 ]; then
      grep --binary-files=text -B100 '^do_command' /tmp/${RANDF}.gdb4 | grep --binary-files=text -v '^do_command' > /tmp/${RANDF}.gdb3
      DC_CLEANED=1
    fi
  fi
fi
if [ ${DC_CLEANED} -eq 0 ]; then
  cat /tmp/${RANDF}.gdb4 > /tmp/${RANDF}.gdb3
fi
rm -f /tmp/${RANDF}.gdb4

# Grap first 4 frames, if they exist, and add to TEXT
FRAMES="$(cat /tmp/${RANDF}.gdb3 | head -n4 | sed 's| [^ ]\+$||;s|[ ]*(.*||' | tr '\n' '|' | sed 's/|$/\n/')"
rm -f /tmp/${RANDF}.gdb3
if [ ! -z "${FRAMES}" ]; then
  if [ ${FRAMESONLY} -eq 1 -o -z "${TEXT}" ]; then
    TEXT="${FRAMES}"
  else
    TEXT="${TEXT}|${FRAMES}"
  fi
else
  echo "Assert: No parsable frames?${IMPROVE_FLAG}"  # Add improve flag, which is almost always empty
  exit 1
fi

# Minor adjustments
TEXT="$(echo "${TEXT}" | sed 's|__cxa_pure_virtual () from|__cxa_pure_virtual|g')"

# Report bug identifier string
if [ "${SHOWINFO}" -eq 1 ]; then # Squirrel/process_testcases (to stderr)
  1>&2 echo "${SHOWTEXT}"
fi
if [ "$(echo "${TEXT}" | sed 's|[ \t]*\(.\).*|\1|')" == "#" ]; then
  echo "Assert: leading character of unique bug id (${TEXT}) is a '#', which will lead to issues in other scripts. This would normally never happen, but it did. Please improve new_text_string.sh to handle this situation!"
  exit 1
else
  echo "${TEXT}"
  exit 0
fi
