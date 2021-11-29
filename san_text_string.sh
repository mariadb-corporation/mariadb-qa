#!/bin/bash
# Created by Roel Van de Paar, MariaDB

# This script generates a uniqueID for the first ASAN, UBSAN or TSAN error seen in a given mysqld or mariadbd error log
# Usage: ~/mariadb-qa/san_text_string.sh ${1}
# ${1}: First input, only option, point to mysqld error log directly, or to a basedir which contains ./log/master.err
#       If the option is not specified, the script will attempt to look in ${PWD}/log/master.err and ${PWD}/master.err

# To 1) aid automation, and as 2) subsequent errors may be the result of former ones, and as 3) subsequent errors may
# be standalone errors which can (and likely will, provided the random spread is wide enough) show in other test trials,
# the script will output only the first FULL issue detected (whetter it be ASAN, UBSAN or TSAN).

# "FULL": the first issue the script can parse into a full UniqueID. Thus, if there is a partial UBSAN failure observed
# followed by a fully readable ASAN failure, the ASAN's failure UniqueID will be output. This solution is better than 
# not outputing anything when the first failure is only partially readable, as herewith testcase reduction can happen 
# against the second FULL failure observed (i.e. a benefit gained). One caveat is that the partial issue may be lost,
# though often times a given issue may show up in other ways, etc.

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
ERROR_LOG=
if [ -z "${1}" ]; then
  ERROR_LOG="$(echo "${PWD}/log/master.err")"
  if [ ! -r "${ERROR_LOG}" ]; then
    ERROR_LOG2="$(echo "${PWD}/master.err")"
    if [ ! -r "${ERROR_LOG2}" ]; then
      echo "Assert: no option passed, and ${ERROR_LOG} and ${ERROR_LOG2} do not exist."
      help_info
      exit 1
    else
      ERROR_LOG="${ERROR_LOG2}"
      ERROR_LOG2=
    fi
  fi
fi
if [ -z "${ERROR_LOG}" ]; then
  if [ -d "${1}" ]; then  # Directory passed, check normal error log location
    ERROR_LOG="$(echo "${1}/log/master.err" | sed 's|//|/|g')"
    if [ ! -r "${ERROR_LOG}" ]; then
      echo "Assert: a directory was passed to this script, and ${ERROR_LOG} does not exist within it."
      help_info
      exit 1
    fi
  fi
  if [ -r "${1}" ]; then
    ERROR_LOG="${1}"
  else
    echo "Assert: ${1} does not exist."
    help_info
    exit 1
  fi
fi
if [ -z "${ERROR_LOG}" -o ! -r "${ERROR_LOG}" ]; then
  echo "Assert: this should not happen. '${ERROR_LOG}' empty or not readable. Please debug script and/or option passed."
  exit 1
fi

# Error log verification
ERROR_LOG_LINES="$(cat "${ERROR_LOG}" 2>/dev/null | wc -l)"  # cat provides streamlined 0-line reporting
if [ -z "${ERROR_LOG_LINES}" ]; then
  echo "Assert: an attempt to count the number of lines in ${ERROR_LOG} has yielded and empty result."
  exit 1
fi
if [ "${ERROR_LOG_LINES}" -eq 0 ]; then
  echo "Assert: the error log at ${ERROR_LOG} contains 0 lines."
  exit 1
elif [ "${ERROR_LOG_LINES}" -lt 10 ]; then
  echo "Assert: the error log at ${ERROR_LOG} contains less then 10 lines."
  exit 1
fi

flag_ready_check(){
  if [ "${FLAG_ASAN_IN_PROGRESS}"  -eq 1 ]; then FLAG_ASAN_READY=1;  else FLAG_ASAN_READY=0;  fi
  if [ "${FLAG_TSAN_IN_PROGRESS}"  -eq 1 ]; then FLAG_TSAN_READY=1;  else FLAG_TSAN_READY=0;  fi
  if [ "${FLAG_UBSAN_IN_PROGRESS}" -eq 1 ]; then FLAG_UBSAN_READY=1; else FLAG_UBSAN_READY=0; fi
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
}

# Preflight check
FLAG_ASAN_PRESENT=0; FLAG_TSAN_PRESENT=0; FLAG_UBSAN_PRESENT=0
if grep -iq --binary-files=text "=ERROR:" "${ERROR_LOG}"; then
  FLAG_ASAN_PRESENT=1
fi
if grep -iq --binary-files=text "ThreadSanitizer:" "${ERROR_LOG}"; then
  FLAG_TSAN_PRESENT=1
fi
if grep -iq --binary-files=text "runtime error:" "${ERROR_LOG}"; then
  FLAG_UBSAN_PRESENT=1
fi

# Error log scanning & parsing
FLAG_ASAN_IN_PROGRESS=0; FLAG_TSAN_IN_PROGRESS=0; FLAG_UBSAN_IN_PROGRESS=0
FLAG_ASAN_READY=0; FLAG_TSAN_READY=0; FLAG_UBSAN_READY=0
ASAN_FRAME1=; ASAN_FRAME2=; ASAN_FRAME3=; ASAN_FRAME4=
UBSAN_FRAME1=; UBSAN_FRAME2=; UBSAN_FRAME3=; UBSAN_FRAME4=
ASAN_ERROR=;TSAN_ERROR=;UBSAN_ERROR=;
ASAN_FILE_PREPARSE=;TSAN_FILE_PREPARSE=;UBSAN_FILE_PREPARSE=
LINE_COUNTER=0

# ASAN (and TSAN) file locations are obtained from the stack. UBSAN file locations are obtained from the first line of the UBSAN output.
asan_file_preparse(){
  if [ -z "${ASAN_FILE_PREPARSE}" ]; then
    ASAN_FILE_PREPARSE="$(echo "${LINE}" | sed 's|.* \([^ ]\+\)$|\1|;s|:[0-9]\+$||;s|.*/client/|client/|;s|.*/cmake/|cmake/|;s|.*/dbug/|dbug/|;s|.*/debian/|debian/|;s|.*/extra/|extra/|;s|.*/include/|include/|;s|.*/libmariadb/|libmariadb/|;s|.*/libmysqld/|libmysqld/|;s|.*/libservices/|libservices/|;s|.*/mysql-test/|mysql-test/|;s|.*/mysys/|mysys/|;s|.*/mysys_ssl/|mysys_ssl/|;s|.*/plugin/|plugin/|;s|.*/scripts/|scripts/|;s|.*/sql/|sql/|;s|.*/sql-bench/|sql-bench/|;s|.*/sql-common/|sql-common/|;s|.*/storage/|storage/|;s|.*/strings/|strings/|;s|.*/support-files/|support-files/|;s|.*/tests/|tests/|;s|.*/tpool/|tpool/|;s|.*/unittest/|unittest/|;s|.*/vio/|vio/|;s|.*/win/|win/|;s|.*/wsrep-lib/|wsrep-lib/|;s|.*/zlib/|zlib/|;s|.*/components/|components/|;s|.*/libbinlogevents/|libbinlogevents/|;s|.*/libbinlogstandalone/|libbinlogstandalone/|;s|.*/libmysql/|libmysql/|;s|.*/router/|router/|;s|.*/share/|share/|;s|.*/testclients/|testclients/|;s|.*/utilities/|utilities/|;s|.*/regex/|regex/|;')"  # Drop path prefix (build directory), leaving only relevant part for MD/MS
    if [[ "${ASAN_FILE_PREPARSE}" == "("*")" ]]; then
      # The location is a non-resolved maridbd/mysqld location (i.e. /bin/mariadbd+0x81e8edf), and not helpful - get it from the next frame
      ASAN_FILE_PREPARSE=''
    fi
  fi
}
tsan_file_preparse(){
  if [ -z "${TSAN_FILE_PREPARSE}" ]; then
    TSAN_FILE_PREPARSE="$(echo "${LINE}" | sed 's|:[^:]*$||;s|:[0-9]\+:[0-9]\+:[ ]*$||;s|.*/client/|client/|;s|.*/cmake/|cmake/|;s|.*/dbug/|dbug/|;s|.*/debian/|debian/|;s|.*/extra/|extra/|;s|.*/include/|include/|;s|.*/libmariadb/|libmariadb/|;s|.*/libmysqld/|libmysqld/|;s|.*/libservices/|libservices/|;s|.*/mysql-test/|mysql-test/|;s|.*/mysys/|mysys/|;s|.*/mysys_ssl/|mysys_ssl/|;s|.*/plugin/|plugin/|;s|.*/scripts/|scripts/|;s|.*/sql/|sql/|;s|.*/sql-bench/|sql-bench/|;s|.*/sql-common/|sql-common/|;s|.*/storage/|storage/|;s|.*/strings/|strings/|;s|.*/support-files/|support-files/|;s|.*/tests/|tests/|;s|.*/tpool/|tpool/|;s|.*/unittest/|unittest/|;s|.*/vio/|vio/|;s|.*/win/|win/|;s|.*/wsrep-lib/|wsrep-lib/|;s|.*/zlib/|zlib/|;s|.*/components/|components/|;s|.*/libbinlogevents/|libbinlogevents/|;s|.*/libbinlogstandalone/|libbinlogstandalone/|;s|.*/libmysql/|libmysql/|;s|.*/router/|router/|;s|.*/share/|share/|;s|.*/testclients/|testclients/|;s|.*/utilities/|utilities/|;s|.*/regex/|regex/|;s|.*/tsan/|tsan/|;')"  # Drop path prefix (build directories), leaving only relevant part for MD/MS
    if [[ "${TSAN_FILE_PREPARSE}" == "("*")" ]]; then
      # The location is a non-resolved maridbd/mysqld location (i.e. /bin/mariadbd+0x81e8edf), and not helpful - get it from the next frame
      TSAN_FILE_PREPARSE=''
    fi
    if [[ "${TSAN_FILE_PREPARSE}" == "tsan/"* ]]; then
      # The location is a tsan location (i.e. tsan/tsan_interface_atomic.cpp with frame __tsan_atomic64_fetch_add) and likely not as helpful as a mysqld function which can likely be retrieved from the next frame
      TSAN_FILE_PREPARSE=''
    fi
  fi
}

while IFS=$'\n' read LINE; do
  LINE_COUNTER=$[ ${LINE_COUNTER} + 1 ]
  # ------------- ASAN Issue check (if present) -------------
  if [ ${FLAG_ASAN_PRESENT} -eq 1 ]; then
    if [[ "${LINE}" == *"AddressSanitizer:"* ]]; then  # ASAN Issue detected, and commencing
      flag_ready_check
      FLAG_ASAN_IN_PROGRESS=1; FLAG_TSAN_IN_PROGRESS=0; FLAG_UBSAN_IN_PROGRESS=0
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
      FLAG_ASAN_IN_PROGRESS=0; FLAG_TSAN_IN_PROGRESS=0; FLAG_UBSAN_IN_PROGRESS=1
      UBSAN_FRAME1=; UBSAN_FRAME2=; UBSAN_FRAME3=; UBSAN_FRAME4=
      UBSAN_FILE_PREPARSE="$(echo "${LINE}" | sed 's| runtime error:.*||;s|:[0-9]\+:[0-9]\+:[ ]*$||;s|.*/client/|client/|;s|.*/cmake/|cmake/|;s|.*/dbug/|dbug/|;s|.*/debian/|debian/|;s|.*/extra/|extra/|;s|.*/include/|include/|;s|.*/libmariadb/|libmariadb/|;s|.*/libmysqld/|libmysqld/|;s|.*/libservices/|libservices/|;s|.*/mysql-test/|mysql-test/|;s|.*/mysys/|mysys/|;s|.*/mysys_ssl/|mysys_ssl/|;s|.*/plugin/|plugin/|;s|.*/scripts/|scripts/|;s|.*/sql/|sql/|;s|.*/sql-bench/|sql-bench/|;s|.*/sql-common/|sql-common/|;s|.*/storage/|storage/|;s|.*/strings/|strings/|;s|.*/support-files/|support-files/|;s|.*/tests/|tests/|;s|.*/tpool/|tpool/|;s|.*/unittest/|unittest/|;s|.*/vio/|vio/|;s|.*/win/|win/|;s|.*/wsrep-lib/|wsrep-lib/|;s|.*/zlib/|zlib/|;s|.*/components/|components/|;s|.*/libbinlogevents/|libbinlogevents/|;s|.*/libbinlogstandalone/|libbinlogstandalone/|;s|.*/libmysql/|libmysql/|;s|.*/router/|router/|;s|.*/share/|share/|;s|.*/testclients/|testclients/|;s|.*/utilities/|utilities/|;s|.*/regex/|regex/|;')"  # Drop path prefix (build directory), leaving only relevant part for MD/MS
      UBSAN_ERROR="$(echo "${LINE}" | sed 's|.*runtime error:[ ]*||;s|load of value \(-*\)[0-9]\+|load of value \1X|g;s|negation of \([-]*\)[0-9]\+|negation of \1X|g;s|applying non-zero offset \([-+]*\)[0-9]\+|applying non-zero offset \1X|g;s|overflow: \(-*\)[0-9]\+ \([-+:\*]\) \(-*\)[0-9]\+ |overflow: \1X \2 \3Y |g;s|shift exponent \([-+]*\)[0-9]\+|shift exponent \1X|g;s|index \(-*\)[0-9]\+ out of bounds|index \1X out of bounds|g;s|member call on address 0x[^ ]\+|member call on address X|g;s|with base 0x[0-9a-f]\+|with base X|g;s|overflowed to 0x[0-9a-f]\+|overflowed to Y|g')"
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
      FLAG_ASAN_IN_PROGRESS=0; FLAG_TSAN_IN_PROGRESS=1; FLAG_UBSAN_IN_PROGRESS=0
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
  # ------------- Error log sanity check + EOF handling for in-progress issues -------------
  if [ ${LINE_COUNTER} -eq ${ERROR_LOG_LINES} ]; then  # End of file reached, check for any final in-progress issues
    flag_ready_check
  elif [ ${LINE_COUNTER} -gt ${ERROR_LOG_LINES} ]; then
    echo "Assert: LINE_COUNTER > ERROR_LOG_LINES (${LINE_COUNTER} > ${ERROR_LOG_LINES})"
    exit 1
  fi
  # ------------- ASAN Issue roundup (if present) -------------
  if [ "${FLAG_ASAN_PRESENT}" -eq 1 -a "${FLAG_ASAN_READY}" -eq 1 ]; then
    UNIQUE_ID="ASAN"
    if [ ! -z "${ASAN_ERROR}" ];         then UNIQUE_ID="${UNIQUE_ID}|${ASAN_ERROR}"; fi
    if [ ! -z "${ASAN_FILE_PREPARSE}" ]; then UNIQUE_ID="${UNIQUE_ID}|${ASAN_FILE_PREPARSE}"; fi
    if [ ! -z "${ASAN_FRAME1}" ];        then UNIQUE_ID="${UNIQUE_ID}|${ASAN_FRAME1}"; fi
    if [ ! -z "${ASAN_FRAME2}" ];        then UNIQUE_ID="${UNIQUE_ID}|${ASAN_FRAME2}"; fi
    if [ ! -z "${ASAN_FRAME3}" ];        then UNIQUE_ID="${UNIQUE_ID}|${ASAN_FRAME3}"; fi
    if [ ! -z "${ASAN_FRAME4}" ];        then UNIQUE_ID="${UNIQUE_ID}|${ASAN_FRAME4}"; fi
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
done < "${ERROR_LOG}"

# Profiling
if [ "${PROFILING}" -eq 1 ]; then
  set +x
  exec 2>&3 3>&-
fi
