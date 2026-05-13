#!/bin/bash
# error_log_scan.sh - Unified error log significant-issue scanner.
# Single source of truth for REGEX_ERRORS_SCAN / REGEX_ERRORS_LASTLINE /
# REGEX_ERRORS_FILTER application and for the TEXT regex cleanup pipeline.
# Used by: pquery-run.sh, pquery-del-trial.sh, pquery-results.sh
#
# Usage:
#   error_log_scan.sh errors   <log>...   raw ERRORS lines (REGEX_ERRORS_SCAN matches, filtered)
#   error_log_scan.sh lastline <log>...   raw ERRORS_LAST_LINE (REGEX_ERRORS_LASTLINE on tail, filtered)
#   error_log_scan.sh check    <log>...   silent; exit 0 if any significant errors, 1 otherwise
#   error_log_scan.sh clean    <log>...   cleaned combined form suitable for reducer TEXT
#
# Exit codes: 0 = matched / output produced, 1 = nothing significant or usage/unreadable input.
# Note that the MYBUG file (the new_text_string.sh UniqueID outcome) is the primary
# bug identifier for a trial; the error log content this script returns is secondary
# and is used by pquery-prep-red.sh only when the MYBUG UniqueID is a known-still-open
# bug (to set reducer TEXT against the unfiltered error log bug instead).
set +H

SCRIPT_PWD="$(dirname $(readlink -f "${0}"))"

MODE="${1}"
shift 2>/dev/null
case "${MODE}" in
  errors|lastline|check|clean) ;;
  *) echo "Usage: $0 {errors|lastline|check|clean} <log>..." >&2; exit 1 ;;
esac
[ $# -eq 0 ] && exit 1

REGEX_ERRORS_FILTER="NOFILTERDUMMY"
if [ -r "${SCRIPT_PWD}/REGEX_ERRORS_SCAN" ]; then
  REGEX_ERRORS_SCAN="$(cat "${SCRIPT_PWD}/REGEX_ERRORS_SCAN" 2>/dev/null | tr -d '\n')"
  [ -z "${REGEX_ERRORS_SCAN}" ] && echo "Error: ${SCRIPT_PWD}/REGEX_ERRORS_SCAN is empty" >&2 && exit 2
else
  echo "Error: ${SCRIPT_PWD}/REGEX_ERRORS_SCAN not readable" >&2; exit 2
fi
if [ -r "${SCRIPT_PWD}/REGEX_ERRORS_LASTLINE" ]; then
  REGEX_ERRORS_LASTLINE="$(cat "${SCRIPT_PWD}/REGEX_ERRORS_LASTLINE" 2>/dev/null | tr -d '\n')"
  [ -z "${REGEX_ERRORS_LASTLINE}" ] && echo "Error: ${SCRIPT_PWD}/REGEX_ERRORS_LASTLINE is empty" >&2 && exit 2
else
  echo "Error: ${SCRIPT_PWD}/REGEX_ERRORS_LASTLINE not readable" >&2; exit 2
fi
[ -r "${SCRIPT_PWD}/REGEX_ERRORS_FILTER" ] && REGEX_ERRORS_FILTER="$(cat "${SCRIPT_PWD}/REGEX_ERRORS_FILTER" 2>/dev/null | tr -d '\n')"

# Expand globs and keep only readable files
LOGS=""
for f in "$@"; do
  for g in $f; do
    [ -r "${g}" ] && LOGS="${LOGS} ${g}"
  done
done
[ -z "${LOGS}" ] && exit 1

ERRORS=""
ERRORS_LAST_LINE=""
# Note: no -m1 on the ERRORS grep. We want all matching ERRORS lines (deduplicated by sort -u) so consumers that present errors to users (pquery-results.sh) see the full picture; consumers that only need "is there an issue?" (pquery-run.sh, dt) treat any non-empty ERRORS the same way regardless of count.
if [ ! -z "${REGEX_ERRORS_SCAN}" ]; then
  ERRORS="$(grep --binary-files=text -h -Ei "${REGEX_ERRORS_SCAN}" ${LOGS} 2>/dev/null | sort -u 2>/dev/null | grep --binary-files=text -vE "${REGEX_ERRORS_FILTER}" | grep -vE "^[ \t]*$|^==>")"
fi
if [ ! -z "${REGEX_ERRORS_LASTLINE}" ]; then
  ERRORS_LAST_LINE="$(tail -n1 ${LOGS} 2>/dev/null | grep --no-group-separator --binary-files=text -B1 -E "${REGEX_ERRORS_LASTLINE}" | grep --binary-files=text -vE "${REGEX_ERRORS_FILTER}" | grep -vE "^[ \t]*$|^==>")"
fi

case "${MODE}" in
  errors)   [ -z "${ERRORS}" ]           && exit 1; echo "${ERRORS}" ;;
  lastline) [ -z "${ERRORS_LAST_LINE}" ] && exit 1; echo "${ERRORS_LAST_LINE}" ;;
  check)    [ -z "${ERRORS}" -a -z "${ERRORS_LAST_LINE}" ] && exit 1 ;;
  clean)
    [ -z "${ERRORS}" -a -z "${ERRORS_LAST_LINE}" ] && exit 1
    # Cleanup pipeline: produces a stable regex form suitable for reducer TEXT matching across testcase replays. Aligns with the cleanup style applied by new_text_string.sh to its UniqueIDs (port numbers, GTIDs, binlog positions, temp table names, file paths, line numbers, etc. all stripped/normalised).
    echo "$(if [ ! -z "${ERRORS}" ]; then echo "${ERRORS}"; fi; if [ ! -z "${ERRORS_LAST_LINE}" ]; then echo "${ERRORS_LAST_LINE}"; fi;)" |  sed "s|^[-0-9: ]*||;s|[]['@/}{#\!$%\^\&\*)(]|.|g" | sed 's|[`"]|.|g' | tr '-' '.' | sed 's|PROCEDURE [^ ]\+ |PROCEDURE.*|' | sed 's|:[0-9][0-9]\+\.|.*|' | sed 's|binlog\.0.*end_log_pos.*gtid.*Internal MariaDB error|binlog.*end_log_pos.*gtid.*Internal MariaDB error|i' | sed 's|\(gtid\) [\.0-9 ]\+|\1.*|i' | sed 's|binlog.[0-9]\+\. at [0-9]\+|binlog.*|g;s| at [0-9]\+|.*|g' | sed 's|\.\*[\.]\+|.*|g;s|[\.]\+\.\*|.*|g;s|^[\.]\+||;s|[\.]\+$||' | sed 's|\.test\.1[^ $]\+|.*|;s|\.dev\.shm\.[^ $]\+|.*|' | sed 's|line [0-9]\+|line |' | sed 's|[\. ]\+$||;s|\.\.\*|.*|' | sed 's|for table.*Lock|for table.*Lock|' | sed 's|ERROR. mariadbd: Table .* is marked as crashed and should be repaired|ERROR. mariadbd: Table .* is marked as crashed and should be repaired|'
    ;;
esac
exit 0
