#!/bin/bash
# Created by Roel Van de Paar, Percona LLC
# Updated by Roel Van de Paar, MariaDB
# Updated by Ramesh Sivaraman, MariaDB
set +H

# The name of this script (pquery-prep-red.sh) was kept short so as to not clog directory listings - it's full name would be ./pquery-prepare-reducer.sh

# To aid with correct bug to testcase generation for pquery trials, this script creates a local run script for reducer and sets #VARMOD#.
# This handles crashes/asserts/Valgrind issues for the moment only. Could be expanded later for other cases, and to handle more unforseen situations.
# Query correctness: data (output) correctness (QC DC) trial handling was also added 11 May 2016

# Improvement ideas
# - It would be better if failing queries were added like this; 3x{query_from_err_log,query_from_core},3{SELECT 1},3{SELECT SLEEP(3)} instead of 3{query_from_core},3{query_from_err_log},3{SELECT 1},3{SELECT SLEEP(3)}

# User configurable variables
VALGRIND_OVERRIDE=0    # If set to 1, Valgrind issues are handled as if they were a crash (core dump required)
SCAN_FOR_NEW_BUGS=1    # If set to 1, all generated reducders will scan for new issues while reducing!

# Internal variables
SCRIPT_PWD=$(dirname $(readlink -f "${0}"))
if [ "${SCRIPT_PWD}" == "${HOME}" -a -r "${HOME}/mariadb-qa/new_text_string.sh" ]; then  # Provision for symlinks (if needed) 
  SCRIPT_PWD="${HOME}/mariadb-qa"
fi
RUNDIR=$PWD
REDUCER="${SCRIPT_PWD}/reducer.sh"
SAN_BUG=0  # Do not remove

# Disable history substitution and avoid  -bash: !: event not found  like errors
set +H

check_if_asan_or_ubsan_or_tsan(){
  SAN_BUG=0
  if [[ "${TEXT}" == *"Assert: no core file found in"* ]]; then
    if [ $(grep -m1 --binary-files=text "=ERROR:" ./${TRIAL}/log/master.err ${TRIAL}/node${1}/node${1}.err 2>/dev/null | wc -l) -ge 1 ]; then
      echo "* ASAN bug found!"
      SAN_BUG=1
    elif [ $(grep -im1 --binary-files=text "ThreadSanitizer:" ./${TRIAL}/log/master.err ${TRIAL}/node${1}/node${1}.err 2>/dev/null | wc -l) -ge 1 ]; then
      echo "* TSAN bug found!"
      SAN_BUG=1
    elif [ $(grep -im1 --binary-files=text "runtime error:" ./${TRIAL}/log/master.err ${TRIAL}/node${1}/node${1}.err 2>/dev/null | wc -l) -ge 1 ]; then
      echo "* UBSAN bug found!"
      SAN_BUG=1
    elif [ $(grep -m1 --binary-files=text "LeakSanitizer:" ./${TRIAL}/log/master.err ${TRIAL}/node${1}/node${1}.err 2>/dev/null | wc -l) -ge 1 ]; then
      echo "* LSAN bug found!"
      SAN_BUG=1
    elif [ $(grep -m1 --binary-files=text "MemorySanitizer:" ./${TRIAL}/log/master.err ${TRIAL}/node${1}/node${1}.err 2>/dev/null | wc -l) -ge 1 ]; then
      echo "* MSAN bug found!"
      SAN_BUG=1
    fi
  fi
  if [ "${SAN_BUG}" -eq 1 ]; then
    if [ -r "./${TRIAL}/node${1}/node${1}.err" ]; then
      TEXT="$(~/mariadb-qa/san_text_string.sh ./${TRIAL}/node${1}/node${1}.err)"
    elif [ -r "./${TRIAL}/log/master.err" ]; then
      TEXT="$(~/mariadb-qa/san_text_string.sh ./${TRIAL}/log/master.err)"
    else
      TEXT=
      echo "Assert: SAN_BUG=1 yet neither ./${TRIAL}/log/master.err nor ./${TRIAL}/node${1}/node${1}.err was found"
      exit 1
    fi
  fi
}

# Sanity checks
if [ ! -r ${SCRIPT_PWD}/new_text_string.sh ]; then
  echo "Assert: ${SCRIPT_PWD}/new_text_string.sh not readable by this script!"
  exit 1
elif [ ! -r ${SCRIPT_PWD}/reducer.sh ]; then
  echo "Assert: ${SCRIPT_PWD}/reducer.sh not readable by this script!"
  exit 1
elif [ ${SCAN_FOR_NEW_BUGS} -eq 1 -a ! -r ${SCRIPT_PWD}/known_bugs.strings ]; then
  echo "Assert: SCAN_FOR_NEW_BUGS=1, yet ${SCRIPT_PWD}/known_bugs.strings was not found?"
  exit 1
fi

# Check if Data at rest encryption was enabled for the run
if [ "$(grep --binary-files=text 'MDG Encryption run:' ./pquery-run.log 2> /dev/null | sed 's|^.*MDG Encryption run[: \t]*||' )" == "YES" ]; then
  export ENCRYPTION_RUN=1
else
  export ENCRYPTION_RUN=0
fi

# Check if RR Tracing was enabled for the run
if [ "$(grep --binary-files=text 'RR Tracing enabled:' ./pquery-run.log 2> /dev/null | sed 's|^.*RR Tracing enabled[: \t]*||' )" == "YES" ]; then
  export RR_TRACING=1
else
  export RR_TRACING=0
fi

# Check if this is a MDG run
if [ "$(grep --binary-files=text 'MDG Mode:' ./pquery-run.log 2> /dev/null | sed 's|^.*MDG Mode[: \t]*||' )" == "TRUE" ]; then
  export MDG=1
  NR_OF_NODES=$(grep --binary-files=text 'Number of Galera Cluster nodes:' ./pquery-run.log 2> /dev/null | sed 's|^.*Number of Galera Cluster nodes[: \t]*||')
else
  export MDG=0
  NR_OF_NODES=0
fi

# Check if this is a group replication run
if [ "$(grep --binary-files=text 'Group Replication Mode:' ./pquery-run.log 2> /dev/null | sed 's|^.*Group Replication Mode[: \t]*||')" == "TRUE" ]; then
  GRP_RPL=1
else
  GRP_RPL=0
fi

# Check if this an automated (pquery-reach.sh) run
if [ "$1" == "reach" ]; then
  REACH=1  # Minimal output, and no 2x enter required
else
  REACH=0  # Normal output
fi

# Check if this is a query correctness run
QC=0
if [ $(ls */*.out */*.sql 2>/dev/null | egrep --binary-files=text -oi "innodb|rocksdb|tokudb|myisam|memory|csv|ndb|merge|aria|sequence|mrg_myisam" | wc -l) -gt 0 ]; then
  if [ "$1" != "noqc" ]; then  # Even though query correctness trials were found, process this run as a crash/assert run only
    QC=1
  fi
fi

# Current location checks
if [ `ls */*thread-[1-9]*.sql 2>/dev/null | wc -l` -gt 0 ]; then
  echo -e "** FYI ** Multi-threaded trials (./*/*thread-[1-9]*.sql) were detected. For multi-threaded trials, now the 'total sql' file containing all executed queries (as randomly generated by pquery-run.sh prior to pquery's execution) is used. Reducer scripts will be generated as per normal (with the relevant multi-threaded options already set), and they will be pointed to these (i.e. one file per trial) SQL testcases. Failing sql from the SQL traces, coredump and the error log, as well as the usual trigger queries, will be auto-added (interleaved multiple times) to ensure better reproducibility. A new feature has also been added to reducer.sh, allowing it to reduce multi-threaded testcases multi-threadely using pquery --threads=x, each time with a reduced original (and still random) sql file. If the bug reproduces, the testcase is reduced further and so on. This will thus still end up with a very small testcase, which can be then used in combination with pquery --threads=x.\n"
  MULTI=1
fi
if [ ${QC} -eq 0 ]; then
  if [ `ls */*thread-0.sql 2>/dev/null | wc -l` -eq 0 ]; then
    echo "Assert: there were 0 pquery sql files found (./*/*thread-0.sql) in subdirectories of the current directory. Terminating."
    exit 1
  fi
else
  echo "Query correctness trials found! Only processing query correctness results. To process crashes/asserts pass 'noqc' as the first option to this script (pquery-prep-red.sh noqc)"
fi

WSREP_OPTION_CHECK=0
if [ `ls */WSREP_PROVIDER_OPT* 2>/dev/null | wc -l` -gt 0 ];then
  WSREP_OPTION_CHECK=1
  WSREP_PROVIDER_OPTIONS=
fi

MYEXTRA=             # Note that MYEXTRA as obtained from any trial's MYEXTRA file (i.e. ./{trialnr}/MYEXTRA) - ref below - includes MYSAFE but not MYINIT, which is read in separately from a ./{trialnr}/MYINIT file. MYINIT cannot be joined to MYEXTRA as MYEXTRA cannot be passed in full to mysqld --initialize as that may cause mysqld initialization to fail
VALGRIND_CHECK=0

if [ `ls ./*/MYEXTRA* 2>/dev/null | wc -l` -eq 0 ]; then
  echo "Assert: No MYEXTRA files for trials (./*/MYEXTRA*) were found. This should not be the case. Please check what is wrong."
  exit 1
fi

#Check MS/PS pquery binary
#PQUERY_BIN="`grep --binary-files=text 'pquery Binary' ./pquery-run.log | sed 's|^.*pquery Binary[: \t]*||' | head -n1`"    # < swap back to this one once old runs are gone (upd: maybe not. Issues.)
if [ -r *pquery*.conf* ]; then
  SEARCH_STR_BIN="*pquery*.conf*"
else
  SEARCH_STR_BIN="*pquery*.sh"  # For backward compatibility. Remove October 2017 or later.
fi
PQUERY_BIN=$(echo "$(grep --binary-files=text -ihm1 "^[ \t]*PQUERY_BIN=" ${SEARCH_STR_BIN} | sed 's|[ \t]*#.*$||;s|PQUERY_BIN=||')" | sed "s|\${SCRIPT_PWD}|${SCRIPT_PWD}|" | head -n1)
echo "pquery binary used: ${PQUERY_BIN}"

if [ "${PQUERY_BIN}" == "" ]; then
  echo "Assert! pquery binary used could not be auto-determined. Check script around \$PQUERY_BIN initialization."
  exit 1
fi

check_if_startup_failure(){  # This function may not be 100% compatible with multi-threaded (MULTI=1) yet (though an attempt was made with the [0-9] regex, ref the MULTI one above which has [1-9] but here we're checking for any startup failure and that would only happen if startup_failure_thread-0.sql is present. Then again, pquery-run.sh may not rename a file correctly to something like startup_failure_thread-{threadnr}.sql - to be verified also. < some TODO's. This function works fine for single thread runs. Multi-thread runs untested. May or may not work as described. Feel free to improve and then remove this note.
  STARTUP_ISSUE=0
  echo "* Checking if this trial had a mysqld startup failure"
  if [ `ls ${TRIAL}/*startup_failure_thread-[0-9]*.sql 2>/dev/null | wc -l` -gt 0 ]; then
    echo "  > This trial had a mysqld startup failure, the trial's reducer will be set to reduce as such (using REDUCE_STARTUP_ISSUES=1)"
    STARTUP_ISSUE=1
  else
    echo "  > This trial did not have a mysqld startup failure"
  fi
}

remove_non_sql_from_trace(){
  if [ -z "${1}" ]; then echo "Assert: remove_non_sql_from_trace called without option!"; exit 1; fi
  if [[ "${1}" != *"quick"* ]]; then
    echo "* Removing any non-SQL lines (diagnostic output from pquery) to improve issue reproducibility"
  fi
  mv ${1} ${1}.filter1
  egrep --binary-files=text -v "Last [0-9]+ consecutive queries all failed" ${1}.filter1 > ${1}
  rm ${1}.filter1
}

add_failing_and_trigger_queries_to_trace(){  # Improve issue reproducibility by adding failing/trigger queries to the SQL trace
  if [ "${1}" != "NOREGEN" ]; then  # Normal operation -or- first call (i.e. without NOREGEN)
    echo "* Obtaining failing and helpful issue trigger SQL queries using pquery-failing-sql.sh"
    # Note that pquery-failing-sql.sh deletes ${RUNDIR}/${TRIAL}/${TRIAL}.sql.failing before [re-]creating it
    ${SCRIPT_PWD}/pquery-failing-sql.sh ${TRIAL} 1
  else  # NOREGEN is used when the failing/trigger queries were already obtained using pquery-failing-sql.sh, when generating the MULTI=1 quick_${TRIAL}.sql files
    echo "* Re-using previously obtained failing and helpful trigger SQL queries for the multi-threaded quick SQL trace"
  fi
  FAILING_AND_TRIGGER_SQL_COUNT="$(cat ${RUNDIR}/${TRIAL}/${TRIAL}.sql.failing | wc -l)"
  if [ "${FAILING_AND_TRIGGER_SQL_COUNT}" -gt 0 ]; then
    if [ "${1}" != "NOREGEN" ]; then
      cat ${RUNDIR}/${TRIAL}/${TRIAL}.sql.failing >> ${INPUTFILE}  # Provision main SQL trace with failing/trigger queries
      echo "  > ${FAILING_AND_TRIGGER_SQL_COUNT} queries were added to the SQL trace to improve issue reproducibility"
    else  # Also provision the SQL trace used in quick_ (MULTI=1) setups
      if [ -r ${RUNDIR}/${TRIAL}/quick_${TRIAL}.sql ]; then
        cat ${RUNDIR}/${TRIAL}/${TRIAL}.sql.failing >> ${RUNDIR}/${TRIAL}/quick_${TRIAL}.sql
        echo "  > ${FAILING_AND_TRIGGER_SQL_COUNT} queries were added to the quick SQL trace to improve issue reproducibility"
      else
        echo "*** ASSERT ***: ${RUNDIR}/${TRIAL}/quick_${TRIAL}.sql does not exist, which is odd as add_failing_and_trigger_queries_to_trace() was called with NOREGEN"
       fi
    fi
  else
    echo "*** ASSERT ***: ${RUNDIR}/${TRIAL}/${TRIAL}.sql.failing lenght is 0, which should not happen, as trigger queries are always added"
    #exit 1  # While for normal operation exit 1 is recommend here, most setups now use automation (i.e. ~/gomd) and as such an exit here is not recommended as it will constantly stop short pquery-go-expert.sh runs
  fi
}

auto_interleave_failing_sql(){
  if [ -z "${1}" ]; then echo "Assert: auto_interleave_failing_sql called without option!"; exit 1; fi
  # sql interleave function based on actual input file size
  INPUTLINECOUNT=$(cat ${1} 2>/dev/null | wc -l)
  FAILING_AND_TRIGGER_SQL_COUNT=$(cat ${RUNDIR}/${TRIAL}/${TRIAL}.sql.failing 2>/dev/null | wc -l)
  if [ -z "${FAILING_AND_TRIGGER_SQL_COUNT}" -o ${FAILING_AND_TRIGGER_SQL_COUNT} -eq 0 ]; then
    return
  elif [ ${FAILING_AND_TRIGGER_SQL_COUNT} -lt 10 ]; then
    if [ ${INPUTLINECOUNT} -le 100 ]; then
      sed -i "0~3 r ${RUNDIR}/${TRIAL}/${TRIAL}.sql.failing" ${1}
    elif [ ${INPUTLINECOUNT} -le 500 ];then
      sed -i "0~15 r ${RUNDIR}/${TRIAL}/${TRIAL}.sql.failing" ${1}
    elif [ ${INPUTLINECOUNT} -le 1000 ];then
      sed -i "0~35 r ${RUNDIR}/${TRIAL}/${TRIAL}.sql.failing" ${1}
    else
      sed -i "0~50 r ${RUNDIR}/${TRIAL}/${TRIAL}.sql.failing" ${1}
    fi
  else
    if [ ${INPUTLINECOUNT} -le 100 ]; then
      sed -i "0~5 r ${RUNDIR}/${TRIAL}/${TRIAL}.sql.failing" ${1}
    elif [ ${INPUTLINECOUNT} -le 500 ];then
      sed -i "0~25 r ${RUNDIR}/${TRIAL}/${TRIAL}.sql.failing" ${1}
    elif [ ${INPUTLINECOUNT} -le 1000 ];then
      sed -i "0~50 r ${RUNDIR}/${TRIAL}/${TRIAL}.sql.failing" ${1}
    else
      sed -i "0~75 r ${RUNDIR}/${TRIAL}/${TRIAL}.sql.failing" ${1}
    fi
  fi
}

generate_reducer_script(){
  if [ "${BASE}" == "" ]; then
    echo "Assert! \$BASE is empty at start of generate_reducer_script()"
    exit 1
  fi
  USE_NEW_TEXT_STRING=1  # Set to 1 (on) until proven otherwise, i.e. when MODE!=3
  if [ -r ${BASE}/lib/mysql/plugin/ha_tokudb.so ]; then
    DISABLE_TOKUDB_AUTOLOAD=0
  else
    DISABLE_TOKUDB_AUTOLOAD=1
  fi
  if [ ${QC} -eq 0 ]; then
    PQUERY_EXTRA_OPTIONS="s|ZERO0|ZERO0|"
    PQUERYOPT_CLEANUP="s|ZERO0|ZERO0|"
  else
    PQUERY_EXTRA_OPTIONS="0,/#VARMOD#/s|#VARMOD#|PQUERY_EXTRA_OPTIONS=\"--log-all-queries --log-failed-queries --no-shuffle --log-query-statistics --log-client-output --log-query-number\"\n#VARMOD#|"
    PQUERYOPT_CLEANUP="0,/^[ \t]*PQUERY_EXTRA_OPTIONS[ \t]*=.*$/s|^[ \t]*PQUERY_EXTRA_OPTIONS[ \t]*=.*$|#PQUERY_EXTRA_OPTIONS=<set_below_in_machine_variables_section>|"
  fi
  ORIGINAL_TEXT="${TEXT}"
  if [ "$TEXT" == "" -o "$TEXT" == "my_print_stacktrace" -o "$TEXT" == "0" -o "$TEXT" == "NULL" -o "$TEXT" == "Assert: no core file found in */*core*" -a "${SAN_BUG}" != "1" ]; then  # Too general strings, or no TEXT found, use MODE=4 (any crash)
    MODE=4
    USE_NEW_TEXT_STRING=0  # As MODE=4 (any crash) is used, new_text_string.sh is not relevant
    SCAN_FOR_NEW_BUGS=0  # Reducer cannot scan for new bugs yet if USE_NEW_TEXT_STRING=0 TODO
    TEXT_CLEANUP="s|ZERO0|ZERO0|"  # A zero-effect change dummy (de-duplicates #VARMOD# code below)
    TEXT_STRING1="s|ZERO0|ZERO0|"
    TEXT_STRING2="s|ZERO0|ZERO0|"
  else  # Bug-specific TEXT string found, use relevant MODE in reducer.sh to let it reduce for that specific string
    if [ "${SAN_BUG}" -eq 1 ]; then  # ASAN, UBSAN or TSAN bug
      MODE=3
      USE_NEW_TEXT_STRING=1  # As the string is already set based on the SAN issue observed in the errorlog
      SCAN_FOR_NEW_BUGS=1
    elif [ "${VALGRIND_CHECK}" -eq 1 ]; then  # Valgrind bug
      MODE=1
      USE_NEW_TEXT_STRING=0  # As here new_text_string.sh will not be used, but valgrind_string.sh
      SCAN_FOR_NEW_BUGS=0  # Reducer cannot scan for new bugs yet if USE_NEW_TEXT_STRING=0 TODO
    elif [[ "$TEXT" == "MEMORY_NOT_FREED"* ]]; then  # Memory not freed bugs
      # UniqueID's will be: 'MEMORY_NOT_FREED|Warning: Memory not freed'
      MODE=3
      USE_NEW_TEXT_STRING=1  # As 'Memory not freed' is supported as of 27/08/22 by new_text_string.sh, we can use it here
      SCAN_FOR_NEW_BUGS=1 
    elif [[ "$TEXT" == "GOT_ERROR"* ]]; then  # Memory not freed bugs
      # UniqueID's will be in the form of: 'GOTERROR|mysqld: Got error .126 .Index is corrupted.', for example
      MODE=3
      USE_NEW_TEXT_STRING=1  # As 'Got error' is supported as of 27/08/22 by new_text_string.sh, we can use it here
      SCAN_FOR_NEW_BUGS=1 
    elif [[ "$TEXT" == "MARKED_AS_CRASHED"* ]]; then  # Table crashed bugs
      # UniqueID's will be in the form of: 'MARKED_AS_CRASHED|mysqld: Table .t. is marked as crashed and should be repaired', for example
      MODE=3
      USE_NEW_TEXT_STRING=1  # As 'Table is crashed' bugs are supported as of 27/08/22 by new_text_string.sh, we can use it here
      SCAN_FOR_NEW_BUGS=1 
    elif [[ "$TEXT" == "MARIADB_ERROR_CODE"* ]]; then  # Table crashed bugs
      # UniqueID's will be in the form of: 'MARIADB_ERROR_CODE|MariaDB error code: 1969'
      MODE=3
      USE_NEW_TEXT_STRING=1  # As 'Table is crashed' bugs are supported as of 27/08/22 by new_text_string.sh, we can use it here
      SCAN_FOR_NEW_BUGS=1 
    elif [ "${QC}" == "1" ]; then  # Query Correctness (QC) bug
      USE_NEW_TEXT_STRING=0  # As here we're doing QC (Query correctness testing)
      SCAN_FOR_NEW_BUGS=0  # Reducer cannot scan for new bugs yet if USE_NEW_TEXT_STRING=0 TODO
    else  # Standard bug, standard UniqueID
      MODE=3
      USE_NEW_TEXT_STRING=1
      SCAN_FOR_NEW_BUGS=1 
    fi
    TEXT_CLEANUP="0,/^[ \t]*TEXT[ \t]*=.*$/s|^[ \t]*TEXT[ \t]*=.*$|#TEXT=<set_below_in_machine_variables_section>|"
    TEXT_STRING1="0,/#VARMOD#/s:#VARMOD#:# IMPORTANT NOTE; Leave the 3 spaces before TEXT on the next line; pquery-results.sh uses these\n#VARMOD#:"
    # This code below is duplicated into reducer.sh. If it is updated here, please also update it there and vice versa. However, note that the code in reducer.sh is longer as it caters for '^   TEXT=' and '^TEXT=' - see the note in reducer.sh - the main variable name (TEXT vs NEWBUGTEXT) is also different, and the code in reducer.sh does not use QC as below. Be careful with changes as this is important code in the framework.
    if [[ "${TEXT}" = *":"* ]]; then
      if [[ "${TEXT}" = *"|"* ]]; then
        if [[ "${TEXT}" = *"/"* ]]; then
          if [[ "${TEXT}" = *"_"* ]]; then
            if [[ "${TEXT}" = *"-"* ]]; then
              if [[ "${TEXT}" = *"("* ]]; then
                if [[ "${TEXT}" = *")"* ]]; then
                  if [[ "${TEXT}" = *"@"* ]]; then
                    if [[ "${TEXT}" = *"+"* ]]; then
                      if [[ "${TEXT}" = *";"* ]]; then
                        if [[ "${TEXT}" = *","* ]]; then
                          if [[ "${TEXT}" = *">"* ]]; then

                            echo "Assert (#1)! No suitable sed seperator found. TEXT (${TEXT}) contains all of the possibilities, add more!"
                            TEXT="ASSERT: No suitable sed seperator found in pquery-prep-red.sh; add more!"
                            TEXT_STRING2="0,/#VARMOD#/s>#VARMOD#>   TEXT=\"${TEXT}\"\n#VARMOD#>"
                          else
                            if [ ${QC} -eq 0 ]; then
                              TEXT="$(echo "$TEXT"|sed "s>&>\\\\\\&>g")"  # Escape '&' correctly
                              TEXT_STRING2="0,/#VARMOD#/s>#VARMOD#>   TEXT=\"${TEXT}\"\n#VARMOD#>"
                            else
                              TEXT="$(echo "$TEXT"|sed "s>|>\\\\\\\|>g")"  # Escape '|' correctly
                              TEXT_STRING2="0,/#VARMOD#/s>#VARMOD#>   TEXT=\"^${TEXT}\$\"\n#VARMOD#>"
                            fi
                          fi
                        else
                          if [ ${QC} -eq 0 ]; then
                            TEXT="$(echo "$TEXT"|sed "s,&,\\\\\\&,g")"  # Escape '&' correctly
                            TEXT_STRING2="0,/#VARMOD#/s,#VARMOD#,   TEXT=\"${TEXT}\"\n#VARMOD#,"
                          else
                            TEXT="$(echo "$TEXT"|sed "s,|,\\\\\\\|,g")"  # Escape '|' correctly
                            TEXT_STRING2="0,/#VARMOD#/s,#VARMOD#,   TEXT=\"^${TEXT}\$\"\n#VARMOD#,"
                          fi
                        fi
                      else
                        if [ ${QC} -eq 0 ]; then
                          TEXT="$(echo "$TEXT"|sed "s;&;\\\\\\&;g")"  # Escape '&' correctly
                          TEXT_STRING2="0,/#VARMOD#/s;#VARMOD#;   TEXT=\"${TEXT}\"\n#VARMOD#;"
                        else
                          TEXT="$(echo "$TEXT"|sed "s;|;\\\\\\\|;g")"  # Escape '|' correctly
                          TEXT_STRING2="0,/#VARMOD#/s;#VARMOD#;   TEXT=\"^${TEXT}\$\"\n#VARMOD#;"
                        fi
                      fi
                    else
                      if [ ${QC} -eq 0 ]; then
                        TEXT="$(echo "$TEXT"|sed "s+&+\\\\\\&+g")"  # Escape '&' correctly
                        TEXT_STRING2="0,/#VARMOD#/s+#VARMOD#+   TEXT=\"${TEXT}\"\n#VARMOD#+"
                      else
                        TEXT="$(echo "$TEXT"|sed "s+|+\\\\\\\|+g")"  # Escape '|' correctly
                        TEXT_STRING2="0,/#VARMOD#/s+#VARMOD#+   TEXT=\"^${TEXT}\$\"\n#VARMOD#+"
                      fi
                    fi
                  else
                    if [ ${QC} -eq 0 ]; then
                      TEXT="$(echo "$TEXT"|sed "s@&@\\\\\\&@g")"  # Escape '&' correctly
                      TEXT_STRING2="0,/#VARMOD#/s@#VARMOD#@   TEXT=\"${TEXT}\"\n#VARMOD#@"
                    else
                      TEXT="$(echo "$TEXT"|sed "s@|@\\\\\\\|@g")"  # Escape '|' correctly
                      TEXT_STRING2="0,/#VARMOD#/s@#VARMOD#@   TEXT=\"^${TEXT}\$\"\n#VARMOD#@"
                    fi
                  fi
                else
                  if [ ${QC} -eq 0 ]; then
                    TEXT="$(echo "$TEXT"|sed "s)&)\\\\\\&)g")"  # Escape '&' correctly
                    TEXT_STRING2="0,/#VARMOD#/s)#VARMOD#)   TEXT=\"${TEXT}\"\n#VARMOD#)"
                  else
                    TEXT="$(echo "$TEXT"|sed "s)|)\\\\\\\|)g")"  # Escape '|' correctly
                    TEXT_STRING2="0,/#VARMOD#/s)#VARMOD#)   TEXT=\"^${TEXT}\$\"\n#VARMOD#)"
                  fi
                fi
              else
                if [ ${QC} -eq 0 ]; then
                  TEXT="$(echo "$TEXT"|sed "s(&(\\\\\\&(g")"  # Escape '&' correctly
                  TEXT_STRING2="0,/#VARMOD#/s(#VARMOD#(   TEXT=\"${TEXT}\"\n#VARMOD#("
                else
                  TEXT="$(echo "$TEXT"|sed "s(|(\\\\\\\|(g")"  # Escape '|' correctly
                  TEXT_STRING2="0,/#VARMOD#/s(#VARMOD#(   TEXT=\"^${TEXT}\$\"\n#VARMOD#("
                fi
              fi
            else
              if [ ${QC} -eq 0 ]; then
                TEXT="$(echo "$TEXT"|sed "s-&-\\\\\\&-g")"  # Escape '&' correctly
                TEXT_STRING2="0,/#VARMOD#/s-#VARMOD#-   TEXT=\"${TEXT}\"\n#VARMOD#-"
              else
                TEXT="$(echo "$TEXT"|sed "s-|-\\\\\\\|-g")"  # Escape '|' correctly
                TEXT_STRING2="0,/#VARMOD#/s-#VARMOD#-   TEXT=\"^${TEXT}\$\"\n#VARMOD#-"
              fi
            fi
          else
            if [ ${QC} -eq 0 ]; then
              TEXT="$(echo "$TEXT"|sed "s_&_\\\\\\&_g")"  # Escape '&' correctly
              TEXT_STRING2="0,/#VARMOD#/s_#VARMOD#_   TEXT=\"${TEXT}\"\n#VARMOD#_"
            else
              TEXT="$(echo "$TEXT"|sed "s_|_\\\\\\\|_g")"  # Escape '|' correctly
              TEXT_STRING2="0,/#VARMOD#/s_#VARMOD#_   TEXT=\"^${TEXT}\$\"\n#VARMOD#_"
            fi
          fi
        else
          if [ ${QC} -eq 0 ]; then
            TEXT="$(echo "$TEXT"|sed "s/&/\\\\\\&/g")"  # Escape '&' correctly
            TEXT_STRING2="0,/#VARMOD#/s/#VARMOD#/   TEXT=\"${TEXT}\"\n#VARMOD#/"
          else
            TEXT="$(echo "$TEXT"|sed "s/|/\\\\\\\|/g")"  # Escape '|' correctly
            TEXT_STRING2="0,/#VARMOD#/s/#VARMOD#/   TEXT=\"^${TEXT}\$\"\n#VARMOD#/"
          fi
        fi
      else
        if [ ${QC} -eq 0 ]; then
          TEXT="$(echo "$TEXT"|sed "s|&|\\\\\\&|g")"  # Escape '&' correctly
          TEXT_STRING2="0,/#VARMOD#/s|#VARMOD#|   TEXT=\"${TEXT}\"\n#VARMOD#|"
        else
          # TODO: check if something was missed here, or is there no swap needed for "|" perhaps? Note '|' is the sed main replacement char here.
          TEXT_STRING2="0,/#VARMOD#/s|#VARMOD#|   TEXT=\"^${TEXT}\$\"\n#VARMOD#|"
        fi
      fi
    else
      if [ ${QC} -eq 0 ]; then
        TEXT="$(echo "$TEXT"|sed "s:&:\\\\\\&:g")"  # Escape '&' correctly
        TEXT_STRING2="0,/#VARMOD#/s:#VARMOD#:   TEXT=\"${TEXT}\"\n#VARMOD#:"
      else
        TEXT="$(echo "$TEXT"|sed "s:|:\\\\\\\|:g")"  # Escape '|' correctly
        TEXT_STRING2="0,/#VARMOD#/s:#VARMOD#:   TEXT=\"^${TEXT}\$\"\n#VARMOD#:"
      fi
    fi
  fi
  if [ "${MYEXTRA}" != "" ]; then  # Fix any dual sql_mode spec
    MYEXTRA="$(echo "${MYEXTRA}" | sed 's|--sql_mode= --sql_mode=|--sql_mode=|g')"
  fi
  if [ "$MYEXTRA" == "" ]; then  # Empty MYEXTRA string
    MYEXTRA_CLEANUP="s|ZERO0|ZERO0|"
    MYEXTRA_STRING1="s|ZERO0|ZERO0|"  # Idem as above
  else  # MYEXTRA specifically set
    MYEXTRA_CLEANUP="0,/^[ \t]*MYEXTRA[ \t]*=.*$/s|^[ \t]*MYEXTRA[ \t]*=.*$|#MYEXTRA=<set_below_in_machine_variables_section>|"
    if [[ "${MYEXTRA}" = *":"* ]]; then
      if [[ "${MYEXTRA}" = *"|"* ]]; then
        if [[ "${MYEXTRA}" = *"!"* ]]; then
          echo "Assert! No suitable sed seperator found. MYEXTRA (${MYEXTRA}) contains all of the possibilities, add more!"
        else
          MYEXTRA_STRING1="0,/#VARMOD#/s!#VARMOD#!MYEXTRA=\"${MYEXTRA}\"\n#VARMOD#!"
        fi
      else
        MYEXTRA_STRING1="0,/#VARMOD#/s|#VARMOD#|MYEXTRA=\"${MYEXTRA}\"\n#VARMOD#|"
      fi
    else
      MYEXTRA_STRING1="0,/#VARMOD#/s:#VARMOD#:MYEXTRA=\"${MYEXTRA}\"\n#VARMOD#:"
    fi
  fi
  REPLICATION_CLEANUP="s|ZERO0|ZERO0|"
  REPLICATION_STRING1="s|ZERO0|ZERO0|"  # Idem as above
  REPL_EXTRA_CLEANUP="s|ZERO0|ZERO0|"
  REPL_EXTRA_STRING1="s|ZERO0|ZERO0|"  # Idem as above
  MASTER_EXTRA_CLEANUP="s|ZERO0|ZERO0|"
  MASTER_EXTRA_STRING1="s|ZERO0|ZERO0|"  # Idem as above
  SLAVE_EXTRA_CLEANUP="s|ZERO0|ZERO0|"
  SLAVE_EXTRA_STRING1="s|ZERO0|ZERO0|"  # Idem as above
  if [ -r ./${TRIAL}/REPLICATION_ACTIVE ]; then  # This was a replication based run
    REPLICATION_CLEANUP="0,/^[ \t]*REPLICATION[ \t]*=.*$/s|^[ \t]*REPLICATION[ \t]*=.*$|#REPLICATION=<set_below_in_machine_variables_section>|"
    REPLICATION_STRING1="0,/#VARMOD#/s!#VARMOD#!REPLICATION=1\n#VARMOD#!"
    if [ ! -z "$REPL_EXTRA" ]; then  # REPL_EXTRA set
      REPL_EXTRA_CLEANUP="0,/^[ \t]*REPL_EXTRA[ \t]*=.*$/s|^[ \t]*REPL_EXTRA[ \t]*=.*$|#REPL_EXTRA=<set_below_in_machine_variables_section>|"
      if [[ "${REPL_EXTRA}" = *":"* ]]; then
        if [[ "${REPL_EXTRA}" = *"|"* ]]; then
          if [[ "${REPL_EXTRA}" = *"!"* ]]; then
            echo "Assert! No suitable sed seperator found. REPL_EXTRA (${REPL_EXTRA}) contains all of the possibilities, add more!"
          else
            REPL_EXTRA_STRING1="0,/#VARMOD#/s!#VARMOD#!REPL_EXTRA=\"${REPL_EXTRA}\"\n#VARMOD#!"
          fi
        else
          REPL_EXTRA_STRING1="0,/#VARMOD#/s|#VARMOD#|REPL_EXTRA=\"${REPL_EXTRA}\"\n#VARMOD#|"
        fi
      else
        REPL_EXTRA_STRING1="0,/#VARMOD#/s:#VARMOD#:REPL_EXTRA=\"${REPL_EXTRA}\"\n#VARMOD#:"
      fi
    fi
    if [ ! -z "$MASTER_EXTRA" ]; then  # MASTER_EXTRA set
      MASTER_EXTRA_CLEANUP="0,/^[ \t]*MASTER_EXTRA[ \t]*=.*$/s|^[ \t]*MASTER_EXTRA[ \t]*=.*$|#MASTER_EXTRA=<set_below_in_machine_variables_section>|"
      if [[ "${MASTER_EXTRA}" = *":"* ]]; then
        if [[ "${MASTER_EXTRA}" = *"|"* ]]; then
          if [[ "${MASTER_EXTRA}" = *"!"* ]]; then
            echo "Assert! No suitable sed seperator found. MASTER_EXTRA (${MASTER_EXTRA}) contains all of the possibilities, add more!"
          else
            MASTER_EXTRA_STRING1="0,/#VARMOD#/s!#VARMOD#!MASTER_EXTRA=\"${MASTER_EXTRA}\"\n#VARMOD#!"
          fi
        else
          MASTER_EXTRA_STRING1="0,/#VARMOD#/s|#VARMOD#|MASTER_EXTRA=\"${MASTER_EXTRA}\"\n#VARMOD#|"
        fi
      else
        MASTER_EXTRA_STRING1="0,/#VARMOD#/s:#VARMOD#:MASTER_EXTRA=\"${MASTER_EXTRA}\"\n#VARMOD#:"
      fi
    fi
    if [ ! -z "$SLAVE_EXTRA" ]; then  # SLAVE_EXTRA set
      SLAVE_EXTRA_CLEANUP="0,/^[ \t]*SLAVE_EXTRA[ \t]*=.*$/s|^[ \t]*SLAVE_EXTRA[ \t]*=.*$|#SLAVE_EXTRA=<set_below_in_machine_variables_section>|"
      if [[ "${SLAVE_EXTRA}" = *":"* ]]; then
        if [[ "${SLAVE_EXTRA}" = *"|"* ]]; then
          if [[ "${SLAVE_EXTRA}" = *"!"* ]]; then
            echo "Assert! No suitable sed seperator found. SLAVE_EXTRA (${SLAVE_EXTRA}) contains all of the possibilities, add more!"
          else
            SLAVE_EXTRA_STRING1="0,/#VARMOD#/s!#VARMOD#!SLAVE_EXTRA=\"${SLAVE_EXTRA}\"\n#VARMOD#!"
          fi
        else
          SLAVE_EXTRA_STRING1="0,/#VARMOD#/s|#VARMOD#|SLAVE_EXTRA=\"${SLAVE_EXTRA}\"\n#VARMOD#|"
        fi
      else
        SLAVE_EXTRA_STRING1="0,/#VARMOD#/s:#VARMOD#:SLAVE_EXTRA=\"${SLAVE_EXTRA}\"\n#VARMOD#:"
      fi
    fi
  fi
  if [ -z "$MYINIT" ]; then  # Empty MYINIT string
    MYINIT_CLEANUP="s|ZERO0|ZERO0|"
    MYINIT_STRING1="s|ZERO0|ZERO0|"  # Idem as above
  else  # MYINIT specifically set
    MYINIT_CLEANUP="0,/^[ \t]*MYINIT[ \t]*=.*$/s|^[ \t]*MYINIT[ \t]*=.*$|#MYINIT=<set_below_in_machine_variables_section>|"
    if [[ "${MYINIT}" = *":"* ]]; then
      if [[ "${MYINIT}" = *"|"* ]]; then
        if [[ "${MYINIT}" = *"!"* ]]; then
          echo "Assert! No suitable sed seperator found. MYINIT (${MYINIT}) contains all of the possibilities, add more!"
        else
          MYINIT_STRING1="0,/#VARMOD#/s!#VARMOD#!MYINIT=\"${MYINIT}\"\n#VARMOD#!"
        fi
      else
        MYINIT_STRING1="0,/#VARMOD#/s|#VARMOD#|MYINIT=\"${MYINIT}\"\n#VARMOD#|"
      fi
    else
      MYINIT_STRING1="0,/#VARMOD#/s:#VARMOD#:MYINIT=\"${MYINIT}\"\n#VARMOD#:"
    fi
  fi
  if [ "$WSREP_PROVIDER_OPTIONS" == "" ]; then  # Empty MYEXTRA string
    WSREP_OPT_CLEANUP="s|ZERO0|ZERO0|"
    WSREP_OPT_STRING="s|ZERO0|ZERO0|"  # Idem as above
  else
    WSREP_OPT_CLEANUP="0,/^[ \t]*WSREP_PROVIDER_OPTIONS[ \t]*=.*$/s|^[ \t]*WSREP_PROVIDER_OPTIONS[ \t]*=.*$|#WSREP_PROVIDER_OPTIONS=<set_below_in_machine_variables_section>|"
    WSREP_OPT_STRING="0,/#VARMOD#/s:#VARMOD#:WSREP_PROVIDER_OPTIONS=\"${WSREP_PROVIDER_OPTIONS}\"\n#VARMOD#:"
  fi
  if [ "$MULTI" != "1" ]; then  # Not a multi-threaded pquery run
    MULTI_CLEANUP="s|ZERO0|ZERO0|"  # Idem as above
    MULTI_CLEANUP2="s|ZERO0|ZERO0|"
    MULTI_CLEANUP3="s|ZERO0|ZERO0|"
    MULTI_STRING1="s|ZERO0|ZERO0|"
    MULTI_STRING2="s|ZERO0|ZERO0|"
    MULTI_STRING3="s|ZERO0|ZERO0|"
  else  # Multi-threaded pquery run
    MULTI_CLEANUP1="0,/^[ \t]*PQUERY_MULTI[ \t]*=.*$/s|^[ \t]*PQUERY_MULTI[ \t]*=.*$|#PQUERY_MULTI=<set_below_in_machine_variables_section>|"
    MULTI_CLEANUP2="0,/^[ \t]*FORCE_SKIPV[ \t]*=.*$/s|^[ \t]*FORCE_SKIPV[ \t]*=.*$|#FORCE_SKIPV=<set_below_in_machine_variables_section>|"
    MULTI_CLEANUP3="0,/^[ \t]*FORCE_SPORADIC[ \t]*=.*$/s|^[ \t]*FORCE_SPORADIC[ \t]*=.*$|#FORCE_SPORADIC=<set_below_in_machine_variables_section>|"
    MULTI_STRING1="0,/#VARMOD#/s:#VARMOD#:PQUERY_MULTI=1\n#VARMOD#:"
    MULTI_STRING2="0,/#VARMOD#/s:#VARMOD#:FORCE_SKIPV=1\n#VARMOD#:"
    MULTI_STRING3="0,/#VARMOD#/s:#VARMOD#:FORCE_SPORADIC=1\n#VARMOD#:"
  fi
  if [[ ${MDG} -eq 1 ]]; then
    MDG_CLEANUP1="0,/^[ \t]*MDG[ \t]*=.*$/s|^[ \t]*MDG[ \t]*=.*$|#MDG=<set_below_in_machine_variables_section>|"
    MDG_CLEANUP2="0,/^[ \t]*NR_OF_NODES[ \t]*=.*$/s|^[ \t]*NR_OF_NODES[ \t]*=.*$|#NR_OF_NODES=<set_below_in_machine_variables_section>|"
    MDG_STRING1="0,/#VARMOD#/s:#VARMOD#:export MDG=1\n#VARMOD#:"
    MDG_STRING2="0,/#VARMOD#/s:#VARMOD#:NR_OF_NODES=${NR_OF_NODES}\n#VARMOD#:"
    MDG_STRING3="0,/#VARMOD#/s:#VARMOD#:GALERA_NODE=${SUBDIR}\n#VARMOD#:"
  else
    MDG_CLEANUP1="s|ZERO0|ZERO0|"  # Idem as above
    MDG_STRING1="s|ZERO0|ZERO0|"
  fi
  if [[ ${ENCRYPTION_RUN} -eq 1 ]]; then
    ENCRYPTION_RUN_CLEANUP="0,/^[ \t]*ENCRYPTION_RUN[ \t]*=.*$/s|^[ \t]*ENCRYPTION_RUN[ \t]*=.*$|#ENCRYPTION_RUN=<set_below_in_machine_variables_section>|"
    ENCRYPTION_RUNSTRING="0,/#VARMOD#/s:#VARMOD#:export ENCRYPTION_RUN=1\n#VARMOD#:"
  else
    ENCRYPTION_RUN_CLEANUP="s|ZERO0|ZERO0|"  # Idem as above
    ENCRYPTION_RUN_STRING="s|ZERO0|ZERO0|"
  fi
  if [[ ${RR_TRACING} -eq 1 ]]; then
    RR_TRACING_CLEANUP="0,/^[ \t]*RR_TRACING[ \t]*=.*$/s|^[ \t]*RR_TRACING[ \t]*=.*$|#RR_TRACING=<set_below_in_machine_variables_section>|"
    RR_TRACING_STRING="0,/#VARMOD#/s:#VARMOD#:export RR_TRACING=1\n#VARMOD#:"
  else
    RR_TRACING_CLEANUP="s|ZERO0|ZERO0|"  # Idem as above
    RR_TRACING_STRING="s|ZERO0|ZERO0|"
  fi
  if [[ ${GRP_RPL} -eq 1 ]]; then
    GRP_RPL_CLEANUP1="0,/^[ \t]*GRP_RPL[ \t]*=.*$/s|^[ \t]*GRP_RPL[ \t]*=.*$|#GRP_RPL=<set_below_in_machine_variables_section>|"
    GRP_RPL_STRING1="0,/#VARMOD#/s:#VARMOD#:GRP_RPL=1\n#VARMOD#:"
  else
    GRP_RPL_CLEANUP1="s|ZERO0|ZERO0|"  # Idem as above
    GRP_RPL_STRING1="s|ZERO0|ZERO0|"
  fi
  if [[ ${QC} -eq 0 ]]; then
    REDUCER_FILENAME=reducer${OUTFILE}.sh
    QC_STRING1="s|ZERO0|ZERO0|"
    QC_STRING2="s|ZERO0|ZERO0|"
    QC_STRING3="s|ZERO0|ZERO0|"
    QC_STRING4="s|ZERO0|ZERO0|"
  else
    REDUCER_FILENAME=qcreducer${OUTFILE}.sh
    QC_STRING1="s|CURRENTLINE=2|CURRENTLINE=5|g"
    QC_STRING2="s|REALLINE=2|REALLINE=5|g"
    # Ref [*], temporarily disabled
    # QC_STRING3="0,/#VARMOD#/s:#VARMOD#:QCTEXT=\"${QCTEXT}\"\n#VARMOD#:"
    QC_STRING3="0,/#VARMOD#/s:#VARMOD#:#QCTEXT=\"${QCTEXT}\"\n#VARMOD#:"
    QC_STRING4="s|SKIPSTAGEABOVE=9|SKIPSTAGEABOVE=3|"
  fi
  if [[ ${STARTUP_ISSUE} -eq 0 ]]; then
    SI_CLEANUP1="s|ZERO0|ZERO0|"
    SI_STRING1="s|ZERO0|ZERO0|"
  else
    SI_CLEANUP1="0,/^[ \t]*REDUCE_STARTUP_ISSUES[ \t]*=.*$/s|^[ \t]*REDUCE_STARTUP_ISSUES[ \t]*=.*$|#REDUCE_STARTUP_ISSUES=<set_below_in_machine_variables_section>|"
    SI_STRING1="0,/#VARMOD#/s:#VARMOD#:REDUCE_STARTUP_ISSUES=1\n#VARMOD#:"
  fi
  SAVE_RESULTS_CLEANUP="0,/^[ \t]*SAVE_RESULTS[ \t]*=.*$/s|^[ \t]*SAVE_RESULTS[ \t]*=.*$|#SAVE_RESULTS=<set_below_in_machine_variables_section>|"
  cat ${REDUCER} \
   | sed "0,/^[ \t]*INPUTFILE[ \t]*=.*$/s|^[ \t]*INPUTFILE[ \t]*=.*$|#INPUTFILE=<set_below_in_machine_variables_section>|" \
   | sed "0,/^[ \t]*MODE[ \t]*=.*$/s|^[ \t]*MODE[ \t]*=.*$|#MODE=<set_below_in_machine_variables_section>|" \
   | sed "0,/^[ \t]*DISABLE_TOKUDB_AUTOLOAD[ \t]*=.*$/s|^[ \t]*DISABLE_TOKUDB_AUTOLOAD[ \t]*=.*$|#DISABLE_TOKUDB_AUTOLOAD=<set_below_in_machine_variables_section>|" \
   | sed "0,/^[ \t]*TEXT_STRING_LOC[ \t]*=.*$/s|^[ \t]*TEXT_STRING_LOC[ \t]*=.*$|#TEXT_STRING_LOC=<set_below_in_machine_variables_section>|" \
   | sed "0,/^[ \t]*USE_NEW_TEXT_STRING[ \t]*=.*$/s|^[ \t]*USE_NEW_TEXT_STRING[ \t]*=.*$|#USE_NEW_TEXT_STRING=<set_below_in_machine_variables_section>|" \
   | sed "0,/^[ \t]*SCAN_FOR_NEW_BUGS[ \t]*=.*$/s|^[ \t]*SCAN_FOR_NEW_BUGS[ \t]*=.*$|#SCAN_FOR_NEW_BUGS=<set_below_in_machine_variables_section>|" \
   | sed "0,/^[ \t]*KNOWN_BUGS_LOC[ \t]*=.*$/s|^[ \t]*KNOWN_BUGS_LOC[ \t]*=.*$|#KNOWN_BUGS_LOC=<set_below_in_machine_variables_section>|" \
   | sed  "0,/^[ \t]*SCRIPT_PWD[ \t]*=.*$/s|^[ \t]*SCRIPT_PWD[ \t]*=.*$|SCRIPT_PWD=${SCRIPT_PWD}|" \
   | sed "${PQUERYOPT_CLEANUP}" \
   | sed "${MYEXTRA_CLEANUP}" \
   | sed "${MYINIT_CLEANUP}" \
   | sed "${REPLICATION_CLEANUP}" \
   | sed "${REPL_EXTRA_CLEANUP}" \
   | sed "${MASTER_EXTRA_CLEANUP}" \
   | sed "${SLAVE_EXTRA_CLEANUP}" \
   | sed "${WSREP_OPT_CLEANUP}" \
   | sed "${TEXT_CLEANUP}" \
   | sed "${MULTI_CLEANUP1}" \
   | sed "${MULTI_CLEANUP2}" \
   | sed "${MULTI_CLEANUP3}" \
   | sed "0,/^[ \t]*BASEDIR[ \t]*=.*$/s|^[ \t]*BASEDIR[ \t]*=.*$|#BASEDIR=<set_below_in_machine_variables_section>|" \
   | sed "0,/^[ \t]*USE_PQUERY[ \t]*=.*$/s|^[ \t]*USE_PQUERY[ \t]*=.*$|#USE_PQUERY=<set_below_in_machine_variables_section>|" \
   | sed "0,/^[ \t]*PQUERY_LOC[ \t]*=.*$/s|^[ \t]*PQUERY_LOC[ \t]*=.*$|#PQUERY_LOC=<set_below_in_machine_variables_section>|" \
   | sed "${MDG_CLEANUP1}" \
   | sed "${MDG_CLEANUP2}" \
   | sed "${ENCRYPTION_RUN_CLEANUP}" \
   | sed "${RR_TRACING_CLEANUP}" \
   | sed "${GRP_RPL_CLEANUP1}" \
   | sed "${SI_CLEANUP1}" \
   | sed "${SI_STRING1}" \
   | sed "0,/#VARMOD#/s:#VARMOD#:MODE=${MODE}\n#VARMOD#:" \
   | sed "0,/#VARMOD#/s:#VARMOD#:USE_NEW_TEXT_STRING=${USE_NEW_TEXT_STRING}\n#VARMOD#:" \
   | sed "${TEXT_STRING1}" \
   | sed "${TEXT_STRING2}" \
   | sed "0,/#VARMOD#/s:#VARMOD#:BASEDIR=\"${BASE}\"\n#VARMOD#:" \
   | sed "0,/#VARMOD#/s:#VARMOD#:INPUTFILE=\"${INPUTFILE}\"\n#VARMOD#:" \
   | sed "0,/#VARMOD#/s:#VARMOD#:SCAN_FOR_NEW_BUGS=${SCAN_FOR_NEW_BUGS}\n#VARMOD#:" \
   | sed "0,/#VARMOD#/s:#VARMOD#:KNOWN_BUGS_LOC=\"${SCRIPT_PWD}/known_bugs.strings\"\n#VARMOD#:" \
   | sed "0,/#VARMOD#/s:#VARMOD#:TEXT_STRING_LOC=\"${SCRIPT_PWD}/new_text_string.sh\"\n#VARMOD#:" \
   | sed "0,/#VARMOD#/s:#VARMOD#:DISABLE_TOKUDB_AUTOLOAD=${DISABLE_TOKUDB_AUTOLOAD}\n#VARMOD#:" \
   | sed "${MYEXTRA_STRING1}" \
   | sed "${MYINIT_STRING1}" \
   | sed "${REPLICATION_STRING1}" \
   | sed "${REPL_EXTRA_STRING1}" \
   | sed "${MASTER_EXTRA_STRING1}" \
   | sed "${SLAVE_EXTRA_STRING1}" \
   | sed "${WSREP_OPT_STRING}" \
   | sed "${MULTI_STRING1}" \
   | sed "${MULTI_STRING2}" \
   | sed "${MULTI_STRING3}" \
   | sed "0,/#VARMOD#/s:#VARMOD#:USE_PQUERY=1\n#VARMOD#:" \
   | sed "0,/#VARMOD#/s:#VARMOD#:PQUERY_LOC=${PQUERY_BIN}\n#VARMOD#:" \
   | sed "${SAVE_RESULTS_CLEANUP}" \
   | sed "0,/#VARMOD#/s:#VARMOD#:SAVE_RESULTS=0\n#VARMOD#:" \
   | sed "${MDG_STRING1}" \
   | sed "${MDG_STRING2}" \
   | sed "${MDG_STRING3}" \
   | sed "${ENCRYPTION_RUN_STRING}" \
   | sed "${RR_TRACING_STRING}" \
   | sed "${GRP_RPL_STRING1}" \
   | sed "${QC_STRING1}" \
   | sed "${QC_STRING2}" \
   | sed "${QC_STRING3}" \
   | sed "${QC_STRING4}" \
   | sed "${PQUERY_EXTRA_OPTIONS}" \
   > ${REDUCER_FILENAME}

  # We want to use the originally detected TEXT string here (stored in ORIGINAL_TEXT) as the TEXT variable has been modified above for strings that contain '&' or '|'
  FINDBUG="$(grep -hFi --binary-files=text "${ORIGINAL_TEXT}" ${SCRIPT_PWD}/known_bugs.strings ${SCRIPT_PWD}/known_bugs.strings.SAN)"
  if [[ "${FINDBUG}" =~ ^[[:space:]]*# ]]; then FINDBUG=""; fi  # Bugs marked as fixed need to be excluded
  # Note that if a known bug was found, FINDBUG is not empty and the next section is skipped, immediately proceeding with using the error log found issue, provided it is not empty
  if [ -z "${FINDBUG}" ]; then  # In case we did not find the bug in the known bugs lists, there may still be scenario's in which we can use the error log string (for example: no core found etc.), if present;
    # Provided that the ERROR_LOG_SCAN_ISSUE flag is present...
    if [ ! -z "$(ls ${RUNDIR}/${TRIAL}/ERROR_LOG_SCAN_ISSUE ${RUNDIR}/${TRIAL}/node*/ERROR_LOG_SCAN_ISSUE 2>/dev/null)" ]; then
      ALT_ACTIVATIONS=0  # ...check if there are any other alternative situations in which we can use the error log string:
      # 'No .* found' scans for 'Assert: no core file found in */*core*, and fallback_text_string.sh returned an empty output'
      if [ ! -z "$(echo "${ORIGINAL_TEXT}" | grep -i "No .* found")" ]; then ALT_ACTIVATIONS=1; fi  # No core file found
      if grep -qi "No .* found" ${RUNDIR}/${TRIAL}/MYBUG ${RUNDIR}/${TRIAL}/node*/MYBUG 2>/dev/null; then ALT_ACTIVATIONS=1; fi  # Idem, but as written to MYBUG
      if [ -z "$(ls ${RUNDIR}/${TRIAL}/MYBUG ${RUNDIR}/${TRIAL}/node*/MYBUG 2>/dev/null)" ]; then ALT_ACTIVATIONS=1; fi  # If no MYBUG was written by pquery-run.sh we can use the error log issue message (as we are sure there is one present given the ERROR_LOG_SCAN_ISSUE check above), and this is true for the above 'no core file found' messages above as well. And, it is again checked below (whetter empty or not)
      if [ "${ALT_ACTIVATIONS}" -eq 1 ]; then
        FINDBUG="YES"  # We had a 'Assert: no core file found in */*core*, and fallback_text_string.sh returned an empty output' trial or similar situation, where there was an error log issue present (i.e. ERROR_LOG_SCAN_ISSUE flag present), so we can update the TEXT to the error log issue. 'YES' Is just a dummy string to trigger the if below to proceed
      fi
      ALT_ACTIVATIONS=
    fi
  fi
  if [ ! -z "${FINDBUG}" ]; then  # Already known and logged, non-fixed bug, use an error log entry instead, using pquery-trial-del.sh (in 'CHECK' non-delete mode only) to tell us what string to use (and additionally pquery-trial-del.sh automatically provides some TEXT regex cleanup in this mode)
    ERROR_LOG_STRING="$(${SCRIPT_PWD}/pquery-del-trial.sh ${TRIAL} CHECK)"
    if [ ! -z "${ERROR_LOG_STRING}" ]; then
      sed -i "s|^USE_NEW_TEXT_STRING=.*|USE_NEW_TEXT_STRING=0  # We set the TEXT to the first UNfiltered error log bug as the main issue seen during this trial (as reflected '#TEXT=' below) is already a known and filtered bug. Note: you may (or may not) need to edit the TEXT=... string (by making it more universal if required) before starting this reducer, for example by removing a port number, replication GTID number sequence or similar|" ${REDUCER_FILENAME}
      sed -i "s|^   \(TEXT=.*\)|   TEXT=\"$ERROR_LOG_STRING\"\n#\1|" ${REDUCER_FILENAME}
    fi
    echo "* TEXT variable set to: '${ERROR_LOG_STRING}'" 
    ERROR_LOG_STRING=
  fi
  FINDBUG=
  ORIGINAL_TEXT=  # This variable was only used for the checks above

  chmod +x ${REDUCER_FILENAME}
  # If this is a multi-threaded run, create additional quick reducers with only the executed SQL (may/may not work)
  # The quick_ reducer script is a copy of the normal already generated reducer with a changed inputfile, others below
  if [ "${MULTI}" == "1" -a ${QC} -eq 0 ]; then
    QUICK_REDUCER_FILENAME="$(echo "${REDUCER_FILENAME}" | sed 's|^|quick_|')"
    if [ ! -z "${QUICK_REDUCER_FILENAME}" ]; then
      if [ -r "${QUICK_REDUCER_FILENAME}" -a ! -d "${QUICK_REDUCER_FILENAME}" ]; then
        rm -f "${QUICK_REDUCER_FILENAME}"
      fi
      if [ "$(ls --color=never ${RUNDIR}/${TRIAL}/*thread-[0-9]*.sql 2>/dev/null | wc -l)" -gt 0 ]; then
        # ------------------------------------------------------------------------------------------------------------
        # TODO: test if adding "DROP DATABASE test;", "CREATE DATABASE test;" (next line) and "USE test;" (idem) here
        # would or would not increase reproducibility. 1st impression is NO unless the needed SQL to produce is simple
        # The reasoning is that the DROP will be hit regularly by many threads, immediately breaking down an
        # exixsting potential buildup towards the issue. Partly negated by quick_onethd_rnd_ reducer creation below.
        # ------------------------------------------------------------------------------------------------------------
        # Build quick_{trial}.sql file by taking all executed SQL from all threads, ...
        cat ${RUNDIR}/${TRIAL}/*thread-[0-9]*.sql > ${RUNDIR}/${TRIAL}/quick_${TRIAL}.sql 2>/dev/null
        # Then do the same standard processing: add failing queries thrice, add SELECT 1's, add SELECT SLEEP's, ...
        # Note that if there is one failing query and one in the error log, then result is it will be added 6x
        # This is fine and >=3 occurrences is desired in any case (may help with sporadic issues)
        if [ -r ${RUNDIR}/${TRIAL}/${TRIAL}.sql.failing ]; then
          for((i=0;i<3;i++)){
            cat ${RUNDIR}/${TRIAL}/${TRIAL}.sql.failing >> ${RUNDIR}/${TRIAL}/quick_${TRIAL}.sql 2>/dev/null
          }
        fi
        # And, attempt to extract the failing query from the pquery sql trace and repeat it thrice
        if [ -r ${RUNDIR}/${TRIAL}/default.node.tld_thread-0.sql ]; then
          for((i=0;i<3;i++)){
            grep --binary-files=text -i 'lost connection to server during query' ${RUNDIR}/${TRIAL}/default.node.tld_thread-0.sql >> ${RUNDIR}/${TRIAL}/quick_${TRIAL}.sql
          }
        fi
        add_failing_and_trigger_queries_to_trace NOREGEN
        remove_non_sql_from_trace ${RUNDIR}/${TRIAL}/quick_${TRIAL}.sql
        # Then interleave in extra failing queries all along the sql file (scaled/chuncked). This may increase
        # reproducibility, and is done for multi-threaded issues (who tend to be reduced by random-order replay!) only
        # Multi-threaded issues are auto-set to random order replay accross many threads, ensuring
        auto_interleave_failing_sql ${RUNDIR}/${TRIAL}/quick_${TRIAL}.sql
        sed "s|${TRIAL}/${TRIAL}.sql|${TRIAL}/quick_${TRIAL}.sql|" "${REDUCER_FILENAME}" > "${QUICK_REDUCER_FILENAME}"  # Generates quick_reducer{trial}.sh with new quick_ input file.
        sed -i "s|^MULTI_THREADS=3|MULTI_THREADS=10|" "${QUICK_REDUCER_FILENAME}"  # Speed things up
        sed -i "s|^PQUERY_MULTI_CLIENT_THREADS=30|PQUERY_MULTI_CLIENT_THREADS=20|" "${QUICK_REDUCER_FILENAME}"  # Don't overdo, scale better
        chmod +x ${QUICK_REDUCER_FILENAME}
        # Make yet another quick_onethd_reducer{trial}.sh which will attempt an even quicker (and potentially less
        # likely to reproduce) reduction using the quick_ input file and run it in a single thread run.
        # The quick_ and quick_onethd_ reducers are meant to reduce the usual "few days" true multi-threaded
        # testcase reduction down to a few hours for at least a subset of the issues which are more easy to reproduce
        QUICK_ONETHD_REDUCER_FILENAME="$(echo "${QUICK_REDUCER_FILENAME}" | sed 's|quick_|quick_onethd_|')"
        cp ${QUICK_REDUCER_FILENAME} ${QUICK_ONETHD_REDUCER_FILENAME}
        QUICK_REDUCER_FILENAME=
        sed -i "s|^PQUERY_MULTI=1|PQUERY_MULTI=0|" ${QUICK_ONETHD_REDUCER_FILENAME}  # Turn of multi-threaded
        # Note that issue reproducibility for original-multithreaded issues may suffer in many cases when attempting
        # a single thread replay using quick_onethd_ reducers. For example, a later DROP TABLE may have mixed in from
        # another thread, thereby rendering the testcase invalid. To counter this, yet another quick_onethd_rnd_
        # reducer is created which will replay the testcase in random order alike to a true multi-threaded reduction
        QUICK_ONETHD_RND_REDUCER_FILENAME="$(echo "${QUICK_ONETHD_REDUCER_FILENAME}" | sed 's|onethd_|onethd_rnd_|')"
        cp ${QUICK_ONETHD_REDUCER_FILENAME} ${QUICK_ONETHD_RND_REDUCER_FILENAME}
        QUICK_ONETHD_REDUCER_FILENAME=
        sed -i "s|^PQUERY_REVERSE_NOSHUFFLE_OPT=0|PQUERY_REVERSE_NOSHUFFLE_OPT=1|" ${QUICK_ONETHD_RND_REDUCER_FILENAME}  # Turn on random shuffle replay
        QUICK_ONETHD_RND_REDUCER_FILENAME=
        # The 3 additional created reducers (quick random, quick 1 thread sequential, quick 1 thread random) cover
        # as good as any concievable situation outside of a true multi-threaded reduction (which is the most costly
        # in terms of machine time). Having all 4 enables one to approach all multi-threaded issues straightforwardly
      fi
    fi
  fi
}

# Main pquery results processing
if [ ${QC} -eq 0 ]; then
  if [[ ${MDG} -eq 1 || ${GRP_RPL} -eq 1 ]]; then
    for TRIAL in $(ls ./*/node*/*core* 2>/dev/null | sed 's|./||;s|/.*||' | sort | sort -u); do
      for SUBDIR in `ls -lt ${TRIAL} --time-style="long-iso"  | egrep --binary-files=text '^d' | awk '{print $8}' | grep --binary-files=text -v tmp | tr -dc '0-9\n' | sort`; do
        export GALERA_CORE_LOC=`ls -1 ./${TRIAL}/node${SUBDIR}/*core* 2>&1 | head -n1 | grep --binary-files=text -v "No such file"`
        export GALERA_ERROR_LOG=./${TRIAL}/node${SUBDIR}/node${SUBDIR}.err
        OUTFILE="${TRIAL}-${SUBDIR}"
        rm -Rf ${RUNDIR}/${TRIAL}/${TRIAL}.sql.failing
        touch ${RUNDIR}/${TRIAL}/${TRIAL}.sql.failing
        echo "========== Processing pquery trial ${TRIAL}-${SUBDIR}"
        if [ -r ./reducer${TRIAL}-${SUBDIR}.sh ]; then
          echo "* Reducer for this trial (./reducer${TRIAL}_${SUBDIR}.sh) already exists. Skipping to next trial/node."
          continue
        fi
        REPL_EXTRA=
        MASTER_EXTRA=
        SLAVE_EXTRA=
        if [ -r ./${TRIAL}/REPLICATION_ACTIVE ]; then  # This was a replication based run
          if [ -r ./${TRIAL}/REPL_EXTRA ]; then
            REPL_EXTRA="$(cat ./${TRIAL}/REPL_EXTRA 2>/dev/null)"
          fi
          if [ -r ./${TRIAL}/MASTER_EXTRA ]; then
            MASTER_EXTRA="$(cat ./${TRIAL}/MASTER_EXTRA 2>/dev/null)"
          fi
          if [ -r ./${TRIAL}/SLAVE_EXTRA ]; then
            SLAVE_EXTRA="$(cat ./${TRIAL}/SLAVE_EXTRA 2>/dev/null)"
          fi
        fi
        MYEXTRA=
        if [ -r ./${TRIAL}/MYEXTRA ]; then
          MYEXTRA="$(cat ./${TRIAL}/MYEXTRA 2>/dev/null)"
        else
          echo "Warning: no MYEXTRA file found for trial ${TRIAL} (./${TRIAL}/MYEXTRA). This should not be the case, unless this run ran out of diskspace"
        fi
        MYINIT=
        if [ -r ./${TRIAL}/MYINIT ]; then
          MYINIT="$(cat ./${TRIAL}/MYINIT 2>/dev/null)"
        fi
        if [ ${WSREP_OPTION_CHECK} -eq 1 ]; then
          WSREP_PROVIDER_OPTIONS=$(cat ./${TRIAL}/WSREP_PROVIDER_OPT 2>/dev/null)
        fi
        if [ "${MULTI}" == "1" ]; then
          INPUTFILE=${RUNDIR}/${TRIAL}/${TRIAL}.sql
          if [ ! -r ${INPUTFILE}.backup ]; then
            cp ${INPUTFILE} ${INPUTFILE}.backup
          else
            cp ${INPUTFILE}.backup ${INPUTFILE}  # Reset ${INPUTFILE} file contents (avoids the file getting larger every time this script is executed due to auto_interleave_failing_sql() being called again.
          fi
        else
          if [ $(ls -1 ./${TRIAL}/*thread-0.sql 2>/dev/null|wc -l) -gt 1 ]; then
            INPUTFILE=$(ls ./${TRIAL}/node${SUBDIR}*thread-0.sql)
          elif [ -f ./${TRIAL}/*thread-0.sql ]; then
            INPUTFILE=`ls ./${TRIAL}/*thread-0.sql | sed "s|^[./]\+|/|;s|^|${RUNDIR}|"`
          else
            INPUTFILE=${RUNDIR}/${TRIAL}/${TRIAL}-${SUBDIR}.sql
          fi
        fi
        BIN="$(ls -1 ${RUNDIR}/${TRIAL}/node${SUBDIR}/mariadbd ${RUNDIR}/${TRIAL}/node${SUBDIR}/mysqld 2>&1 | head -n1 | grep --binary-files=text -v 'No such file')"
        if [ ! -r $BIN ]; then
          echo "Assert! mariadbd/mysqld binary '$BIN' could not be read"
          exit 1
        fi
        BASE="$(grep --binary-files=text 'Basedir:' ./pquery-run.log 2>/dev/null | sed 's|^.*Basedir[: \t]*||;;s/|.*$//' | tr -d '[[:space:]]')"
        if [ -z "${BASE}" ]; then BASE="/test/SOMEBASEDIR"; fi
        if [ ! -r ./${TRIAL}/node${SUBDIR}/MYBUG ]; then  # [re-]generate it if not present  TODO: find reason (in pquery-run.sh likely) why it not always generated by pquery-run.sh (or later deleted?)
          cd ./${TRIAL}/node${SUBDIR} || exit 1
          ${SCRIPT_PWD}/new_text_string.sh > ./MYBUG
          cd - >/dev/null || exit 1
        fi
        TEXT="$(cat ./${TRIAL}/node${SUBDIR}/MYBUG | head -n1 | sed 's|"|\\\\"|g')"  # TODO: this change needs further testing for cluster/GR. Also, it is likely someting was missed for this in the updated pquery-run.sh: the need to generate a MYBUG file for each node!   # The sed transforms " to \" to avoid TEXT containing doube quotes in reducer.sh. This works correctly, even though TEXT is set to "some text \" some text \" some text" in reducer.sh. i.e. bugs are reduced correctly.
        if [[ "${TEXT}" == "Assert:"* ]]; then  # Try to re-generate MYBUG in case something went amiss during pquery-run.sh (i.e. when 'Assert:' is seen in MYBUG)
          cd ./${TRIAL}/node${SUBDIR} || exit 1
          ${SCRIPT_PWD}/new_text_string.sh > ./MYBUG
          cd - >/dev/null || exit 1
        fi
        TEXT="$(cat ./${TRIAL}/node${SUBDIR}/MYBUG | head -n1 | sed 's|"|\\\\"|g')"  # Ref TODO above
        check_if_asan_or_ubsan_or_tsan ${SUBDIR}
        if [ "${MULTI}" == "1" ]; then
           if [ -s ${RUNDIR}/${TRIAL}/node${SUBDIR}/${TRIAL}.sql.failing ];then
             auto_interleave_failing_sql ${INPUTFILE}
           fi
        fi
        if [ ! -z "$(echo "${TEXT}" | grep -i "No .* found")" -a ! -z "$(ls ${RUNDIR}/${TRIAL}/ERROR_LOG_SCAN_ISSUE ${RUNDIR}/${TRIAL}/node*/ERROR_LOG_SCAN_ISSUE 2>/dev/null)" ]; then
          echo "* TEXT variable will be set to the error log issue discovered for/in this trial (ref next line)"
        else
          echo "* TEXT variable set to: '${TEXT}'"
        fi
        add_failing_and_trigger_queries_to_trace
        remove_non_sql_from_trace ${INPUTFILE}
        generate_reducer_script
        if [ "${MYEXTRA}" != "" ]; then
          echo "* MYEXTRA variable set to: ${MYEXTRA}"
        fi
        if [ "${WSREP_PROVIDER_OPTIONS}" != "" ]; then
          echo "* WSREP_PROVIDER_OPTIONS variable set to: ${WSREP_PROVIDER_OPTIONS}"
        fi
        if [[ ${VALGRIND_CHECK} -eq 1 ]]; then
          echo "* Valgrind was used for this trial"
        fi
        echo "Trial analysis complete. Reducer created: ${PWD}/reducer${TRIAL}-${SUBDIR}.sh"
      done
    done
  else
    for SQLLOG in $(ls ./*/*thread-0.sql 2>/dev/null); do
      TRIAL=`echo ${SQLLOG} | sed 's|./||;s|/.*||'`
      REPL_EXTRA=
      MASTER_EXTRA=
      SLAVE_EXTRA=
      if [ -r ./${TRIAL}/REPLICATION_ACTIVE ]; then  # This was a replication based run
        if [ -r ./${TRIAL}/REPL_EXTRA ]; then
          REPL_EXTRA="$(cat ./${TRIAL}/REPL_EXTRA 2>/dev/null)"
        fi
        if [ -r ./${TRIAL}/MASTER_EXTRA ]; then
          MASTER_EXTRA="$(cat ./${TRIAL}/MASTER_EXTRA 2>/dev/null)"
        fi
        if [ -r ./${TRIAL}/SLAVE_EXTRA ]; then
          SLAVE_EXTRA="$(cat ./${TRIAL}/SLAVE_EXTRA 2>/dev/null)"
        fi
      fi
      MYEXTRA=
      if [ -r ./${TRIAL}/MYEXTRA ]; then
        MYEXTRA=$(cat ./${TRIAL}/MYEXTRA 2>/dev/null)
      else
        echo "Warning: no MYEXTRA file found for trial ${TRIAL} (./${TRIAL}/MYEXTRA). This should not be the case, unless this run ran out of diskspace"
      fi
      MYINIT=
      if [ -r ./${TRIAL}/MYINIT ]; then
        MYINIT=$(cat ./${TRIAL}/MYINIT 2>/dev/null)
      fi
      if [ ${MDG} -eq 0 ]; then
        OUTFILE=$TRIAL
        rm -Rf ${RUNDIR}/${TRIAL}/${TRIAL}.sql.failing
        touch ${RUNDIR}/${TRIAL}/${TRIAL}.sql.failing
        if [ ${REACH} -eq 0 ]; then # Avoid normal output if this is an automated run (REACH=1)
          echo "========== Processing pquery trial ${TRIAL} in ${RUNDIR}"
        fi
        if [ ! -r ./${TRIAL}/start ]; then
          echo "* No ./${TRIAL}/start detected, so this was likely a SAVE_SQL=1, SAVE_TRIALS_WITH_CORE_ONLY=1 trial with no core generated. Skipping to next trial."
          continue
        fi
        if [ -r ./reducer${TRIAL}.sh ]; then
          echo "* Reducer for this trial (./reducer${TRIAL}.sh) already exists. Skipping to next trial."
          continue
        fi
        if [ "${MULTI}" == "1" ]; then
          INPUTFILE=${RUNDIR}/${TRIAL}/${TRIAL}.sql
          if [ ! -r ${INPUTFILE}.backup ]; then
            cp ${INPUTFILE} ${INPUTFILE}.backup
          else
            cp ${INPUTFILE}.backup ${INPUTFILE}  # Reset ${INPUTFILE} file contents (avoids the file getting larger every time this script is executed due to auto_interleave_failing_sql() being called again.
          fi
        else
          INPUTFILE=`echo ${SQLLOG} | sed "s|^[./]\+|/|;s|^|${RUNDIR}|"`
        fi
        BIN=$(grep --binary-files=text "\/mariadbd" ./${TRIAL}/start | head -n1 | sed 's|mariadbd .*|mariadbd|;s|.* \(.*bin/mariadbd\)|\1|')
        if [ -z "${BIN}" ]; then
          BIN=$(grep --binary-files=text "\/mysqld" ./${TRIAL}/start | head -n1 | sed 's|mysqld .*|mysqld|;s|.* \(.*bin/mysqld\)|\1|')
          if [ -z "${BIN}" -o ! -r "${BIN}" ]; then  # Check if we can obtain bin from the pquery-run.sh log in case BIN is still empty, or is not empty/set but cannot be read at this point (TBD: check if this works correctly given that normally there is an 'exit 1' (ref below) when BIN cannot be read. It should work as in this codeblock we add a '-r' as well, and the BIN var is only changed if it can be -r read)  # 8-Feb-24 RV
            if [ -r ./pquery-run.log ]; then
              TEST_BASE="$(grep -io --binary-files=text 'Basedir:.*' pquery-run.log 2>/dev/null | sed 's|^.*[ \t]*:[ \t]*||')"
              if [ ! -z "${TEST_BASE}" ]; then
                if [ -r "${TEST_BASE}/bin/mariadbd" ]; then
                  BIN="${TEST_BASE}/bin/mariadbd"
                elif [ -r "${TEST_BASE}/bin/mysqld" ]; then
                  BIN="${TEST_BASE}/bin/mysqld"
                fi
              fi
              TEST_BASE=
            fi
            if [ -z "${BIN}" ]; then
              echo "Assert \$BIN is empty for trial $TRIAL, please fix this trial manually"
              continue
            fi
          fi
        fi
        if [ ! -r "${BIN}" ]; then
          ALT_DATA_BIN="$(echo "${BIN}" | sed 's|^/test|/data/VARIOUS_BUILDS|')"
          if [ -r "${ALT_DATA_BIN}" ]; then
            BIN=${ALT_DATA_BIN}
          else
            echo "Assert! mariadbd/mysqld binary '${BIN}' could not be read. The script also checked: '${ALT_DATA_BIN}' which was equally unavailable"
            CHECK_TARS_DIR_GZ="$(echo "${BIN}" | sed 's|^/test/|/data/TARS/|;s|/bin/.*|.tar.gz|')"
            if [ -r "${CHECK_TARS_DIR_GZ}" ]; then
              echo "Note: A ${CHECK_TARS_DIR_GZ} tarball was found; you may like to decompress that file (and rename the resulting extracted directory to match the directory name in /test), and retry"
            fi
            exit 1
          fi
          ALT_DATA_BIN=
        fi
        BASE="$(echo ${BIN} | sed 's|/bin/mariadbd||;s|/bin/mysqld||')"
        if [ ! -d "${BASE}" ]; then
          echo "Assert! Basedir '${BASE}' does not look to be a directory"
          exit 1
        fi
        add_failing_and_trigger_queries_to_trace
        remove_non_sql_from_trace ${INPUTFILE}
        # Check if this trial was/had a startup failure (which would take priority over anything else) - will be used to set REDUCE_STARTUP_ISSUES=1
        check_if_startup_failure
        VALGRIND_CHECK=0
        VALGRIND_ERRORS_FOUND=0; VALGRIND_CHECK_1=
        if [ -r ./${TRIAL}/VALGRIND -a ${VALGRIND_OVERRIDE} -ne 1 ]; then
          VALGRIND_CHECK=1
          # What follows are 3 different ways of checking if Valgrind issues were seen, mostly to ensure that no Valgrind issues go unseen, especially if log is not complete
          VALGRIND_CHECK_1=$(grep --binary-files=text "==[0-9]\+== ERROR SUMMARY: [0-9]\+ error" ./${TRIAL}/log/master.err 2>/dev/null | sed 's|.*ERROR SUMMARY: \([0-9]\+\) error.*|\1|')
          if [ "${VALGRIND_CHECK_1}" == "" ]; then VALGRIND_CHECK_1=0; fi
          if [ ${VALGRIND_CHECK_1} -gt 0 ]; then
            VALGRIND_ERRORS_FOUND=1
          fi
          if egrep --binary-files=text -qi "^[ \t]*==[0-9]+[= \t]+[atby]+[ \t]*0x" ./${TRIAL}/log/master.err  2>/dev/null; then
            VALGRIND_ERRORS_FOUND=1
          fi
          if egrep --binary-files=text -qi "==[0-9]+== ERROR SUMMARY: [1-9]" ./${TRIAL}/log/master.err 2>/dev/null; then
            VALGRIND_ERRORS_FOUND=1
          fi
          if [ ${VALGRIND_ERRORS_FOUND} -eq 1 ]; then
            TEXT="$(${SCRIPT_PWD}/valgrind_string.sh ./${TRIAL}/log/master.err  2>/dev/null)"
            if [ "${TEXT}" != "" ]; then
              echo "* Valgrind string detected: '${TEXT}'"
            else
              echo "*** ERROR: No specific Valgrind string was detected in ./${TRIAL}/log/master.err! This may be a bug... Setting TEXT to generic '==    at 0x'"
              TEXT="==    at 0x"
            fi
            # generate a valgrind specific reducer and then reset values if standard crash reducer is needed
            OUTFILE=_val$TRIAL
            generate_reducer_script
            VALGRIND_CHECK=0
            OUTFILE=$TRIAL
          fi
        fi
        # if not a valgrind run process everything, if it is valgrind run only if there's a core
        if [ ! -r ./${TRIAL}/VALGRIND ] || [ -r ./${TRIAL}/VALGRIND -a ! -z "$(ls -t --color=never data*/*core* node*/*core* 2>/dev/null)" ]; then
          if [ ! -r ./${TRIAL}/MYBUG ]; then  # Sometimes (approx 1/75 trials) MYBUG is missing, so [re-]generate it. TODO: find reason (in pquery-run.sh likely)
            cd ./${TRIAL} || exit 1
            ${SCRIPT_PWD}/new_text_string.sh > ./MYBUG
            cd - >/dev/null || exit 1
          fi
          TEXT="$(cat ./${TRIAL}/MYBUG | sed 's|"|\\\\"|g')"  # The sed transforms " to \" to avoid TEXT containing doube quotes in reducer.sh. This works correctly, even though TEXT is set to "some text \" some text \" some text" in reducer.sh. i.e. bugs are reduced correctly.
          if [[ "${TEXT}" == "Assert:"* ]]; then  # Try to re-generate MYBUG in case something went amiss during pquery-run.sh (i.e. when 'Assert:' is seen in MYBUG)
            cd ./${TRIAL} || exit 1
            ${SCRIPT_PWD}/new_text_string.sh > ./MYBUG
            cd - >/dev/null || exit 1
          fi
          TEXT="$(cat ./${TRIAL}/MYBUG | sed 's|"|\\\\"|g')"  # As above
          check_if_asan_or_ubsan_or_tsan
          if [ "$(echo "${TEXT}" | wc -l)" != "1" ]; then
            echo "Assert: TEXT does not exactly contain one line only! TEXT seen (with newlines removed): '$(echo "${TEXT}" | tr '\n' ' ')'"
            TEXT_MULTI="${TEXT}"
            TEXT="Assert: multi-line TEXT found! Check and fix scripts please. TEXT seen (with newlines removed): '$(echo "${TEXT_MULTI}" | tr '\n' ' ')'"
            TEXT_MULTI=
          fi
          if [ ! -z "$(echo "${TEXT}" | grep -i "No .* found")" -a ! -z "$(ls ${RUNDIR}/${TRIAL}/ERROR_LOG_SCAN_ISSUE ${RUNDIR}/${TRIAL}/node*/ERROR_LOG_SCAN_ISSUE 2>/dev/null)" ]; then
            echo "* TEXT variable will be set to the error log issue discovered for/in this trial (ref next line)"
          else
            echo "* TEXT variable set to: '${TEXT}'"
          fi
          if [ "${MULTI}" == "1" -a -s ${RUNDIR}/${TRIAL}/${TRIAL}.sql.failing ];then
            auto_interleave_failing_sql ${INPUTFILE}
          fi
          generate_reducer_script
        fi
      fi
      if [ "${MYEXTRA}" != "" ]; then
        echo "* MYEXTRA variable set to: ${MYEXTRA}"
      fi
      if [ ${VALGRIND_CHECK} -eq 1 ]; then
        echo "* Valgrind was used for this trial"
      fi
    done
  fi
else
  for TRIAL in $(ls ./*/diff.result 2>/dev/null | sed 's|./||;s|/.*||'); do
    BIN=$(grep --binary-files=text "\/mariadbd" ./${TRIAL}/start | head -n1 | sed 's|mariadbd .*|mariadbd|;s|.* \(.*bin/mariadbd\)|\1|')
    if [ -z "${BIN}" ]; then
      BIN=$(grep --binary-files=text "\/mysqld" ./${TRIAL}/start | head -n1 | sed 's|mysqld .*|mysqld|;s|.* \(.*bin/mysqld\)|\1|')
      if [ -z "${BIN}" ]; then
        echo "Assert \$BIN is empty"
        continue
      fi
    fi
    if [ ! -r "${BIN}" ]; then
      echo "Assert! mariadbd/mysqld binary '${BIN}' could not be read"
      exit 1
    fi
    BASE="$(echo ${BIN} | sed 's|/bin/mariadbd||;s|/bin/mysqld||')"
    if [ ! -d "${BASE}" ]; then
      echo "Assert! Basedir '${BASE}' does not look to be a directory"
      exit 1
    fi
    TEXT="$(grep --binary-files=text "^[<>]" ./${TRIAL}/diff.result | awk '{print length, $0;}' | sort -nr | head -n1 | sed 's/^[0-9]\+[ \t]\+//')"
    LEFTRIGHT=$(echo ${TEXT} | sed 's/\(^.\).*/\1/')
    TEXT="$(echo ${TEXT} | sed 's/[<>][ \t]\+//')"
    ENGINE=
    FAULT=0
    # Pre-processing all possible sql files to make it suitable for reducer.sh and manual replay - this can be handled in pquery core < TODO
    sed -i "s/;|NOERROR/;#NOERROR/" ${RUNDIR}/${TRIAL}/*_thread-0.*.sql
    sed -i "s/;|ERROR/;#ERROR/" ${RUNDIR}/${TRIAL}/*_thread-0.*.sql
    REPL_EXTRA=
    MASTER_EXTRA=
    SLAVE_EXTRA=
    if [ -r ./${TRIAL}/REPLICATION_ACTIVE ]; then  # This was a replication based run
      if [ -r ./${TRIAL}/REPL_EXTRA ]; then
        REPL_EXTRA="$(cat ./${TRIAL}/REPL_EXTRA 2>/dev/null)"
      fi
      if [ -r ./${TRIAL}/MASTER_EXTRA ]; then
        MASTER_EXTRA="$(cat ./${TRIAL}/MASTER_EXTRA 2>/dev/null)"
      fi
      if [ -r ./${TRIAL}/SLAVE_EXTRA ]; then
        SLAVE_EXTRA="$(cat ./${TRIAL}/SLAVE_EXTRA 2>/dev/null)"
      fi
    fi
    MYINIT=
    if [ -r ./${TRIAL}/MYINIT ]; then
      MYINIT=$(cat ./${TRIAL}/MYINIT 2>/dev/null)
    fi
    if [ "${LEFTRIGHT}" == "<" ]; then
      ENGINE=$(cat ./${TRIAL}/diff.left)
      MYEXTRA=
      if [ -r ./${TRIAL}/MYEXTRA.left ]; then
        MYEXTRA=$(cat ./${TRIAL}/MYEXTRA.left 2>/dev/null)
      else
        echo "Warning: no MYEXTRA.left file found for trial ${TRIAL} (./${TRIAL}/MYEXTRA.left). This should not be the case, unless this run ran out of diskspace"
      fi
    elif [ "${LEFTRIGHT}" == ">" ]; then
      ENGINE=$(cat ./${TRIAL}/diff.right)
      MYEXTRA=
      if [ -r ./${TRIAL}/MYEXTRA.right ]; then
        MYEXTRA=$(cat ./${TRIAL}/MYEXTRA.right 2>/dev/null)
      else
        echo "Warning: no MYEXTRA.right file found for trial ${TRIAL} (./${TRIAL}/MYEXTRA.right). This should not be the case, unless this run ran out of diskspace"
      fi
    else
      # Possible reasons for this can be: interrupted or crashed trial, ... ???
      echo "Warning! \$LEFTRIGHT != '<' or '>' but '${LEFTRIGHT}' for trial ${TRIAL}! NOTE: qcreducer${TRIAL}.sh will not be complete: renaming to qcreducer${TRIAL}_notcomplete.sh!"
      FAULT=1
    fi
    if [ ${FAULT} -ne 1 ]; then
      QCTEXTLN=$(echo "${TEXT}" | grep --binary-files=text -o "[0-9]*$")
      TEXT="$(echo ${TEXT} | sed "s/#[0-9]*$//")"
      QCTEXT="$(sed -n "${QCTEXTLN},${QCTEXTLN}p" ${RUNDIR}/${TRIAL}/*_thread-0.${ENGINE}.sql | grep --binary-files=text -o "#@[0-9]*#")"
    fi
    # Output of the following is too verbose
    #if [ "${MYEXTRA}" != "" ]; then
    #  echo "* MYEXTRA variable set to: ${MYEXTRA}"
    #fi
    INPUTFILE=$(echo ${TRIAL} | sed "s|^|${RUNDIR}/|" | sed "s|$|/*_thread-0.${ENGINE}.sql|")
    echo "* Query Correctness: Data Correctness (QC DC) TEXT variable for trial ${TRIAL} set to: \"${TEXT}\""
    # TODO: TEMPORARILY DISABLED THIS; re-review QCTEXT variable functionality later. Also see change at [*]
    #echo "* Query Correctness: Line Identifier (QC LI) QCTEXT variable for trial ${TRIAL} set to: \"${QCTEXT}\""
    OUTFILE=$TRIAL
    generate_reducer_script
    if [ ${FAULT} -eq 1 ]; then
      mv ./qcreducer${TRIAL}.sh ./qcreducer${TRIAL}_notcomplete.sh
    fi
  done
fi

# Process shutdown timeout issues correctly
# * Checking for a coredump ensures that there was no coredump found in the trial's directory, which would mean that this is not a shutdown issue
# * The check for ${MATCHING_TRIAL}/SHUTDOWN_TIMEOUT_ISSUE ensures that the issue was a shutdown issue
# * Also check that this is not a MEMORY_NOT_FREED issue
# If these 3 all apply, it is safe to change the MODE to =0 and assume that this is a shutdown issue only
echo '========== Processing SHUTDOWN_TIMEOUT_ISSUE trials (if any)'
for MATCHING_TRIAL in `grep --binary-files=text -H "^MODE=[0-9]$" reducer* 2>/dev/null | awk '{print $1}' | sed 's|:.*||;s|[^0-9]||g' | sort -un` ; do
  if [ -r ${MATCHING_TRIAL}/SHUTDOWN_TIMEOUT_ISSUE ]; then  # Only deal with shutdown timeout issues!
    if [ $(grep -m1 --binary-files=text "=ERROR:" ${MATCHING_TRIAL}/log/master.err ${TRIAL}/node*/node*.err 2>/dev/null | wc -l) -gt 0 -o "${SAN_BUG}" -eq 1 ]; then  # SAN issue: do not set MODE=0
      echo "* Trial ${MATCHING_TRIAL} found to be a SHUTDOWN_TIMEOUT_ISSUE trial, however a SAN issue was [also] present"
      echo "  > Removing ${MATCHING_TRIAL}/SHUTDOWN_TIMEOUT_ISSUE marker so normal reduction & result presentation can happen"
      rm -f ${MATCHING_TRIAL}/SHUTDOWN_TIMEOUT_ISSUE
      echo "  > Creating ${MATCHING_TRIAL}/AVOID_FORCE_KILL flag to ensure pquery-go-expert does not set FORCE_KILL=1 for this trial"
      touch ${MATCHING_TRIAL}/AVOID_FORCE_KILL
    elif [ $(grep -Em1 --binary-files=text "MEMORY_NOT_FREED|GOT_ERROR|MARKED_AS_CRASHED|MARIADB_ERROR_CODE" ${MATCHING_TRIAL}/MYBUG ${TRIAL}/node*/MYBUG 2>/dev/null | wc -l) -gt 0 ]; then
      echo "* Trial ${MATCHING_TRIAL} found to be a SHUTDOWN_TIMEOUT_ISSUE trial, however another interesting issue was present"
      echo "  > Removing ${MATCHING_TRIAL}/SHUTDOWN_TIMEOUT_ISSUE marker so normal reduction & result presentation can happen"
      rm -f ${MATCHING_TRIAL}/SHUTDOWN_TIMEOUT_ISSUE
      echo "  > Creating ${MATCHING_TRIAL}/AVOID_FORCE_KILL flag to ensure pquery-go-expert does not set FORCE_KILL=1 for this trial"
      touch ${MATCHING_TRIAL}/AVOID_FORCE_KILL
    elif [ $(ls -1 ./${MATCHING_TRIAL}/data/*core* 2>&1 | grep --binary-files=text -v "No such file" | wc -l) -eq 0 ]; then
      echo "* Trial ${MATCHING_TRIAL} found to be a SHUTDOWN_TIMEOUT_ISSUE trial with no core dump nor memory free issue present"
      echo "  > Setting MODE=0, TEXT='', and turning off USE_NEW_TEXT_STRING use"
      sed -i "s|^MODE=[1-9]|MODE=0|" reducer${MATCHING_TRIAL}.sh
      sed -i "s|^   TEXT=.*|TEXT=''|" reducer${MATCHING_TRIAL}.sh
      sed -i "s|^USE_NEW_TEXT_STRING=1|USE_NEW_TEXT_STRING=0|" reducer${MATCHING_TRIAL}.sh
      sed -i "s|^SCAN_FOR_NEW_BUGS=1|SCAN_FOR_NEW_BUGS=0|" reducer${MATCHING_TRIAL}.sh  # Reducer cannot scan for new bugs yet if USE_NEW_TEXT_STRING=0 TODO
    else
      # There was a coredump found in this trial's directory. Thus, this issue should be handled as a non-shutdown problem (i.e. MODE=3 or MODE=4), even though the issue happens on shutdown. Thus: delete the SHUTDOWN_TIMEOUT_ISSUE flag. This basically makes the issue a normal MODE=3 or MODE=4 trial. Simply deleting the flag ensures that it will be listed in the normal crash output results of pquery-results.sh, and not as a 'mysqld Shutdown Issues' (which are joined together and thus would cause many such issues to be auto-deleted when pquery-eliminate-dups runs!). Also create the AVOID_FORCE_KILL flag to ensure reducer uses mysqladmin shutdown which will show the issue in shutdown instead of quick-reducing using FORCE_KILL=1 and thereby missing the issue-on-shutdown
      echo "* Trial ${MATCHING_TRIAL} found to be a SHUTDOWN_TIMEOUT_ISSUE trial, however a core dump was present"
      echo "  > Removing ${MATCHING_TRIAL}/SHUTDOWN_TIMEOUT_ISSUE marker so normal reduction & result presentation can happen"
      rm -f ${MATCHING_TRIAL}/SHUTDOWN_TIMEOUT_ISSUE
      echo "  > Creating ${MATCHING_TRIAL}/AVOID_FORCE_KILL flag to ensure pquery-go-expert does not set FORCE_KILL=1 for this trial"
      touch ${MATCHING_TRIAL}/AVOID_FORCE_KILL
    fi
  fi
done

if [ ${REACH} -eq 0 ]; then # Avoid normal output if this is an automated run (REACH=1)
  echo "======================================================================================================================"
  if [ ${QC} -eq 0 ]; then
    echo -e "\nDone! Start reducer scripts like this: './reducerTRIAL.sh' or './reducer_valTRIAL.sh' where TRIAL stands for the trial number you would like to reduce. Both reducer and the SQL trace file have been pre-prepped with all the crashing queries and settings, ready for you to use without further options!"
  else
    echo -e "\nDone! Start reducer scripts like this: './qcreducerTRIAL.sh' where TRIAL stands for the trial number you would like to reduce"
  fi
  echo -e "\nIMPORTANT! Remember that settings pre-programmed into reducerTRIAL.sh by this script are in the 'Machine configurable variables' section, not in the 'User configurable variables' section. As such, and for example, if you want to change the settings (for example change MODE=3 to MODE=4), then please make such changes in the 'Machine configurable variables' section which is a bit lower in the file (search for 'Mac' to find it easily). Any changes you make in the 'User configurable variables' section will not take effect as the Machine sections overwrites these!"
  echo -e "\nIMPORTANT! Remember that a number of testcases as generated by reducer.sh will require the MYEXTRA mysqld options used in the original test. The reducer<nr>.sh scripts already have these set, but when you want to replay a testcase in some other mysqld setup, remember you will need these options passed to mysqld directly or in some my.cnf script. Note also, in reverse, that the presence of certain mysqld options that did not form part of the original test can cause the same effect; non-reproducibility of the testcase. You want a replay setup as closely matched as possible. If you use the new scripts (./{epoch}_init, _start, _stop, _cl, _run, _run-pquery, _stop etc. then these options for mysqld will already be preset for you."
fi
