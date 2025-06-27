#!/bin/bash
# Created by Roel Van de Paar, MariaDB

# This script generates a UniqueID for the first ASAN, LSAN, UBSAN, TSAN or MSAN error seen in a given mysqld/mariadbd 
# error log after the 'ready for connections' string is seen. If the string is not present, the scan starts from line #1

# Usage: ~/mariadb-qa/san_text_string.sh ${1}
# ${1}: First input, only option, point to mysqld error log directly, or to a basedir which contains ./log/master.err
#       If the option is not specified, the script will attempt to look in ${PWD}/log/master.err and ${PWD}/master.err

# To 1) aid automation, and as 2) subsequent errors may be the result of former ones, and as 3) subsequent errors may
# be standalone errors which can (and likely will, provided the random spread is wide enough) show in other test trials,
# the script will output only the first FULL issue detected (whetter it be ASAN, UBSAN, TSAN or MSAN).

# "FULL": the first issue the script can parse into a full UniqueID. Thus, if there is a partial UBSAN failure observed
# followed by a fully readable ASAN failure, the ASAN's failure UniqueID will be output. This solution is better than
# not outputing anything when the first failure is only partially readable, as herewith testcase reduction can happen
# against the second FULL failure observed (i.e. a benefit gained). One caveat is that the partial issue may be lost,
# though often times a given issue may show up in other ways, etc.

# Note that we scan for issues only after 'ready for connections' is seen. There may be other issues seen during
# server init, which may be sporadic and may be connected to only a single version. This greatly simplifies issue
# handling, as otherwise tools like './allstrings SAN' (and therefore '~/b SAN' (bug report) output also) may list
# UniqueID's seen during startup etc., which are otherwise completely unrelated to the issue being scanned for, which
# may lead in turn (in error) to UniqueID's unrelated to a particular issue ending up in the known bugs UniqueID's list.
# However, if 'ready for connections' is not seen in the log, the scanning starts at line #1 which may or may not # lead to unexpected results.

set +H
PROFILING=0  # Set to 1 to profile Bash to /tmp/bashstart.$$.log (slows down script by a factor of 10x)

help_info(){
  echo "Usage:"
  echo "1] If you want to point the script to a specific error log in a specific location, do:"
  echo "   ~/mariadb-qa/san_text_string.sh your_error_log_location"
  echo "   Where your_error_log_location points to such a specific error log in a specific location."
  echo "2] If you want to point the script to a base directory which already contains ./log/master.err, do:"
  echo "   ~/mariadb-qa/san_text_string.sh your_base_directory"
  echo "   Where your_base_directory is a base directory which already contains ./log/master.err"
  echo "3] If you are within a base directory which already contains a ./log/master.err, do:"
  echo "   ~/mariadb-qa/san_text_string.sh"
  echo "   Without any options, as this will automatically use \${PWD}/log/master.err"
}

# Profiling
if [ "${PROFILING}" -eq 1 ]; then
  PS4='+ $(date "+%s.%N")\011 '
  exec 3>&2 2>/tmp/bashstart.$$.log
  set -x
fi

# Variable and error log dir/file checking
ERROR_LOGS=
if [ -z "${1}" ]; then
  ERROR_LOGS="$(echo "${PWD}/log/master.err")"
  if [ ! -r "${ERROR_LOGS}" ]; then  # -r is OK here as it is currently only a single file
    ERROR_LOGS2="$(echo "${PWD}/master.err")"
    if [ ! -r "${ERROR_LOGS2}" ]; then
      echo "Assert: no option passed, and ${ERROR_LOGS} and ${ERROR_LOGS2} do not exist."
      help_info
      exit 1
    else
      ERROR_LOGS="${ERROR_LOGS2}"
      ERROR_LOGS2=
    fi
  fi
  if [ -r "${PWD}/log/slave.err" ]; then
    ERROR_LOGS="${ERROR_LOGS} ${PWD}/log/slave.err"
  elif [ -r "${PWD}/slave.err" ]; then
    ERROR_LOGS="${ERROR_LOGS} ${PWD}/slave.err"
  fi 
fi
if [ -z "${ERROR_LOGS}" ]; then
  if [[ "${1}" == *" "* ]]; then  # Multiple error logs passed, do not check for presence as -r will only work for one error log
    ERROR_LOGS="${1}"
  elif [ -d "${1}" ]; then  # Directory passed, check normal error log location  # TODO: add support for no /log/
    ERROR_LOGS="$(echo "${1}/log/master.err" | sed 's|//|/|g')"
    if [ ! -r "${ERROR_LOGS}" ]; then  # -r is OK here as it is currently only a single file
      echo "Assert: a directory was passed to this script, and ${ERROR_LOGS} does not exist within it."
      help_info
      exit 1
    else
      ERROR_LOGS="${1}"
    fi
    if [ -r "${1}/log/slave.err" ]; then
      ERROR_LOGS="${ERROR_LOGS} ${1}/log/slave.err"
    fi
  elif [ -r "${1}" ]; then
    ERROR_LOGS="${1}"
  else
    echo "Assert: ${1} does not exist."
    help_info
    exit 1
  fi
fi
if [ -z "${ERROR_LOGS}" ]; then  # -o ! -r "${ERROR_LOGS}" removed when ERROR_LOG was changed to ERROR_LOGS, i.e. multi-error log capability
  echo "Assert: this should not happen. '${ERROR_LOGS}' empty. Please debug script and/or option passed."
  exit 1
fi

# Error log verification
ERROR_LOGS_LINES="$(cat ${ERROR_LOGS} 2>/dev/null | wc -l)"  # cat provides streamlined 0-line reporting
if [ -z "${ERROR_LOGS_LINES}" ]; then
  echo "Assert: an attempt to count the number of lines in ${ERROR_LOGS} has yielded and empty result."
  exit 1
fi
if [ "${ERROR_LOGS_LINES}" -eq 0 ]; then
  echo "Assert: the error log at ${ERROR_LOGS} contains 0 lines."
  exit 1
elif [ "${ERROR_LOGS_LINES}" -lt 3 ]; then
  echo "Assert: the error log at ${ERROR_LOGS} contains less then 3 lines."
  exit 1
fi

flag_ready_check(){
  if [ "${FLAG_ASAN_IN_PROGRESS}"  -eq 1 ]; then FLAG_ASAN_READY=1;  else FLAG_ASAN_READY=0;  fi
  if [ "${FLAG_TSAN_IN_PROGRESS}"  -eq 1 ]; then FLAG_TSAN_READY=1;  else FLAG_TSAN_READY=0;  fi
  if [ "${FLAG_UBSAN_IN_PROGRESS}" -eq 1 ]; then FLAG_UBSAN_READY=1; else FLAG_UBSAN_READY=0; fi
  if [ "${FLAG_MSAN_IN_PROGRESS}"  -eq 1 ]; then FLAG_MSAN_READY=1;  else FLAG_MSAN_READY=0;  fi
  # Check imposibilties
  if [ "${FLAG_ASAN_READY}" -eq 1 -a "${FLAG_TSAN_READY}" -eq 1 ]; then
    echo "Assert: FLAG_ASAN_READY=1, FLAG_TSAN_READY=1"
    exit 1
  fi
  if [ "${FLAG_TSAN_READY}" -eq 1 -a "${FLAG_UBSAN_READY}" -eq 1 ]; then
    echo "Assert: FLAG_TSAN_READY=1, FLAG_UBSAN_READY=1"
    exit 1
  fi
  if [ "${FLAG_ASAN_READY}" -eq 1 -a "${FLAG_UBSAN_READY}" -eq 1 ]; then
    echo "Assert: FLAG_ASAN_READY=1, FLAG_UBSAN_READY=1"
    exit 1
  fi
  if [ "${FLAG_MSAN_READY}" -eq 1 -a "${FLAG_UBSAN_READY}" -eq 1 ]; then
    echo "Assert: FLAG_MSAN_READY=1, FLAG_UBSAN_READY=1"
    exit 1
  fi
  if [ "${FLAG_MSAN_READY}" -eq 1 -a "${FLAG_TSAN_READY}" -eq 1 ]; then
    echo "Assert: FLAG_MSAN_READY=1, FLAG_TSAN_READY=1"
    exit 1
  fi
  if [ "${FLAG_MSAN_READY}" -eq 1 -a "${FLAG_ASAN_READY}" -eq 1 ]; then
    echo "Assert: FLAG_MSAN_READY=1, FLAG_ASAN_READY=1"
    exit 1
  fi
}

# Preflight check
FLAG_ASAN_PRESENT=0; FLAG_TSAN_PRESENT=0; FLAG_UBSAN_PRESENT=0; FLAG_MSAN_PRESENT=0
if grep -iqE --binary-files=text "=ERROR:|LeakSanitizer:" ${ERROR_LOGS} 2>/dev/null; then  # Note that '=ERROR:' is likely enough as this includes LeakSanitizer. The common error is: ERROR: LeakSanitizer: detected memory leaks
  FLAG_ASAN_PRESENT=1  # Includes LSAN handling
fi
if grep -iq --binary-files=text "ThreadSanitizer:" ${ERROR_LOGS} 2>/dev/null; then
  FLAG_TSAN_PRESENT=1
fi
if grep -iq --binary-files=text "runtime error:" ${ERROR_LOGS} 2>/dev/null; then
  FLAG_UBSAN_PRESENT=1
fi
if grep -iq --binary-files=text "MemorySanitizer:" ${ERROR_LOGS} 2>/dev/null; then
  FLAG_MSAN_PRESENT=1
fi

# Error log scanning & parsing
FLAG_ASAN_IN_PROGRESS=0; FLAG_TSAN_IN_PROGRESS=0; FLAG_UBSAN_IN_PROGRESS=0; FLAG_MSAN_IN_PROGRESS=0
FLAG_ASAN_READY=0; FLAG_TSAN_READY=0; FLAG_UBSAN_READY=0; FLAG_MSAN_READY=0
ASAN_FRAME1=; ASAN_FRAME2=; ASAN_FRAME3=; ASAN_FRAME4=
UBSAN_FRAME1=; UBSAN_FRAME2=; UBSAN_FRAME3=; UBSAN_FRAME4=
ASAN_ERROR=;TSAN_ERROR=;UBSAN_ERROR=;
ASAN_FILE_PREPARSE=;TSAN_FILE_PREPARSE=;UBSAN_FILE_PREPARSE=
LINE_COUNTER=0

# ASAN (and TSAN) file locations are obtained from the stack. UBSAN file locations are obtained from the first line of the UBSAN output.
asan_file_preparse(){
  if [ -z "${ASAN_FILE_PREPARSE}" ]; then
    ASAN_FILE_PREPARSE="$(echo "${LINE}" | sed 's| (BuildId: [0-9a-f]\+)||;s|.* \([^ ]\+\)$|\1|;s|:[0-9]\+:[0-9]\+$||;s|:[0-9]\+$||;s|.*/client/|client/|;s|.*/cmake/|cmake/|;s|.*/dbug/|dbug/|;s|.*/debian/|debian/|;s|.*/extra/|extra/|;s|.*/include/|include/|;s|.*/libmariadb/|libmariadb/|;s|.*/libmysqld/|libmysqld/|;s|.*/libservices/|libservices/|;s|.*/mysql-test/|mysql-test/|;s|.*/mysys/|mysys/|;s|.*/mysys_ssl/|mysys_ssl/|;s|.*/plugin/|plugin/|;s|.*/scripts/|scripts/|;s|.*/sql/|sql/|;s|.*/sql-bench/|sql-bench/|;s|.*/sql-common/|sql-common/|;s|.*/storage/|storage/|;s|.*/strings/|strings/|;s|.*/support-files/|support-files/|;s|.*/tests/|tests/|;s|.*/tpool/|tpool/|;s|.*/unittest/|unittest/|;s|.*/vio/|vio/|;s|.*/win/|win/|;s|.*/wsrep-lib/|wsrep-lib/|;s|.*/zlib/|zlib/|;s|.*/components/|components/|;s|.*/libbinlogevents/|libbinlogevents/|;s|.*/libbinlogstandalone/|libbinlogstandalone/|;s|.*/libmysql/|libmysql/|;s|.*/router/|router/|;s|.*/share/|share/|;s|.*/testclients/|testclients/|;s|.*/utilities/|utilities/|;s|.*/regex/|regex/|;s|/c++/[0-9]\+/|/c++/current_version/|g;')"  # Drop path prefix (build directory), leaving only relevant part for MD/MS
    if [[ "${ASAN_FILE_PREPARSE}" == "("*")" ]]; then
      # The location is a non-resolved maridbd/mysqld location (i.e. /bin/mariadbd+0x81e8edf), and not helpful - get it from the next frame
      ASAN_FILE_PREPARSE=''
    fi
  fi
}
tsan_file_preparse(){
  if [ -z "${TSAN_FILE_PREPARSE}" ]; then
    TSAN_FILE_PREPARSE="$(echo "${LINE}" | sed 's| (BuildId: [0-9a-f]\+)||;s|:[^:]*$||;s|:[0-9]\+:[0-9]\+:[ ]*$||;s|.*/client/|client/|;s|.*/cmake/|cmake/|;s|.*/dbug/|dbug/|;s|.*/debian/|debian/|;s|.*/extra/|extra/|;s|.*/include/|include/|;s|.*/libmariadb/|libmariadb/|;s|.*/libmysqld/|libmysqld/|;s|.*/libservices/|libservices/|;s|.*/mysql-test/|mysql-test/|;s|.*/mysys/|mysys/|;s|.*/mysys_ssl/|mysys_ssl/|;s|.*/plugin/|plugin/|;s|.*/scripts/|scripts/|;s|.*/sql/|sql/|;s|.*/sql-bench/|sql-bench/|;s|.*/sql-common/|sql-common/|;s|.*/storage/|storage/|;s|.*/strings/|strings/|;s|.*/support-files/|support-files/|;s|.*/tests/|tests/|;s|.*/tpool/|tpool/|;s|.*/unittest/|unittest/|;s|.*/vio/|vio/|;s|.*/win/|win/|;s|.*/wsrep-lib/|wsrep-lib/|;s|.*/zlib/|zlib/|;s|.*/components/|components/|;s|.*/libbinlogevents/|libbinlogevents/|;s|.*/libbinlogstandalone/|libbinlogstandalone/|;s|.*/libmysql/|libmysql/|;s|.*/router/|router/|;s|.*/share/|share/|;s|.*/testclients/|testclients/|;s|.*/utilities/|utilities/|;s|.*/regex/|regex/|;s|.*/tsan/|tsan/|;s|/c++/[0-9]\+/|/c++/current_version/|g;')"  # Drop path prefix (build directories), leaving only relevant part for MD/MS
    if [[ "${TSAN_FILE_PREPARSE}" == "("*")" ]]; then
      # The location is a non-resolved maridbd/mysqld location (i.e. /bin/mariadbd+0x81e8edf), and not helpful - get it from the next frame
      TSAN_FILE_PREPARSE=''
    fi
    if [[ "${TSAN_FILE_PREPARSE}" == "tsan/"* ]]; then
      # The location is a tsan location (for example: tsan/tsan_interface_atomic.cpp with frame tsan_atomic64_fetch_add) and likely not as helpful as a mysqld function which can likely be retrieved from the next frame
      TSAN_FILE_PREPARSE=''
    fi
  fi
}
msan_file_preparse(){
  if [ -z "${MSAN_FILE_PREPARSE}" ]; then
    MSAN_FILE_PREPARSE="$(echo "${LINE}" | sed 's| (BuildId: [0-9a-f]\+)||;s|:[^:]*$||;s|:[0-9]\+:[0-9]\+:[ ]*$||;s|:[0-9]\+$||;s|.*/client/|client/|;s|.*/cmake/|cmake/|;s|.*/dbug/|dbug/|;s|.*/debian/|debian/|;s|.*/extra/|extra/|;s|.*/include/|include/|;s|.*/libmariadb/|libmariadb/|;s|.*/libmysqld/|libmysqld/|;s|.*/libservices/|libservices/|;s|.*/mysql-test/|mysql-test/|;s|.*/mysys/|mysys/|;s|.*/mysys_ssl/|mysys_ssl/|;s|.*/plugin/|plugin/|;s|.*/scripts/|scripts/|;s|.*/sql/|sql/|;s|.*/sql-bench/|sql-bench/|;s|.*/sql-common/|sql-common/|;s|.*/storage/|storage/|;s|.*/strings/|strings/|;s|.*/support-files/|support-files/|;s|.*/tests/|tests/|;s|.*/tpool/|tpool/|;s|.*/unittest/|unittest/|;s|.*/vio/|vio/|;s|.*/win/|win/|;s|.*/wsrep-lib/|wsrep-lib/|;s|.*/zlib/|zlib/|;s|.*/components/|components/|;s|.*/libbinlogevents/|libbinlogevents/|;s|.*/libbinlogstandalone/|libbinlogstandalone/|;s|.*/libmysql/|libmysql/|;s|.*/router/|router/|;s|.*/share/|share/|;s|.*/testclients/|testclients/|;s|.*/utilities/|utilities/|;s|.*/regex/|regex/|;s|.*/msan/|msan/|;s|/c++/[0-9]\+/|/c++/current_version/|g;s|#[0-9]\+[ ]\+0x[a-f0-9]\+||;s|[ ]\+in[ ]\+||;s|[^ ]\+[ ]\+\([^ ]\+\.[c]\+\)|\1|;')"  # Drop path prefix (build directories), leaving only relevant part for MD/MS
    if [[ "${MSAN_FILE_PREPARSE}" == *"+0x"*")" ]]; then
      # The location is a non-resolved maridbd/mysqld location (i.e. /bin/mariadbd+0x7196fe), and not helpful - get it from the next frame
      MSAN_FILE_PREPARSE=''
    fi
    if [[ "${MSAN_FILE_PREPARSE}" == "msan/"* ]]; then
      # The location is a msan location and likely not as helpful as a mysqld function which can likely be retrieved from the next frame
      MSAN_FILE_PREPARSE=''
    fi
  fi
}

STARTED=0
if ! grep -qi 'ready for connections' ${ERROR_LOGS} 2>/dev/null; then
  # If 'ready for connections' is not present in the input file, start from line #1 as explained above
  STARTED=1
fi
for FILE in ${ERROR_LOGS}; do
  while IFS=$'\n' read -r LINE; do
    LINE_COUNTER=$[ ${LINE_COUNTER} + 1 ]
    LINE="$(echo "${LINE}" | sed 's|(<unknown module>)|<unknown_module>|g')"
    if [ ${STARTED} -eq 0 ]; then
      if [[ "${LINE}" == *"ready for connections"* ]]; then
        STARTED=1
      fi
      continue
    fi
    # ------------- ASAN/LSAN Issue check (if present) -------------
    if [ ${FLAG_ASAN_PRESENT} -eq 1 ]; then
      if [[ "${LINE}" == *"AddressSanitizer:"* || "${LINE}" == *"LeakSanitizer:"* ]]; then  # ASAN or LSAN Issue detected, and commencing (this script handles LSAN issues in the same way as ASAN issues: all references are to ASAN for both ASAN and LSAN issues). Note that for LSAN issues it does not make much sense to include the actual number of bytes lost, as the UniqueID specifically flags a function/backtrace as the issue; this function will get due review/attention by develoment when the bug is reviewed, and thus any bugs present in the function or even area are likely to be fixed. On the other hand, different code paths triggered by different tests may lead to a different amount of bytes lost, leading to wasted QA work for each testcase reduction, as they are all likely to be the same issue (remembering it is the same function that fails, and the function, and the lead-up stack thereunto, are fully included in the UniqueID). Thus, no number of actual bytes lost is tracked. Later in the script it replaces 'ASAN|LeakSanitizer: detected memory leaks' with 'LSAN|memory leak' to make it clearer which issues are LSAN issues.
        flag_ready_check
        FLAG_ASAN_IN_PROGRESS=1; FLAG_TSAN_IN_PROGRESS=0; FLAG_UBSAN_IN_PROGRESS=0; FLAG_MSAN_IN_PROGRESS=0
        ASAN_FRAME1=; ASAN_FRAME2=; ASAN_FRAME3=; ASAN_FRAME4=
        ASAN_FILE_PREPARSE=
        ASAN_ERROR="$(echo "${LINE}" | sed 's|.*ERROR:[ ]*||;s|.*AddressSanitizer:[ ]*||;s| on address.*||;s|thread T[0-9]\+|thread Tx|g;s|allocation size 0x[0-9a-f]\+|allocation size X|g;s|(0x[0-9a-f]\+ after adjustment|(Y after adjustment|g;s|supported size of 0x[0-9a-f]\+|supported size of Z|g;')"
      fi
      if [ "${FLAG_ASAN_IN_PROGRESS}" -eq 1 ]; then
        # Parse first 4 stack frames if discovered in current line
        if [[ "${LINE}" == *" #0 0x"* ]]; then
          ASAN_FRAME1="$(echo "${LINE}" | sed 's|^[^i]\+in[ ]\+||;s|(.*)||g;s|[ ]\+.*||')"
          asan_file_preparse
        fi
        if [[ "${LINE}" == *" #1 0x"* ]]; then
          ASAN_FRAME2="$(echo "${LINE}" | sed 's|^[^i]\+in[ ]\+||;s|(.*)||g;s|[ ]\+.*||')"
          asan_file_preparse
        fi
        if [[ "${LINE}" == *" #2 0x"* ]]; then
          ASAN_FRAME3="$(echo "${LINE}" | sed 's|^[^i]\+in[ ]\+||;s|(.*)||g;s|[ ]\+.*||')"
          asan_file_preparse
        fi
        if [[ "${LINE}" == *" #3 0x"* ]]; then
          ASAN_FRAME4="$(echo "${LINE}" | sed 's|^[^i]\+in[ ]\+||;s|(.*)||g;s|[ ]\+.*||')"
          asan_file_preparse
          FLAG_ASAN_READY=1
        fi
      fi
    fi
    # ------------- UBSAN Issue check (if present) -------------
    if [ ${FLAG_UBSAN_PRESENT} -eq 1 ]; then
      if [[ "${LINE}" == *"runtime error:"* ]]; then  # UBSAN Issue detected, and commencing
        flag_ready_check
        FLAG_ASAN_IN_PROGRESS=0; FLAG_TSAN_IN_PROGRESS=0; FLAG_UBSAN_IN_PROGRESS=1; FLAG_MSAN_IN_PROGRESS=0
        UBSAN_FRAME1=; UBSAN_FRAME2=; UBSAN_FRAME3=; UBSAN_FRAME4=
        UBSAN_FILE_PREPARSE="$(echo "${LINE}" | sed 's| (BuildId: [0-9a-f]\+)||;s| runtime error:.*||;s|:[0-9]\+:[0-9]\+:[ ]*$||;s|.*/client/|client/|;s|.*/cmake/|cmake/|;s|.*/dbug/|dbug/|;s|.*/debian/|debian/|;s|.*/extra/|extra/|;s|.*/include/|include/|;s|.*/libmariadb/|libmariadb/|;s|.*/libmysqld/|libmysqld/|;s|.*/libservices/|libservices/|;s|.*/mysql-test/|mysql-test/|;s|.*/mysys/|mysys/|;s|.*/mysys_ssl/|mysys_ssl/|;s|.*/plugin/|plugin/|;s|.*/scripts/|scripts/|;s|.*/sql/|sql/|;s|.*/sql-bench/|sql-bench/|;s|.*/sql-common/|sql-common/|;s|.*/storage/|storage/|;s|.*/strings/|strings/|;s|.*/support-files/|support-files/|;s|.*/tests/|tests/|;s|.*/tpool/|tpool/|;s|.*/unittest/|unittest/|;s|.*/vio/|vio/|;s|.*/win/|win/|;s|.*/wsrep-lib/|wsrep-lib/|;s|.*/zlib/|zlib/|;s|.*/components/|components/|;s|.*/libbinlogevents/|libbinlogevents/|;s|.*/libbinlogstandalone/|libbinlogstandalone/|;s|.*/libmysql/|libmysql/|;s|.*/router/|router/|;s|.*/share/|share/|;s|.*/testclients/|testclients/|;s|.*/utilities/|utilities/|;s|.*/regex/|regex/|;s|/c++/[0-9]\+/|/c++/current_version/|g;')"  # Drop path prefix (build directory), leaving only relevant part for MD/MS
        UBSAN_ERROR="$(echo "${LINE}" | sed 's|.*runtime error:[ ]*||;s|[-\.\+0-9e]\+ is outside the range|X is outside the range|;s|load of value \(-*\)[0-9]\+|load of value \1X|g;s|negation of \([-]*\)[0-9]\+|negation of \1X|g;s|applying non-zero offset \([-+]*\)[0-9]\+|applying non-zero offset \1X|g;s|overflow: \(-*\)[0-9]\+ \([-+:\*]\) \(-*\)[0-9]\+ |overflow: \1X \2 \3Y |g;s|shift exponent \([-+]*\)[0-9]\+|shift exponent \1X|g;s|index \(-*\)[0-9]\+ out of bounds|index \1X out of bounds|g;s| address 0x[^ ]\+| address X|g;s|with base 0x[0-9a-f]\+|with base X|g;s|overflowed to 0x[0-9a-f]\+|overflowed to Y|g;s| offset to 0x[0-9a-f]\+| offset to X|g;')"
      fi
      if [ "${FLAG_UBSAN_IN_PROGRESS}" -eq 1 ]; then
        # Parse first 4 stack frames if discovered in current line
        if [[ "${LINE}" == *" #0 0x"* ]]; then
          UBSAN_FRAME1="$(echo "${LINE}" | sed 's|^[^i]\+in[ ]\+||;s|(.*)||g;s|[ ]\+.*||')"
        fi
        if [[ "${LINE}" == *" #1 0x"* ]]; then
          UBSAN_FRAME2="$(echo "${LINE}" | sed 's|^[^i]\+in[ ]\+||;s|(.*)||g;s|[ ]\+.*||')"
        fi
        if [[ "${LINE}" == *" #2 0x"* ]]; then
          UBSAN_FRAME3="$(echo "${LINE}" | sed 's|^[^i]\+in[ ]\+||;s|(.*)||g;s|[ ]\+.*||')"
        fi
        if [[ "${LINE}" == *" #3 0x"* ]]; then
          UBSAN_FRAME4="$(echo "${LINE}" | sed 's|^[^i]\+in[ ]\+||;s|(.*)||g;s|[ ]\+.*||')"
          FLAG_UBSAN_READY=1
        fi
      fi
    fi
    # ------------- TSAN Issue check (if present) -------------
    if [ ${FLAG_TSAN_PRESENT} -eq 1 ]; then
      if [[ "${LINE}" == *"ThreadSanitizer:"* ]]; then  # TSAN Issue detected, and commencing
        flag_ready_check
        FLAG_ASAN_IN_PROGRESS=0; FLAG_TSAN_IN_PROGRESS=1; FLAG_UBSAN_IN_PROGRESS=0; FLAG_MSAN_IN_PROGRESS=0
        TSAN_FRAME1=; TSAN_FRAME2=; TSAN_FRAME3=; TSAN_FRAME4=
        TSAN_FILE_PREPARSE=
        TSAN_ERROR="$(echo "${LINE}" | sed 's|.*WARNING:||;s|.*ThreadSanitizer:[ ]*||;s| (pid=.*||')"
      fi
      if [ "${FLAG_TSAN_IN_PROGRESS}" -eq 1 ]; then
        # Parse first 4 stack frames if discovered in current line
        if [[ "${LINE}" == *" #0 "* ]]; then
          TSAN_FRAME1="$(echo "${LINE}" | sed 's|(.*)||g;s|,*#[0-9]\+ ||;s| ||g;s|[\.]\+/.*||;s|/.*||;s|<.*||;')"
          tsan_file_preparse
        fi
        if [[ "${LINE}" == *" #1 "* ]]; then
          TSAN_FRAME2="$(echo "${LINE}" | sed 's|(.*)||g;s|,*#[0-9]\+ ||;s| ||g;s|[\.]\+/.*||;s|/.*||;s|<.*||;')"
          tsan_file_preparse
        fi
        if [[ "${LINE}" == *" #2 "* ]]; then
          TSAN_FRAME3="$(echo "${LINE}" | sed 's|(.*)||g;s|,*#[0-9]\+ ||;s| ||g;s|[\.]\+/.*||;s|/.*||;s|<.*||;')"
          tsan_file_preparse
        fi
        if [[ "${LINE}" == *" #3 "* ]]; then
          TSAN_FRAME4="$(echo "${LINE}" | sed 's|(.*)||g;s|,*#[0-9]\+ ||;s| ||g;s|[\.]\+/.*||;s|/.*||;s|<.*||;')"
          tsan_file_preparse
          FLAG_TSAN_READY=1
        fi
      fi
    fi
    # ------------- MSAN Issue check (if present) -------------
    if [ ${FLAG_MSAN_PRESENT} -eq 1 ]; then
      if [[ "${LINE}" == *"MemorySanitizer:"* ]]; then  # MSAN Issue detected, and commencing
        flag_ready_check
        FLAG_ASAN_IN_PROGRESS=0; FLAG_TSAN_IN_PROGRESS=0; FLAG_UBSAN_IN_PROGRESS=0; FLAG_MSAN_IN_PROGRESS=1
        MSAN_FRAME1=; MSAN_FRAME2=; MSAN_FRAME3=; MSAN_FRAME4=
        MSAN_FILE_PREPARSE=
        MSAN_ERROR="$(echo "${LINE}" | sed 's|.*WARNING:||;s|.*MemorySanitizer:[ ]*||;s| (pid=.*||')"
      fi
      if [ "${FLAG_MSAN_IN_PROGRESS}" -eq 1 ]; then
        # Parse first 4 stack frames if discovered in current line
        if [[ "${LINE}" == *" #0 "* ]]; then
          MSAN_FRAME1="$(echo "${LINE}" | grep -o '[ ]\+in[ ]\+[^ \(\)]\+' | sed 's|[ ]\+in[ ]\+||')"
          msan_file_preparse
        fi
        if [[ "${LINE}" == *" #1 "* ]]; then
          MSAN_FRAME2="$(echo "${LINE}" | grep -o '[ ]\+in[ ]\+[^ \(\)]\+' | sed 's|[ ]\+in[ ]\+||')"
          msan_file_preparse
        fi
        if [[ "${LINE}" == *" #2 "* ]]; then
          MSAN_FRAME3="$(echo "${LINE}" | grep -o '[ ]\+in[ ]\+[^ \(\)]\+' | sed 's|[ ]\+in[ ]\+||')"
          msan_file_preparse
        fi
        if [[ "${LINE}" == *" #3 "* ]]; then
          MSAN_FRAME4="$(echo "${LINE}" | grep -o '[ ]\+in[ ]\+[^ \(\)]\+' | sed 's|[ ]\+in[ ]\+||')"
          msan_file_preparse
          FLAG_MSAN_READY=1
        fi
      fi
    fi
    # ------------- Error log sanity check + EOF handling for in-progress issues -------------
    if [ ${LINE_COUNTER} -eq ${ERROR_LOGS_LINES} ]; then  # End of file reached, check for any final in-progress issues
      flag_ready_check
    elif [ ${LINE_COUNTER} -gt ${ERROR_LOGS_LINES} ]; then
      echo "Assert: LINE_COUNTER > ERROR_LOGS_LINES (${LINE_COUNTER} > ${ERROR_LOGS_LINES})"
      exit 1
    fi
    # ------------- ASAN/LSAN Issue roundup (if present) -------------
    if [ "${FLAG_ASAN_PRESENT}" -eq 1 -a "${FLAG_ASAN_READY}" -eq 1 ]; then
      UNIQUE_ID="ASAN"
      if [ ! -z "${ASAN_ERROR}" ];         then UNIQUE_ID="${UNIQUE_ID}|${ASAN_ERROR}"; fi
      if [ ! -z "${ASAN_FILE_PREPARSE}" ]; then UNIQUE_ID="${UNIQUE_ID}|${ASAN_FILE_PREPARSE}"; fi
      if [ ! -z "${ASAN_FRAME1}" ];        then UNIQUE_ID="${UNIQUE_ID}|${ASAN_FRAME1}"; fi
      if [ ! -z "${ASAN_FRAME2}" ];        then UNIQUE_ID="${UNIQUE_ID}|${ASAN_FRAME2}"; fi
      if [ ! -z "${ASAN_FRAME3}" ];        then UNIQUE_ID="${UNIQUE_ID}|${ASAN_FRAME3}"; fi
      if [ ! -z "${ASAN_FRAME4}" ];        then UNIQUE_ID="${UNIQUE_ID}|${ASAN_FRAME4}"; fi
      UNIQUE_ID="$(echo "${UNIQUE_ID}" | sed 's/ASAN|LeakSanitizer: detected memory leaks/LSAN|memory leak/')"  # LSAN
      # Specific issue (odd stack): LSAN in operator new from dlopen
      if [ "${UNIQUE_ID}" == "LSAN|memory leak|<unknown_module>|operator" ]; then
        if grep -qi 'dlopen' ${ERROR_LOGS} 2>/dev/null; then
          if grep -qi 'plugin_dl_add' ${ERROR_LOGS} 2>/dev/null; then
            if grep -qi 'plugin_dl_foreach' ${ERROR_LOGS} 2>/dev/null; then
              UNIQUE_ID="LSAN|memory leak|sql/sql_plugin.cc|operator new|dlopen|plugin_dl_add|plugin_dl_foreach"
            elif grep -qi 'dl_open_worker' ${ERROR_LOGS} 2>/dev/null; then
              UNIQUE_ID="LSAN|memory leak|sql/sql_plugin.cc|operator new|dl_open_worker|dlopen|plugin_dl_add"
      fi; fi; fi; fi
      echo "${UNIQUE_ID}"
      exit 0
    fi
    # ------------- UBSAN Issue roundup (if present) -------------
    if [ "${FLAG_UBSAN_PRESENT}" -eq 1 -a "${FLAG_UBSAN_READY}" -eq 1 ]; then
      UNIQUE_ID="UBSAN"
      if [ ! -z "${UBSAN_ERROR}" ];         then UNIQUE_ID="${UNIQUE_ID}|${UBSAN_ERROR}"; fi
      if [ ! -z "${UBSAN_FILE_PREPARSE}" ]; then UNIQUE_ID="${UNIQUE_ID}|${UBSAN_FILE_PREPARSE}"; fi
      if [ ! -z "${UBSAN_FRAME1}" ];        then UNIQUE_ID="${UNIQUE_ID}|${UBSAN_FRAME1}"; fi
      if [ ! -z "${UBSAN_FRAME2}" ];        then UNIQUE_ID="${UNIQUE_ID}|${UBSAN_FRAME2}"; fi
      if [ ! -z "${UBSAN_FRAME3}" ];        then UNIQUE_ID="${UNIQUE_ID}|${UBSAN_FRAME3}"; fi
      if [ ! -z "${UBSAN_FRAME4}" ];        then UNIQUE_ID="${UNIQUE_ID}|${UBSAN_FRAME4}"; fi
      echo "${UNIQUE_ID}"
      exit 0
    fi
    # ------------- TSAN Issue roundup (if present) -------------
    if [ "${FLAG_TSAN_PRESENT}" -eq 1 -a "${FLAG_TSAN_READY}" -eq 1 ]; then
      UNIQUE_ID="TSAN"
      if [ ! -z "${TSAN_ERROR}" ];         then UNIQUE_ID="${UNIQUE_ID}|${TSAN_ERROR}"; fi
      if [ ! -z "${TSAN_FILE_PREPARSE}" ]; then UNIQUE_ID="${UNIQUE_ID}|${TSAN_FILE_PREPARSE}"; fi
      if [ ! -z "${TSAN_FRAME1}" ];        then UNIQUE_ID="${UNIQUE_ID}|${TSAN_FRAME1}"; fi
      if [ ! -z "${TSAN_FRAME2}" ];        then UNIQUE_ID="${UNIQUE_ID}|${TSAN_FRAME2}"; fi
      if [ ! -z "${TSAN_FRAME3}" ];        then UNIQUE_ID="${UNIQUE_ID}|${TSAN_FRAME3}"; fi
      if [ ! -z "${TSAN_FRAME4}" ];        then UNIQUE_ID="${UNIQUE_ID}|${TSAN_FRAME4}"; fi
      echo "${UNIQUE_ID}"
      exit 0
    fi
    # ------------- MSAN Issue roundup (if present) -------------
    if [ "${FLAG_MSAN_PRESENT}" -eq 1 -a "${FLAG_MSAN_READY}" -eq 1 ]; then
      UNIQUE_ID="MSAN"
      if [ ! -z "${MSAN_ERROR}" ];         then UNIQUE_ID="${UNIQUE_ID}|${MSAN_ERROR}"; fi
      if [ ! -z "${MSAN_FILE_PREPARSE}" ]; then UNIQUE_ID="${UNIQUE_ID}|${MSAN_FILE_PREPARSE}"; fi
      if [ ! -z "${MSAN_FRAME1}" ];        then UNIQUE_ID="${UNIQUE_ID}|${MSAN_FRAME1}"; fi
      if [ ! -z "${MSAN_FRAME2}" ];        then UNIQUE_ID="${UNIQUE_ID}|${MSAN_FRAME2}"; fi
      if [ ! -z "${MSAN_FRAME3}" ];        then UNIQUE_ID="${UNIQUE_ID}|${MSAN_FRAME3}"; fi
      if [ ! -z "${MSAN_FRAME4}" ];        then UNIQUE_ID="${UNIQUE_ID}|${MSAN_FRAME4}"; fi
      echo "${UNIQUE_ID}"
      exit 0
    fi
  done < ${FILE}
done
 
# Profiling
if [ "${PROFILING}" -eq 1 ]; then
  set +x
  exec 2>&3 3>&-
fi
