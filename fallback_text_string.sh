#!/bin/bash
# Created by Roel Van de Paar, Percona LLC
# Updated by Roel Van de Paar, MariaDB

# Extracts the most relevant string from an error log, in this order:
# 1. Assertion message
# 2. First mangled c++ frame from error log stack (relatively inaccurate), in two different modes: (_ then (
# 3. Filename + line number

# WARNING! If there are multiple crashes/asserts shown in the error log, remove the older ones (or the ones you do not want)

# Possible issue (to be done/researched further); "<" character. If this turns out to be a genuine problem (i.e. reducer not reducing until "<" is removed from TEXT string) then add it below (Swap to '.' dot as usual) + ensure that known_bugs.strings and similar files are updated to change all "<" to "." AND below there is also for example correction of things like 'info->end_of_file' - i.e. if both "<" and ">" are to be changed to "." they need to be updated too in this script. Same for any other references to "<" (and potentially ">") in this script besides known_bugs.strings

ERROR_LOG=$1
if [ "$ERROR_LOG" == "" ]; then
  if [ -f ./log/master.err -a -r ./log/master.err ]; then
    ERROR_LOG=./log/master.err
  elif [ -f ./var/log/mysqld.1.err ]; then
    ERROR_LOG=./var/log/mysqld.1.err
  else
    echo "Assert: no error log file name was passed to fallback_text_string.sh" >&2
    exit 1
  fi
fi

if [ ! -f ${ERROR_LOG} -o ! -a "${ERROR_LOG}" ]; then
  echo "Assert: ${ERROR_LOG} does not exist or could not be read by fallback_text_string.sh" >&2
  exit 1
fi

# The 4 egreps are individual commands executed in a subshell of which the output is then combined and processed further
# Be not misled by the 'libgalera_smm' start of the egrep. note the OR (i.e. '|') in the egreps; mysqld(_ is also scanned for, etc.
# This code block CAN NOT be changed without breaking backward compatibility, unless ALL bugs in known_bugs.strings are re-string'ed
STRING="$(echo "$( \
    egrep --binary-files=text 'Assertion.*failed' $ERROR_LOG | grep --binary-files=text -v 'Assertion .0. failed' | sed 's/|/./g;s/\&/./g;s/"/./g;s/:/./g;s|^.*Assertion .||;s|. failed.*$||;s| |DUMMY|g'; \
    egrep --binary-files=text 'libgalera_smm\.so\(_|mysqld\(_|ha_rocksdb.so\(_|ha_tokudb.so\(_' $ERROR_LOG; \
    egrep --binary-files=text 'libgalera_smm\.so\(|mysqld\(|ha_rocksdb.so\(|ha_tokudb.so\(' $ERROR_LOG | egrep --binary-files=text -v 'mysqld\(_|ha_rocksdb.so\(_|ha_tokudb.so\(_'; \
    egrep --binary-files=text -i 'Assertion failure.*in file.*line' $ERROR_LOG | sed 's|.*in file ||;s|.*/10.[1-9][^/]*/||;s| |DUMMY|g'; \
  )" \
  | tr ' ' '\n' | \
  sed 's|.*libgalera_smm\.so[\(_]*||;s|.*mysqld[\(_]*||;s|.*ha_rocksdb.so[\(_]*||;s|.*ha_tokudb.so[\(_]*||;s|).*||;s|+.*$||;s|DUMMY| |g;s|($||;s|"|.|g;s|\!|.|g;s|&|.|g;s|\*|.|g;s|\]|.|g;s|\[|.|g;s|)|.|g;s|(|.|g' | \
  grep --binary-files=text -v '^[ \t]*$' | \
  head -n1 | sed 's|^[ \t]\+||;s|[ \t]\+$||;' \
)"

poor_strings_check(){
  if [ "${TEST_STRING}" == "" ]; then POOR_STRING=1; fi
  if [ "${TEST_STRING}" == "my_print_stacktrace" ]; then POOR_STRING=1; fi
  if [ "${TEST_STRING}" == "my_print_stacktrace.unsigned" ]; then POOR_STRING=1; fi
  if [ "${TEST_STRING}" == "0" ]; then POOR_STRING=1; fi
  if [ "${TEST_STRING}" == "NULL" ]; then POOR_STRING=1; fi
  if [ "${TEST_STRING}" == "start" ]; then POOR_STRING=1; fi
  if [ "${TEST_STRING}" == "ut_dbg_assertion_failed" ]; then POOR_STRING=1; fi
}

check_better_string(){
  POOR_STRING=0
  TEST_STRING=${POTENTIALLY_BETTER_STRING}
  poor_strings_check
  if [ ${POOR_STRING} -eq 0 ]; then
    STRING=${POTENTIALLY_BETTER_STRING}
  fi
}

# Find a better string if needbe
# This block can be added unto with 'ever deeper nesting if's' - i.e. as long as the output is poor (for the cases covered), more can be done to try and get a better quality string. Adding other "poor outputs" is also possible, though not 100% (as someone may have already added that particular poor output to known_bugs.strings - always check that file first, especially the TEXT=... strings towards the end of that file).
POOR_STRING=0
TEST_STRING=${STRING}
poor_strings_check
if [ ${POOR_STRING} -eq 1 ]; then
  POTENTIALLY_BETTER_STRING="$(grep --binary-files=text 'Assertion failure:' $ERROR_LOG | tail -n1 | sed 's|.*Assertion failure:[ \t]\+||;s|[ \t]+$||;s|.*c:[0-9]\+:||;s/|/./g;s/\&/./g;s/:/./g;s|"|.|g;s|\!|.|g;s|&|.|g;s|\*|.|g;s|\]|.|g;s|\[|.|g;s|)|.|g;s|(|.|g')"
  check_better_string
  if [ ${POOR_STRING} -eq 1 ]; then
    # Last resort; try to get first frame from stack trace in error log in a more basic way
    # This may need some further work, if we start seeing too generic strings like 'do_command', 'parse_sql' etc. text showing in bug list
    POTENTIALLY_BETTER_STRING="$(egrep --binary-files=text -o 'libgalera_smm\.so\(.*|mysqld\(.*|ha_rocksdb.so\(.*|ha_tokudb.so\(.*' $ERROR_LOG | sed 's|[^(]\+(||;s|).*||;s|(.*||;s|+0x.*||' | egrep --binary-files=text -v 'my_print_stacktrace|handle.*signal|^[ \t]*$' | sed 's/|/./g;s/\&/./g;s/:/./g;s|"|.|g;s|\!|.|g;s|&|.|g;s|\*|.|g;s|\]|.|g;s|\[|.|g;s|)|.|g;s|(|.|g' | head -n1)"
    check_better_string
    if [ ${POOR_STRING} -eq 1 ]; then
      # 8.0 runs have somewhat different looking assertions, more may need to be added here
      POTENTIALLY_BETTER_STRING="$(grep --binary-files=text 'Assertion failure:' $ERROR_LOG | tail -n1 | sed 's|.*Assertion failure:[ \t]\+||;s|[ \t]+$||;s/|/./g;s/\&/./g;s/:/./g;s|"|.|g;s|\!|.|g;s|&|.|g;s|\*|.|g;s|\]|.|g;s|\[|.|g;s|)|.|g;s|(|.|g')"
      check_better_string
      # More can be added here, always preceded by:  if [ ${POOR_STRING} -eq 1 ]; then
    fi
  fi
fi

if [ $(echo ${STRING} | wc -l) -gt 1 ]; then
  echo "Assert: TEXT STRING WAS MORE THEN ONE LINE. PLEASE FIX ME (text_string.sh). NOTE; AND, AS PER INSTRUCTIONS IN THE SCRIPT, PLEASE AVOID EDITING THE ORIGINAL CODE BLOCK!" >&2
  exit 1
fi

# Fixup an assert which had a path specifier in it
STRING=$(echo ${STRING} | sed 's|info->end_of_file == inline_mysql_file_tell.*|info->end_of_file == inline_mysql_file_tel|')

# Fixup a common (".all") text string (seen much in error logs, so reducer reduces to 0 lines instead of the bug)
# Normally this would be done by 1) making the look-for TEXT="..." string (...) more specific in reducer, 2) filtering
# it at the end of known_bugs.strings with a TEXT=.....$ (to avoid it matching too generic strings)
if [ "${STRING}" == ".all" ]; then
  if grep --binary-files=text "MYSQL_BIN_LOG..rollback.THD.. bool.. Assertion ..all" $ERROR_LOG 2>/dev/null 1>&2; then  # Always check that it is a specific issue
    STRING="MYSQL_BIN_LOG..rollback.THD.. bool.. Assertion ..all"
  fi
fi

# Fixup a common (".error") text string (ref TEXT=".all" example above for more information on how this is done)
if [ "${STRING}" == ".error" ]; then
  if grep --binary-files=text "virtual uint dd::Dictionary_impl::get_actual_P_S_version(THD.): Assertion ..error' failed" $ERROR_LOG 2>/dev/null 1>&2; then  # Always check that it is a specific issue
    STRING="uint dd..Dictionary_impl..get_actual_P_S_version.THD... Assertion ..error. failed"
  fi
  if grep --binary-files=text "InnoDB: Assertion failure: dict0dd.cc:5.....error$" $ERROR_LOG 2>/dev/null 1>&2; then  # Always check that it is a specific issue
    STRING="dict0dd.cc:5.....error"
  fi
fi

# Fixup an important ("dd_table_discard_tablespace") text string (ref examples above for more information on how this is done)
if [ "${STRING}" == "dd_table_discard_tablespace" ]; then
  if grep --binary-files=text "Cannot find a free slot for an undo log" $ERROR_LOG 2>/dev/null 1>&2; then  # Always check that it is a specific issue
    if grep --binary-files=text "InnoDB: Assertion failure: dict0dd.cc:" $ERROR_LOG 2>/dev/null 1>&2; then  # Always check that it is a specific issue
      STRING="RSEG.....dd_table_discard_tablespace"
    fi
  fi
fi

# Fixup an important ("strcmp.table->name.m_name, table_name. == 0") text string (ref examples above for more information on how this is done)
if [ "${STRING}" == "strcmp.table->name.m_name, table_name. == 0" ]; then
  if grep --binary-files=text "Cannot find a free slot for an undo log" $ERROR_LOG 2>/dev/null 1>&2; then  # Always check that it is a specific issue
    if grep --binary-files=text "InnoDB: Assertion failure: dict0dd.cc:" $ERROR_LOG 2>/dev/null 1>&2; then  # Always check that it is a specific issue
      STRING="RSEG.....strcmp.table->name.m_name, table_name. == 0"
    fi
  fi
fi

# Fixup an important ("strcmp.table->name.m_name, table_name. == 0") text string (ref examples above for more information on how this is done)
if [ "${STRING}" == "status.ok" ]; then
  if grep --binary-files=text "rocksdb::Status rocksdb::BlockCacheTier::Open.*status.ok" $ERROR_LOG 2>/dev/null 1>&2; then  # Always check that it is a specific issue
    STRING="rocksdb::Status rocksdb::BlockCacheTier::Open status.ok"
  fi
fi

# Filter out accidental thread <nr> insertions
STRING=$(echo ${STRING} | sed "s| thread [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]||")

# Filter out accidental path name insertions
STRING=$(echo "${STRING}" | sed "s|/sda/[PM]S[0-9]\+[^ ]\+/bin/mysqld||g")

if [ -z "${STRING}" ]; then
  # The >&2 direction is important as pquery-run.sh redirects stderr output of fallback_text_string.sh to null to avoid any output by fallback_text_string.sh being interpreted as an actual relevant string. All echo's/asserts (and the 'No relevant strings were found' below), except any actual 'FALLBACK|<some bug string>' output should be >&2 redirected, i.e. to stderr. Finally, reducer.sh also redirects stderr output so no output is shown while reducing
  echo "No relevant strings were found in ${ERROR_LOG} by fallback_text_string.sh" >&2
  exit 1
else 
  # Ensure that fallback_text_string.sh string output is clearly indicated by a 'FALLBACK|' marker
  echo "FALLBACK|${STRING}"
  exit 0
fi
