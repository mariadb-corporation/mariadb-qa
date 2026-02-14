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
if [ $(grep -m1 --binary-files=text -E "=ERROR:|ThreadSanitizer:|runtime error:|LeakSanitizer:|MemorySanitizer:" ./log/master.err ./log/slave.err 2>/dev/null | wc -l) -eq 0 ]; then  # If no such issue found (count is 0), sleep x seconds to allow core, if any, to finish writing
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
ERROR_LOGS=
MYSQLD=
TRIAL=
LOC=${PWD}

if [ $(df -k -P /tmp | grep -E --binary-files=text -v "Mounted" | awk '{print $4}') -lt 400000 ]; then
  echo 'Assert: /tmp does not have enough free space (400Mb free space required for temporary files and any ongoing programs). Terminating now.'
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
  elif [ -r ./log/mysqld.out ]; then  # Reducer
    POTENTIAL_MYSQLD="$(grep "ready for connections" ./log/mysqld.out | sed 's|: .*||;s|^.* ||' | head -n1)"
    if [ -r ${POTENTIAL_MYSQLD} ]; then
      MYSQLD="${POTENTIAL_MYSQLD}"
    fi
  elif [ -r ./log/master.err ]; then
    POTENTIAL_MYSQLD="$(grep "ready for connections" ./log/master.err | sed 's|: .*||;s|^.* ||' | head -n1)"
    if [ -r ${POTENTIAL_MYSQLD} ]; then
      MYSQLD="${POTENTIAL_MYSQLD}"
    fi
  elif [ -r ./log/slave.err ]; then
    POTENTIAL_MYSQLD="$(grep "ready for connections" ./log/slave.err | sed 's|: .*||;s|^.* ||' | head -n1)"
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
  elif [ -r ./node3/node3.err ]; then
    POTENTIAL_MYSQLD="$(grep "ready for connections" ./node3/node3.err | sed 's|: .*||;s|^.* ||' | head -n1)"
    if [ -f ${POTENTIAL_MYSQLD} -a -r ${POTENTIAL_MYSQLD} ]; then
      MYSQLD="${POTENTIAL_MYSQLD}"
    fi
  else
    echo "Assert: mariadbd/mysqld not found in ./bin/, nor ../, nor ../mysqld/ nor any other potential locations extracted from any logs at ./log/*.err or ./node[1-3]/node[1-3].err"
    exit 1
  fi
fi

if [ "${MDG}" != "1" ]; then
  if [ ! -z "$(ls --color=never ./node*/node*.err 2>/dev/null)" ]; then
    MDG=1
  fi
fi

if [[ ${MDG} -eq 1 ]]; then
  ERROR_LOGS=${GALERA_ERROR_LOG}
  LATEST_CORE=${GALERA_CORE_LOC}
  if [ -z "${ERROR_LOGS}" ]; then  # Interactive call from basedir
    if [ -r ${LOC}/node1/node1.err ]; then
      ERROR_LOGS="${LOC}/node1/node1.err"
    fi
    if [ -r ${LOC}/node2/node2.err ]; then
      ERROR_LOGS="${ERROR_LOGS} ${LOC}/node2/node2.err"
    fi
    if [ -r ${LOC}/node3/node3.err ]; then
      ERROR_LOGS="${ERROR_LOGS} ${LOC}/node3/node3.err"
    fi
    if [ -z "${ERROR_LOGS}" ]; then
      echo "Assert: no error log found for Galera run!"
      exit 1
    fi
  fi
  if [ -z "${LATEST_CORE}" ]; then  # Interactive call from basedir
    LATEST_CORE="$(ls -t --color=never ${LOC}/node*/*core* 2>/dev/null)"
  fi
else
  ERROR_LOGS=$(ls ${LOC}/log/master.err 2>/dev/null)
  if [ -r ${LOC}/log/slave.err ]; then
    ERROR_LOGS="${ERROR_LOGS} $(ls ${LOC}/log/slave.err 2>/dev/null)"  # Include slave log in scanning
  fi
  LATEST_CORE=$(ls -t ${LOC}/*/*core* 2>/dev/null | grep -v 'data.PREV' | head -n1)  # Exclude data.PREV
  if [ -z "${LATEST_CORE}" ]; then  # Attempt MTR core location 1/3 (this may have been an MTR run)
    LATEST_CORE=$(ls -t ${LOC}/var/log/*/mysqld*/data*/*core* 2>/dev/null | head -n1)
  fi
  if [ -z "${LATEST_CORE}" ]; then  # Attempt MTR core location 2/3 (this may have been an MTR run)  # Replication, with --parallel
    LATEST_CORE=$(ls -t ${LOC}/var/*/log/*/mysqld*/data*/*core* 2>/dev/null | head -n1)
  fi
  if [ -z "${LATEST_CORE}" ]; then  # Attempt MTR core location 2/3 (this may have been an MTR run)  # Replication MTR testcases seems to use ./var/mysqld.nr/data/core.* instead, or may be due to older version?
    LATEST_CORE=$(ls -t ${LOC}/var/mysqld*/data*/*core* 2>/dev/null | head -n1)
  fi
fi

if [ -z "${ERROR_LOGS}" ]; then
  if [ -r "../../mysqld.1.err" ]; then
    ERROR_LOGS="../../mysqld.1.err"
  fi
  if [ -r "../../mysqld.2.err" ]; then
    ERROR_LOGS="${ERROR_LOGS} ../../mysqld.2.err"
  fi
  if [ -r "./var/log/mysqld.1.err" ]; then  # For MTR, default ./mtr test runs (e.g. testcase in main/test.test)
    ERROR_LOGS="${ERROR_LOGS} ./var/log/mysqld.1.err"
  fi
  if [ -r "./var/log/mysqld.2.err" ]; then  # For MTR, default ./mtr test runs (e.g. testcase in main/test.test)
    ERROR_LOGS="${ERROR_LOGS} ./var/log/mysqld.2.err"
  fi
  if [ -r "./var/log/mysqld.3.1.err" ]; then  # For MTR Spider (and other) test runs (may not be correct one)
    ERROR_LOGS="${ERROR_LOGS} ./var/log/mysqld.3.1.err"
  fi
  if [ -r "./var/log/mysqld.2.1.err" ]; then  # For MTR Spider (and other) test runs (may not be correct one)
    ERROR_LOGS="${ERROR_LOGS} ./var/log/mysqld.2.1.err"
  fi
  if [ -r "./var/log/mysqld.1.1.err" ]; then  # For MTR Spider (and other) test runs (may not be correct one)
    ERROR_LOGS="${ERROR_LOGS} ./var/log/mysqld.1.1.err"
  fi
  if [ -r "../../mysqld.2.err" ]; then
    ERROR_LOGS="${ERROR_LOGS} ../../mysqld.2.err"
  fi
  if [ -r "../../mysqld.2.err" ]; then
    ERROR_LOGS="${ERROR_LOGS} ../../mysqld.2.err"
  fi
  if [ -r "./var/log/mysqld.2.err" ]; then  # For MTR, default ./mtr test runs (e.g. testcase in main/test.test)
    ERROR_LOGS="${ERROR_LOGS} ./var/log/mysqld.2.err"
  fi
  if [ -r "./var/log/mysqld.2.err" ]; then  # For MTR, default ./mtr test runs (e.g. testcase in main/test.test)
    ERROR_LOGS="${ERROR_LOGS} ./var/log/mysqld.2.err"
  fi
  if [ -r "./var/log/mysqld.3.1.err" ]; then  # For MTR Spider (and other) test runs (may not be correct one)
    ERROR_LOGS="${ERROR_LOGS} ./var/log/mysqld.3.1.err"
  fi
  if [ -r "./var/log/mysqld.2.1.err" ]; then  # For MTR Spider (and other) test runs (may not be correct one)
    ERROR_LOGS="${ERROR_LOGS} ./var/log/mysqld.2.1.err"
  fi
  if [ -r "./var/log/mysqld.2.1.err" ]; then  # For MTR Spider (and other) test runs (may not be correct one)
    ERROR_LOGS="${ERROR_LOGS} ./var/log/mysqld.2.1.err"
  fi
  if [ -r "./log/mysqld.out" ]; then  # Reducer
    ERROR_LOGS="${ERROR_LOGS} ./log/mysqld.out"
  fi
  if [ -z "${ERROR_LOGS}" ]; then
    ERROR_LOGS="$(ls ./var/*/log/mysqld.[12].err 2>/dev/null | tr '\n' ' ')"  # MTR, replication, with --parallel
  fi
fi

if [ -z "${ERROR_LOGS}" ]; then
  echo "Assert: no error log(s) found - exiting"
  exit 1
else
  ERROR_LOGS="$(echo "${ERROR_LOGS}" | tr ' ' '\n' | sort -u | tr '\n' ' ')"  # Avoid duplicates
fi

# Match the MTR error log used with the m/s core used, if/when mismatched (for example when both m+s crash and one dir is deleted to debug the other with 'tt' etc.)
# This (if) code is similar to the code in stack.sh but here we scan all error logs (i.e. ERROR_LOGS instead of ERROR_LOG). As we already have a core in mysqld.1 or mysqld.2 we can safely change all instances of mysqld.2 or mysqld.1 to mysqld.1 and mysqld.2 respectively (i.e. |g)
if [[ "${LATEST_CORE}" == *"mysqld.1"* ]]; then
  ERROR_LOGS="$(echo "${ERROR_LOGS}" | sed 's|mysqld.2|mysqld.1|g')"
elif [[ "${LATEST_CORE}" == *"mysqld.2"* ]]; then
  ERROR_LOGS="$(echo "${ERROR_LOGS}" | sed 's|mysqld.1|mysqld.2|g')"
fi
# Idem for non-MTR runs, i.e. standard BASEDIR 'str' runs
if [[ "${LATEST_CORE}" == *"data_slave"* ]]; then
  ERROR_LOGS="$(echo "${ERROR_LOGS}" | sed 's|master.err|slave.err|g')"
elif [[ "${LATEST_CORE}" == *"data/core"* ]]; then
  ERROR_LOGS="$(echo "${ERROR_LOGS}" | sed 's|slave.err|master.err|g')"
fi
#echo "DEBUG: errs: ${ERROR_LOGS} | core: ${LATEST_CORE}"
# TODO: MDG needs similar code for node1/2/3

# Disabled when ERROR_LOG was changed to ERROR_LOGS (multi-scanning for issues in all applicable error logs)
#if [ ! -r "${ERROR_LOG}" ]; then
#  echo "Assert: ${ERROR_LOG} set but not readable (this should not happen!)"
#  exit 1
#fi

# When adding additional items to find_other_possible_issue_strings(), please also add them to reducer.sh, serach for 'Likely misconfiguration' in there
find_other_possible_issue_strings(){
  # If all else failed, check if there are other interesting issues
  # TODO, over time, it may make sense to rotate the issues below in to a different order. The benefit of this is increased
  # coverage of issues which may appear together in a single trial, thereby maskign the other etc. Then again, may it not
  # "mess us" UniqueID coverage in known bugs strings? Likely not, but needs some additional consideration
  # sed 's|: [0-9]\+||': Remove the number of of bytes, as often this significantly increases reproducibility of the SQL
  WRONGMUTEXUSAGE="$(grep -hio "safe_mutex: Found wrong usage of mutex .* and .*" ${ERROR_LOGS} 2>/dev/null | head -n1 | tr -d '\n' | sed 's|"||g' | sed "s|'||g")"
  if [ ! -z "${WRONGMUTEXUSAGE}" ]; then
    TEXT="MUTEX_ERROR|${WRONGMUTEXUSAGE}"  # Found wrong usage of mutex
    echo "${TEXT}"
    exit 0
  else
    WRONGMUTEXUSAGE="$(grep -hio 'safe_mutex: .*' ${ERROR_LOGS} 2>/dev/null | head -n1 | sed 's|, line.*||;s|/test/[^/]\+/||')"
    if [ ! -z "${WRONGMUTEXUSAGE}" ]; then
      TEXT="MUTEX_ERROR|${WRONGMUTEXUSAGE}"  # For example, 'Trying to lock uninitialized mutex...'
      echo "${TEXT}"
      exit 0
    fi
  fi
  WRONGMUTEXUSAGE=
  OPENTABLE="$(grep -hio "OpenTable:.*" ${ERROR_LOGS} 2>/dev/null | head -n1 | tr -d '\n' | sed 's|"||g' | sed "s|'||g")"
  if [ ! -z "${OPENTABLE}" ]; then
    TEXT="OPENTABLE|${OPENTABLE}"  # Found 'OpenTable' bug
    echo "${TEXT}"
    exit 0
  fi
  OPENTABLE=
  GOT_FATAL_ERROR="$(grep -hio 'Got fatal error [0-9]\+' ${ERROR_LOGS} 2>/dev/null | head -n1 | tr -d '\n')"
  if [ ! -z "${GOT_FATAL_ERROR}" ]; then
    TEXT="GOT_FATAL_ERROR|${GOT_FATAL_ERROR}"
    echo "${TEXT}"
    exit 0
  fi
  GOT_FATAL_ERROR=
  MEMNOTFREED="$(grep -hi 'Warning: Memory not freed' ${ERROR_LOGS} 2>/dev/null | head -n1 | sed 's|: [0-9]\+||' | tr -d '\n')"
  if [ ! -z "${MEMNOTFREED}" ]; then
    TEXT="GENERIC_ISSUE-DO_NOT_ADD_TO_KB_OR_KBA|MEMORY_NOT_FREED|${MEMNOTFREED}"
    echo "${TEXT}"
    exit 0
  fi
  MEMNOTFREED=
  GOTERROR="$(grep -hio 'mysqld: Got error[^"]\+"[^"]\+"' ${ERROR_LOGS} 2>/dev/null | head -n1 | tr -d '\n' | sed 's|"||g' | sed "s|'||g" | grep -io 'Got error [0-9]\+[^\.]\+' | sed 's/Got error \([0-9]\+\)[ ]*/Got error \1|/i' | sed 's|/dev/shm/.*sql-temptable.*MAI|.*sql-temptable.*MAI|' | sed 's|/[dt][ae][ts][at]/.*sql-temptable.*MAI|.*sql-temptable.*MAI|')"
  if [ ! -z "${GOTERROR}" ]; then
    TEXT="GOT_ERROR|${GOTERROR}"
    echo "${TEXT}"
    exit 0
  else
    GOTERROR="$(grep -hio 'Got error.*' ${ERROR_LOGS} 2>/dev/null | head -n1 | sed "s|when reading table '.*|when reading table|" | sed 's/Got error \([0-9]\+\)[ ]*/Got error \1|/i' | sed 's|/dev/shm/.*sql-temptable.*MAI|.*sql-temptable.*MAI|' | sed 's|/[dt][ae][ts][at]/.*sql-temptable.*MAI|.*sql-temptable.*MAI|')"
    if [ ! -z "${GOTERROR}" ]; then
      TEXT="GOT_ERROR|${GOTERROR}"
      TEXT="$(echo "${TEXT}" | sed "s|marked as crashed and should be repaired\"' for .*|marked as crashed and should be repaired\" for 'X'|")"  # Use a generic indentifier 'X' for any table name, similar to X/Y value handling in *SAN bugs
      echo "${TEXT}"
      exit 0
    fi
  fi
  GOTERROR=
  MARKEDASCRASHED="$(grep -hio 'mysqld: Table.*is marked as crashed and should be repaired' ${ERROR_LOGS} 2>/dev/null | head -n1 | tr -d '\n' | sed 's|"||g' | sed "s|'||g" | sed 's|Table /[^#]\+#sql-temptable[^ ]\+ |Table sql-temptable-X |')"
  if [ ! -z "${MARKEDASCRASHED}" ]; then
    TEXT="MARKED_AS_CRASHED|${MARKEDASCRASHED}"
    echo "${TEXT}"
    exit 0
  fi
  MARKEDASCRASHED=
  INNODBERROR="$(grep -hio 'ERROR. InnoDB.*' ${ERROR_LOGS} 2>/dev/null | head -n1 | tr -d '\n' | sed 's|"||g' | sed "s|'||g" | sed 's|ERROR. InnoDB[: ]*||' | sed 's|table.*index.*stat[^:]\+|table.*index.*stat.*|;s|User stopword table.*does not exist|User stopword table does not exist|;s|\.$||')"
  if [ ! -z "${INNODBERROR}" ]; then
    TEXT="INNODB_ERROR|${INNODBERROR}"
    TEXT="$(echo "${TEXT}" | sed 's|Cannot rename.*to.*because the target schema directory doesnt exist|Cannot rename.*to.*because the target schema directory doesnt exist|')"  # https://jira.mariadb.org/browse/MDEV-27952?focusedCommentId=283382&page=com.atlassian.jira.plugin.system.issuetabpanels:comment-tabpanel#comment-283382
    TEXT="$(echo "${TEXT}" | sed 's|Record in index.*of table.*was not found on update: TUPLE.*at: COMPACT RECORD.*|Record in index.*of table.*was not found on update: TUPLE.*at: COMPACT RECORD|')"  # MDEV-35187
    TEXT="$(echo "${TEXT}" | sed 's|for table [^ ]\+|for table|g')"  # MDEV-34951
    TEXT="$(echo "${TEXT}" | sed 's|The table [^ ]\+ doesnt have|The table doesnt have|g')"  # SPECIAL-33
    TEXT="$(echo "${TEXT}" | sed 's|Unable to import tablespace .* because it already exists.  Please DISCARD the tablespace before IMPORT|Unable to import tablespace X because it already exists.  Please DISCARD the tablespace before IMPORT|')"  # Use a generic indentifier 'X' for any table name, similar to X/Y value handling in *SAN bugs
    TEXT="$(echo "${TEXT}" | sed 's|Cannot add field.*in table.*because after adding it, the row size is.*which is greater than maximum allowed size.*for a record on index leaf page|Cannot add field in table because after adding it, the row size is greater than the maximum allowed size for a record on index leaf page|')"  # Use a generic message for all similar errors
    TEXT="$(echo "${TEXT}" | sed 's|Failed to read page [0-9]\+ from file [^:]\+:|Failed to read page X from file Y:|')"
    echo "${TEXT}"
    exit 0
  fi
  INNODBERROR=
  MDERRORCODE="$(grep -hio 'MariaDB error code: [0-9]\+' ${ERROR_LOGS} 2>/dev/null | head -n1 | tr -d '\n')"
  if [ ! -z "${MDERRORCODE}" ]; then
    TEXT="MARIADB_ERROR_CODE|${MDERRORCODE}"
    echo "${TEXT}"
    exit 0
  fi
  MDERRORCODE=
  MDBDERROR="$(grep -hio 'ERROR] mariadbd: .*' ${ERROR_LOGS} 2>/dev/null | head -n1 | tr -d '\n' | sed "s|^ERROR] ||;s|'t[0-9]*'|table|")"
  if [ ! -z "${MDBDERROR}" ]; then
    TEXT="$(echo "${MDBDERROR}" | sed "s|Incorrect information in file: '[^']*.frm'|Incorrect information in frm file|")"  # Fix to remove any table name/path, specifically for .frm issues, ref MDEV-28498 and MDEV-27771
    TEXT="$(echo "${TEXT}" | sed "s|writing file '[^']*' |writing file |")"  # Fix things like Error writing file 'qa-roel-2-bin' by making it generic
    TEXT="MARIADBD_ERROR|${TEXT}"
    echo "${TEXT}"
    exit 0
  fi
  MDBDERROR=
  SERVER_ERRNO="$(grep -hio 'server_errno: [0-9]\+' ${ERROR_LOGS} 2>/dev/null | head -n1 | tr -d '\n')"
  if [ ! -z "${SERVER_ERRNO}" ]; then
    TEXT="SERVER_ERRNO|${SERVER_ERRNO}"
    echo "${TEXT}"
    exit 0
  fi
  SERVER_ERRNO=
  SLAVE_ERROR="$(grep -hio 'ERROR.*Slave[^:]*:[^0-9]*[Ee]rror[: 0-9]\+' ${ERROR_LOGS} 2>/dev/null | sed 's|ERROR[] ]*||' | head -n1 | tr -d '\n')"
  if [ ! -z "${SLAVE_ERROR}" ]; then
    TEXT="SLAVE_ERROR|${SLAVE_ERROR}"
    echo "${TEXT}"
    exit 0
  fi
  SLAVE_ERROR=
  SLAVE_ERROR2="$(grep -hio 'ERROR.*Slave[^:]*:[^0-9]*[Ee]rror_code[: 0-9]\+' ${ERROR_LOGS} 2>/dev/null | sed 's|ERROR[] ]*||' | head -n1 | tr -d '\n')"
  if [ ! -z "${SLAVE_ERROR2}" ]; then
    TEXT="SLAVE_ERROR|${SLAVE_ERROR2}"
    echo "${TEXT}"
    exit 0
  fi
  SLAVE_ERROR2=
  # RV-27/08/22 If none of these issues was found present, then the script will continue and such continuations will always result in exit 1 as find_other_possible_issue_strings is a final attempt at returning a useful string if all other checks have already failed. It provides for several of the exit_code!=0 by mariadbd/mysyqld, previously reported as 'no core found' and similar, yet now covered.
}

# Check first if this is an ASAN/UBSAN/TSAN/MSAN issue. If so, this was a *SAN run and thus all bugs should first be handled/classified by san_text_string.sh rather than this script. Note that any normal crashing/asserting bug, which does not also generate a *SAN issue/bug, will also crash the *SAN build but the strings below will not be present and thus it will still be handled by this script. Therefore, *SAN runs may be better in general, however a number of crashes/asserts will be masked as a fair number of general crashing/asserting bugs are preceded by *SAN findings. In summary, best to run both normal runs as well as *SAN runs. UB+ASAN can be combined. UB+MSAN can be comined. TSAN cannot be combined.
SAN_BUG=0
if [ $(grep -m1 --binary-files=text "=ERROR:" ${ERROR_LOGS} 2>/dev/null | wc -l) -ge 1 ]; then
  SAN_BUG=1
elif [ $(grep -im1 --binary-files=text "ThreadSanitizer:" ${ERROR_LOGS} 2>/dev/null | wc -l) -ge 1 ]; then
  SAN_BUG=1
elif [ $(grep -im1 --binary-files=text "runtime error:" ${ERROR_LOGS} 2>/dev/null | wc -l) -ge 1 ]; then
  SAN_BUG=1
elif [ $(grep -im1 --binary-files=text "LeakSanitizer:" ${ERROR_LOGS} 2>/dev/null | wc -l) -ge 1 ]; then
  SAN_BUG=1
elif [ $(grep -im1 --binary-files=text "MemorySanitizer:" ${ERROR_LOGS} 2>/dev/null | wc -l) -ge 1 ]; then
  SAN_BUG=1
fi
if [ "${SAN_BUG}" -eq 1 ]; then
  if [ ! -r ${HOME}/mariadb-qa/san_text_string.sh ]; then
    echo "Assert: ${HOME}/mariadb-qa/san_text_string.sh not available, you may want to clone mariadb-qa. Terminating"
    exit 1
  fi
  TEXT="$(${HOME}/mariadb-qa/san_text_string.sh "${ERROR_LOGS}")"  # Ensure the double quotes in "${ERROR_LOGS}" are present so ${1} is all logs, rather than ${1} being the first log only
  if [ "${SHOWINFO}" -eq 1 ]; then # Squirrel/process_testcases (to stderr)
    1>&2 echo "${SHOWTEXT}"
  fi
  echo "${TEXT}"
  exit 0
fi

if [ -z "${LATEST_CORE}" ]; then
  if [ "${SHOWINFO}" -eq 1 ]; then # Squirrel/process_testcases (to stderr)
    1>&2 echo "${SHOWTEXT}"
  fi
  find_other_possible_issue_strings
  # If find_other_possible_issue_strings did not terminate the script with exit 0, it failed to find a string of interest
  if [ -f ${SCRIPT_PWD}/fallback_text_string.sh -a -r ${SCRIPT_PWD}/fallback_text_string.sh ]; then
    if [[ "${PWD}" != *"SAN"* ]]; then  # [*] When SAN is used, no cores are generated. As such, we don't want to produce a fallback_text_string.sh string here (from the error log) as they will be almost always dud's and there will be many of them (all the same issues which already have UniqueID's and are already logged etc.)
      COUNT_NR_OF_ERROR_LOGS="$(echo "${ERROR_LOGS}" | tr ' ' '\n' | wc -l)"
      for((i=0;i<${COUNT_NR_OF_ERROR_LOGS};i++)){
        # echo "${ERROR_LOGS}" | tr ' ' '\n' | head -n${i} | tail -n1  # debug to see what logs are scanned
        TEXT="$(${SCRIPT_PWD}/fallback_text_string.sh "$(echo "${ERROR_LOGS}" | tr ' ' '\n' | head -n${i} | tail -n1)" 2>&1 | grep -v 'No relevant strings were found in')"  # Try FTS, one log at the time. Note: spaces in the path may break this, but with a standard server setup (i.e. ~/mariadb-qa, /test, /data and /dev/shm, this should never happen as every path used is without spaces). fallback_text_string.sh was never made multi-error-log aware, the ROI is too low
        if [ ! -z "${TEXT}" ]; then
          if [[ "${TEXT}" != *"Assert"* ]]; then
            echo "${TEXT}"
            exit 0
          fi
        fi
      }
      echo "Assert: no core file found in */*core*, and fallback_text_string.sh returned an empty output for all logs"
      exit 1
    else  # This is a SAN build, so do not run a FALLBACK string generation attempt, but do try find_other_possible_issue_strings
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
  set logging enabled on
  bt
  set logging enabled off
  quit
EOF

# Cleanup (gdb) markers to allow frame #0 to be read
sed -i 's|^(gdb)[ ]*||' /tmp/${RANDF}.gdb2

touch /tmp/${RANDF}.gdb3
TEXT=

# Assertion catch
# Assumes (which is valid for the pquery framework) that 1st assertion is also the last in the log
ASSERT="$(grep --binary-files=text -ohm1 'Assertion.*failed.$' ${ERROR_LOGS} 2>/dev/null | sed "s|\.$||;s|^Assertion [\`]||;s|['] failed$||" | head -n1)"
if [ -z "${ASSERT}" ]; then
  ASSERT="$(grep --binary-files=text -hm1 'Failing assertion:' ${ERROR_LOGS} 2>/dev/null | sed "s|.*Failing assertion:[ \t]*||" | head -n1)"
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
FRAMES_FILTER='__interceptor_strcmp.part.0|std::terminate.*from|fprintf|__pthread_kill_.*|__GI___pthread_kill|__GI_raise |__GI_abort |__assert_fail|memmove|memcpy|\?\? \(\)|\(gdb\)|signal handler called|uw_update_context_1|uw_init_context_1|_Unwind_Resume|Warning: .set logging enabled off|Use .set logging enabled'
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
TEXT="$(echo "${TEXT}" | sed 's|"/test/[^/"]\+[/"]|"|')"  # To cleanup, for example: inline_mysql_file_tell("/test/bb-11.4-MDEV-7850_dbg/mysys/mf_iocache2.c"
TEXT="$(echo "${TEXT}" | sed 's/^SIGABRT|Backtrace stopped: Cannot access memory at address|$/GENERIC_MEMORY_CORRUPTION_ISSUE|DO_NOT_ADD_TO_KNOWN_BUGS|SIGABRT|Backtrace stopped: Cannot access memory at address|/g')"  # Do not log this UniqueID to kb

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
