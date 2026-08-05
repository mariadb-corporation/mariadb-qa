#!/bin/bash
set +H  # Disables history substitution and avoids  -bash: !: event not found  like errors
SCRIPT_PWD=$(dirname $(readlink -f "${0}"))
RANDF=$(${SCRIPT_PWD}/random --digits 10)  # Random 10 digits filenr

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

if [ "${MDG}" -eq 1 ]; then
  CORE_COUNT=$(ls --color=never node*/*core* 2>/dev/null | wc -l)
else
  CORE_COUNT=$(ls --color=never data*/*core* var/log/*/*/data/*core* var/*/log/*/*/data/*core* var/mysqld*/data/*core* 2>/dev/null | wc -l)
fi
if [ ${CORE_COUNT} -gt 1 ]; then
  echo "Assert: too many (${CORE_COUNT}) cores found at data*/*core* and/or node*/*core*"
  exit 1
fi
# A core is not required: a *SAN or Valgrind issue is reported in the error log without aborting.
# With no core the assert and the sanitizer block are still emitted; only the gdb stack is skipped.

# Note that no 'head -n1' or similar is needed here, as the script will terminate if >1 core is found (ref code above)
LATEST_CORE=
if [ "${MDG}" -eq 1 ]; then
  LATEST_CORE="$(ls -t --color=never node*/*core* 2>/dev/null)"
else
  LATEST_CORE="$(ls -t --color=never data*/*core* var/log/*/*/data/*core* var/*/log/*/*/data/*core* var/mysqld*/data/*core* 2>/dev/null)"
fi

if [ "${MDG}" -eq 1 ]; then
  ERROR_LOG=$(ls --color=never node*/node*.err 2>/dev/null | head -n1)  # This is not perfect in case node2 or node3 crashes TODO
else
  ERROR_LOG=$(ls --color=never log/master.err log/slave.err var/log/mysqld.2.err var/log/mysqld.1.err 2>/dev/null | head -n1)  # Deterministic initial pick (first existing of master.err / slave.err / mysqld.2.err / mysqld.1.err). The LATEST_CORE-driven sed realignment immediately below swaps master.err<->slave.err and mysqld.1<->mysqld.2 as needed so the assertion extracted further down matches the core actually analyzed by gdb. Likely something similar can be done for MDG.
fi
# Match the (MTR / master-slave) error log to the core actually being analyzed, if/when mismatched (for example when both m+s crash and one dir is deleted to debug the other with tt etc.). Done BEFORE assert extraction so the assertion shown corresponds to the LATEST_CORE chosen for gdb below.
if [[ "${LATEST_CORE}" == *"mysqld.1"* ]]; then
  ERROR_LOG="$(echo "${ERROR_LOG}" | sed 's|mysqld.2|mysqld.1|')"
elif [[ "${LATEST_CORE}" == *"mysqld.2"* ]]; then
  ERROR_LOG="$(echo "${ERROR_LOG}" | sed 's|mysqld.1|mysqld.2|')"
fi
if [[ "${LATEST_CORE}" == *"data_slave"* ]]; then
  ERROR_LOG="$(echo "${ERROR_LOG}" | sed 's|master.err|slave.err|g')"
elif [[ "${LATEST_CORE}" == *"data/core"* ]]; then
  ERROR_LOG="$(echo "${ERROR_LOG}" | sed 's|slave.err|master.err|g')"
fi
#echo "DEBUG: err: ${ERROR_LOG} | core: ${LATEST_CORE}"
# TODO: MDG needs similar code for node1/2/3

# Only collected here. It is printed further below, and ONLY when no *SAN or Valgrind report is
# present: an assertion never belongs above a sanitizer stack. On a sanitizer build the assert is
# the downstream abort of what the sanitizer already reported, and showing both reads as two bugs.
if [ ! -z "${ERROR_LOG}" ]; then
  #echo "----${ERROR_LOG} "  # Debug
  ASSERT="$(grep --binary-files=text -m1 'Assertion.*failed.$' ${ERROR_LOG} | head -n1)"
  #echo "----${ASSERT}"  # Debug
  if [ -z "${ASSERT}" ]; then
    ASSERT="$(grep --binary-files=text -m1 'Failing assertion:' ${ERROR_LOG} | head -n1)"
  fi
fi

# Find a *SAN or Valgrind report in the error log, and its line range: the first issue line to
# its closing summary line. Same range bug_report.sh uses for ~/bs, ~/bm, ~/bt and ~/bv - keep
# the two in step when changing either. Done BEFORE gdb, as it decides whether gdb runs at all.
SAN_START_LINE=;SAN_END_LINE=
if [ ! -z "${ERROR_LOG}" ] && [ -r "${ERROR_LOG}" ]; then
  SAN_START_REGEX=
  SAN_END_REGEX='^SUMMARY:|=ABORTING$'
  if grep -qE --binary-files=text '==[0-9]+== ERROR SUMMARY:' "${ERROR_LOG}" 2>/dev/null; then  # Valgrind
    SAN_START_REGEX='==[0-9]+==.*(Invalid read|Invalid write|Invalid free|Mismatched free|uninitialised|Syscall param|Source and destination overlap|Jump to the invalid address|Process terminating with default action)'
    SAN_END_REGEX='==[0-9]+== ERROR SUMMARY:'
  elif grep -qE --binary-files=text 'MemorySanitizer:' "${ERROR_LOG}" 2>/dev/null; then  # MSAN
    SAN_START_REGEX='^SUMMARY:|=ERROR:|MemorySanitizer:'
  elif grep -qE --binary-files=text 'ThreadSanitizer:' "${ERROR_LOG}" 2>/dev/null; then  # TSAN
    SAN_START_REGEX='WARNING: ThreadSanitizer:|SUMMARY: ThreadSanitizer:'
  elif grep -qE --binary-files=text 'runtime error:|AddressSanitizer:|LeakSanitizer:|=ERROR:' "${ERROR_LOG}" 2>/dev/null; then  # UBSAN and/or ASAN
    SAN_START_REGEX='^SUMMARY:|=ERROR:|runtime error:|AddressSanitizer:|LeakSanitizer:'
  fi
  if [ ! -z "${SAN_START_REGEX}" ]; then
    SAN_START_LINE=$(grep -n -m1 -E --binary-files=text "${SAN_START_REGEX}" "${ERROR_LOG}" | cut -d: -f1)
    SAN_END_LINE=$(grep -n -E --binary-files=text "${SAN_END_REGEX}" "${ERROR_LOG}" | tail -n1 | cut -d: -f1)
    if [ ! -z "${SAN_START_LINE}" ]; then
      # No end marker means a truncated report, so bound the range rather than dump the rest of the log
      if [ -z "${SAN_END_LINE}" ] || [ "${SAN_END_LINE}" -lt "${SAN_START_LINE}" ]; then SAN_END_LINE=$(( SAN_START_LINE + 200 )); fi
    fi
  fi
fi

# ONE stack only. A *SAN or Valgrind report IS the stack, and it wins over the core backtrace:
# on a sanitizer build that backtrace usually shows only the abort path, not the offending code.
if [ ! -z "${SAN_START_LINE}" ]; then
  # Sanitizer block only. No assert block above it, and no core backtrace.
  echo "{noformat:title=${SVR} ${SERVER_VERSION} ${SOURCE_CODE_REV}${BUILD_TYPE} ${BUILD_DATE}}"
  sed -n "${SAN_START_LINE},${SAN_END_LINE}p" "${ERROR_LOG}"
  echo '{noformat}'
elif [ ${CORE_COUNT} -eq 1 ]; then
  if [ ! -z "${ASSERT}" ]; then
    echo -e "{noformat:title=${SVR} ${SERVER_VERSION} ${SOURCE_CODE_REV}${BUILD_TYPE} ${BUILD_DATE}}\n${ASSERT}\n{noformat}\n"
  fi
  gdb -q -iex 'set debuginfod enabled off' ${BIN} ${LATEST_CORE} >/tmp/${RANDF}.gdba 2>&1 << EOF
 set pagination off
 set print pretty on
 set print frame-arguments all
 bt
 quit
EOF

# Update March/April 24: a system update now renders stacks as
#10 0x0000562e73a837b4 in mysql_admin_table (thd=thd@entry=0x152110000d58,
#    tables=tables@entry=0x152110016ac0,
#    ...
#    at /test/preview-11.5-preview_dbg/sql/sql_admin.cc:1116
# The awk below fixes this by moving everything back into single lines
# Also changed in bug_report.sh

  if [ -r /tmp/${RANDF}.gdba ]; then
    echo "{noformat:title=${SVR} ${SERVER_VERSION} ${SOURCE_CODE_REV}${BUILD_TYPE} ${BUILD_DATE}}"
    # The next line is duplicated in bug_report.sh, update both if changing one
    grep --binary-files=text -A999 'Core was generated by' /tmp/${RANDF}.gdba | grep --binary-files=text -v 'No such file or directory' | sed 's|(gdb) (gdb) |(gdb) bt\n|' | sed 's|(gdb) (gdb) ||' | awk '{ if(/^    /) printf("%s", substr($0, 5)); else if(NR > 1) printf("\n%s", $0); else printf("%s", $0); } END { printf("\n"); }' | grep --binary-files=text -v '^(gdb)[ \t]*$' | grep --binary-files=text -viE 'Downloading source file|Download failed'
    rm -f /tmp/${RANDF}.gdba
  else
    echo "Assert: /tmp/${RANDF}.gdba not found after gdb was called"
    exit 1
  fi
  echo '{noformat}'
else
  echo "INFO: no cores found at data*/*core* nor at node*/*core*, and no *SAN or Valgrind report found in ${ERROR_LOG:-the error log}"
  exit 1
fi
