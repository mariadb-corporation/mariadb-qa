#!/bin/bash
# error_log_scan.sh - Unified error log significant-issue scanner.
# Single source of truth for REGEX_ERRORS_SCAN / REGEX_ERRORS_LASTLINE /
# REGEX_ERRORS_FILTER application and for the UID / TEXT cleanup pipelines.
# Used by: pquery-run.sh, pquery-del-trial.sh, pquery-results.sh
#
# Usage:
#   error_log_scan.sh errors   <log>...   typed UIDs (REGEX_ERRORS_SCAN matches, filtered, normalised)
#   error_log_scan.sh lastline <log>...   typed UID(s) for the tail-of-log error
#   error_log_scan.sh check    <log>...   silent; exit 0 if any significant errors, 1 otherwise
#   error_log_scan.sh clean    <log>...   cleaned combined form suitable for reducer TEXT (regex-friendly)
#   error_log_scan.sh aggregate <log>...  <UID><tab><trial> rows for pquery-results.sh's grouper
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
  errors|lastline|check|clean|aggregate) ;;
  *) echo "Usage: $0 {errors|lastline|check|clean|aggregate} <log>..." >&2; exit 1 ;;
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

# Pre-normalisation cleanups applied before UID typing / extraction. Two stages:
#  1) INNODB_RECORD_COLLAPSE: pattern-specific. Collapses multi-KB InnoDB "Record in index ... TUPLE ... at: (COMPACT )?RECORD ..." dumps into a single stable signature, folding both the [ERROR] update form and the paired [Warning] rollback form, and folding COMPACT vs non-COMPACT row formats (semantically the same logical event, different table row_format). nts (new_text_string.sh) keeps the COMPACT and non-COMPACT forms separate for MYBUG so kb classification can distinguish them (kb anchors the COMPACT form on MDEV-35187); the aggregate-path fold here is the looser grouping used by pquery-results.sh's UID list.
#  2) UNIVERSAL_COLLAPSE: pattern-agnostic. Squashes long whitespace runs (5+) and long 0x-hex blobs (12+ hex chars) to "..."; catches binary-payload noise that lands in the error log.
INNODB_RECORD_COLLAPSE='s|Record in index.*of table.*was not found on update: TUPLE.*at: (COMPACT )?RECORD.*|Record in index X of table Y was not found (update/rollback)|; s|Record in index.*of table.*was not found on rollback, trying to insert: TUPLE.*at: (COMPACT )?RECORD.*|Record in index X of table Y was not found (update/rollback)|'
UNIVERSAL_COLLAPSE='s| \{5,\}|...|g; s|0x[0-9A-Fa-f]\{12,\}|0x...|g'

# UID-line normalisations for the errors / lastline / aggregate output paths. Strips per-trial volatile detail (timestamps, port numbers, binlog positions, GTID values, hex IDs, identifier quoting, table-name suffixes, etc.) so semantically-identical events fold to the same UID. "Clean" mode does NOT use these — it has its own regex-friendly pipeline (below) that pquery-del-trial.sh feeds into reducer TEXT.
UID_NORMALIZE_TS='s|^[0-9]{4}-[0-9]{2}-[0-9]{2}  *[0-9]+:[0-9]+:[0-9]+ +[0-9]+ +||'
UID_NORMALIZE_TT='s|#sql-temptable-[0-9a-f]+-[0-9]+-[0-9a-f]+|#sql-temptable-X|g'
UID_NORMALIZE_BACKUP='s|#sql-backup-[0-9a-f]+-[0-9]+|#sql-backup-X|g'
UID_NORMALIZE_SHM='s|/dev/shm/[0-9]+/[0-9]+/|/dev/shm/X/N/|g'
UID_NORMALIZE_IBD="s|'/[^']*/test/t[0-9]+\\.ibd'|'/X/test/tN.ibd'|g"
UID_NORMALIZE_QUOTED_ID="s/'[a-zA-Z_][a-zA-Z0-9_]*'/'<id>'/g"
UID_NORMALIZE_BACKTICK_ID='s/`[a-zA-Z_][a-zA-Z0-9_]*`/`<id>`/g'
UID_NORMALIZE_TABLE_REF="s#'\\./test/[^']+'#'./test/X'#g"
UID_NORMALIZE_PORT='s|127\.0\.0\.1:[0-9]+|127.0.0.1:X|g'
UID_NORMALIZE_BINLOG='s|binlog\.[0-9]+|binlog.X|g'
UID_NORMALIZE_POSITION='s#(^| )position [0-9]+#\1position X#g'
UID_NORMALIZE_END_LOG_POS='s|end_log_pos [0-9]+|end_log_pos X|g'
UID_NORMALIZE_GTID='s|Gtid [0-9]+-[0-9]+-[0-9]+(,[0-9]+-[0-9]+-[0-9]+)*|Gtid X|g'
UID_NORMALIZE_GTID_POSITION="s|GTID position '[^']*'|GTID position 'X'|g"
UID_NORMALIZE_FAILED_OPEN="s|'Failed to open [^']+'|'Failed to open X'|g"
UID_NORMALIZE_DATA_LEN='s|data_len: [0-9]+|data_len: X|g'
UID_NORMALIZE_EVENT_TYPE='s|event_type: [0-9]+|event_type: X|g'
UID_NORMALIZE_PAGE_NUM='s|page number=[0-9]+|page number=X|g; s|page id: space=[0-9]+|page id: space=X|g'
UID_NORMALIZE_INDEX_PAGE='s|Index root page [0-9]+ in ([^ ]+) is corrupted at [0-9]+|Index root page N in \1 is corrupted at M|g'
UID_NORMALIZE_UNDO_PAGE='s|corrupted page [0-9]+ in file [./]*undo[0-9]+|corrupted page N in file undoX|g'
UID_NORMALIZE_ABORTED_CONN='s|Aborted connection [0-9]+ |Aborted connection N |g'
UID_NORMALIZE_LEAK='s|Indirect leak of [0-9]+ byte\(s\) in [0-9]+ object\(s\)|Indirect leak of N bytes in M objects|g'
UID_NORMALIZE_ASAN_PID='s|^==[0-9]+==|==X==|'
UID_NORMALIZE_DBLWRITE_WAIT='s|Long wait \([0-9]+ seconds\)|Long wait (N seconds)|g'
UID_NORMALIZE_DATETIME='s|[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?|YYYY-MM-DD HH:MM:SS|g'
UID_NORMALIZE_LRECL='s|Table/File lrecl mismatch \([0-9]+,[0-9]+\)|Table/File lrecl mismatch (N,M)|g'
UID_NORMALIZE_TEST_PATH='s|/test/[^/]+/|/test/X/|g'
UID_NORMALIZE_INNODB_HELP='s|We detected index corruption in an InnoDB type table\..*|We detected index corruption in an InnoDB type table|; s|already exists though the corresponding table did not exist in the InnoDB data dictionary\..*|already exists though the corresponding table did not exist in the InnoDB data dictionary|'

uid_normalize() {
  sed -E \
      -e "${UID_NORMALIZE_TS}" \
      -e "${UID_NORMALIZE_TT}" \
      -e "${UID_NORMALIZE_BACKUP}" \
      -e "${UID_NORMALIZE_SHM}" \
      -e "${UID_NORMALIZE_IBD}" \
      -e "${UID_NORMALIZE_QUOTED_ID}" \
      -e "${UID_NORMALIZE_BACKTICK_ID}" \
      -e "${UID_NORMALIZE_TABLE_REF}" \
      -e "${UID_NORMALIZE_PORT}" \
      -e "${UID_NORMALIZE_BINLOG}" \
      -e "${UID_NORMALIZE_POSITION}" \
      -e "${UID_NORMALIZE_END_LOG_POS}" \
      -e "${UID_NORMALIZE_GTID}" \
      -e "${UID_NORMALIZE_GTID_POSITION}" \
      -e "${UID_NORMALIZE_FAILED_OPEN}" \
      -e "${UID_NORMALIZE_DATA_LEN}" \
      -e "${UID_NORMALIZE_EVENT_TYPE}" \
      -e "${UID_NORMALIZE_PAGE_NUM}" \
      -e "${UID_NORMALIZE_INDEX_PAGE}" \
      -e "${UID_NORMALIZE_UNDO_PAGE}" \
      -e "${UID_NORMALIZE_ABORTED_CONN}" \
      -e "${UID_NORMALIZE_LEAK}" \
      -e "${UID_NORMALIZE_ASAN_PID}" \
      -e "${UID_NORMALIZE_DBLWRITE_WAIT}" \
      -e "${UID_NORMALIZE_DATETIME}" \
      -e "${UID_NORMALIZE_LRECL}" \
      -e "${UID_NORMALIZE_TEST_PATH}" \
      -e "${UID_NORMALIZE_INNODB_HELP}" \
  | awk '!seen[$0]++'
}

# uid_prefix: route each normalised line to its UID form (<TYPE>|<short body>). Order matters — most specific match wins. Prefixes shared with new_text_string.sh (INNODB_ERROR, INNODB_WARNING, SLAVE_ERROR, MARIADBD_ERROR, MARKED_AS_CRASHED, GOT_ERROR, OPENTABLE, MUTEX_ERROR) and known_bugs.strings (ASAN, LSAN). Prefixes scoped to this script: INNODB_NOTE, SLAVE_WARNING, WARNING_ABORTED, MYSQL_HA_READ, ROCKSDB_ERROR, CHECKTABLE, GLIBC, ASSERT. ASSERT is used only when an assert line reaches the aggregate path without nts producing an <assert>|<frame1..4> UID (no core / no MYBUG); the ASSERT form drops the `/test/<ver>/` leading path and the line number, leaving `ASSERT|<repo-relative-path>|Assertion '<x>' failed`.
uid_prefix() {
  awk '
    {
      if (match($0, /^mariadbd: \/test\/[^\/]+\/.*: Assertion .* failed/)) {
        pos = index($0, ": Assertion ")
        if (pos > 0) {
          prefix = substr($0, 1, pos - 1)
          tail = "Assertion " substr($0, pos + length(": Assertion "))
          sub(/^mariadbd: \/test\/[^\/]+\//, "", prefix)
          sub(/:[0-9]+: .+$/, "", prefix)
          sub(/\.$/, "", tail)
          print "ASSERT|" prefix "|" tail
          next
        }
      }
      if (sub(/^\[ERROR\] InnoDB: /,     "INNODB_ERROR|"))   { print; next }
      if (sub(/^\[Warning\] InnoDB: /,   "INNODB_WARNING|")) {
        # Fold the [Warning] rollback variant of "Record in index ... was not found" into INNODB_ERROR — paired emission of the same logical event as the [ERROR] update variant. Other [Warning] InnoDB bodies keep the INNODB_WARNING prefix.
        if ($0 ~ /^INNODB_WARNING\|Record in index X of table Y was not found \(update\/rollback\)$/) {
          sub(/^INNODB_WARNING\|/, "INNODB_ERROR|")
        }
        print; next
      }
      if (sub(/^\[Note\] InnoDB: /,      "INNODB_NOTE|"))    { print; next }
      if ($0 ~ /^\[ERROR\] mariadbd: Table .* is marked as crashed/) {
        sub(/^\[ERROR\] mariadbd: /, "MARKED_AS_CRASHED|"); print; next
      }
      if (sub(/^\[ERROR\] mariadbd: /,           "MARIADBD_ERROR|"))             { print; next }
      if (sub(/^\[ERROR\] mysql_ha_read: /,      "MYSQL_HA_READ|"))              { print; next }
      if (sub(/^\[ERROR\] Got error /,           "GOT_ERROR|Got error "))        { print; next }
      if (sub(/^\[ERROR\] Got an error /,        "GOT_ERROR|Got an error "))     { print; next }
      if (sub(/^\[ERROR\] Slave I\/O: /,                  "SLAVE_ERROR|Slave I/O: "))                  { print; next }
      if (sub(/^\[ERROR\] Slave SQL: /,                   "SLAVE_ERROR|Slave SQL: "))                  { print; next }
      if (sub(/^\[ERROR\] Slave \(additional info\): /,   "SLAVE_ERROR|Slave (additional info): "))    { print; next }
      if (sub(/^\[ERROR\] Slave: /,                       "SLAVE_ERROR|Slave: "))                      { print; next }
      if (sub(/^\[ERROR\] Master /,                       "SLAVE_ERROR|Master "))                      { print; next }
      if (sub(/^\[ERROR\] Error running query/,           "SLAVE_ERROR|Error running query"))          { print; next }
      if (sub(/^\[ERROR\] Error in Log_event/,            "SLAVE_ERROR|Error in Log_event"))           { print; next }
      if (sub(/^\[ERROR\] Error reading master/,          "SLAVE_ERROR|Error reading master"))         { print; next }
      if (sub(/^\[ERROR\] Error reading packet/,          "SLAVE_ERROR|Error reading packet"))         { print; next }
      if (sub(/^\[ERROR\][ ]+BINLOG_BASE64_EVENT: /,      "SLAVE_ERROR|BINLOG_BASE64_EVENT: "))        { print; next }
      if (sub(/^\[Warning\] Slave I\/O: /,                "SLAVE_WARNING|Slave I/O: "))                { print; next }
      if (sub(/^\[Warning\] Slave SQL: /,                 "SLAVE_WARNING|Slave SQL: "))                { print; next }
      if (sub(/^\[Warning\] Slave: /,                     "SLAVE_WARNING|Slave: "))                    { print; next }
      if (sub(/^\[Warning\] Aborted connection/, "WARNING_ABORTED|Aborted connection")) { print; next }
      if (sub(/^\[ERROR\] RocksDB: /,            "ROCKSDB_ERROR|RocksDB: "))     { print; next }
      if (sub(/^\[ERROR\] CHECKTABLE /,          "CHECKTABLE|CHECKTABLE "))      { print; next }
      if (sub(/^\[ERROR\] Table /,               "MARIADBD_ERROR|Table "))       { print; next }
      if ($0 ~ /^OpenTable: /)                          { print "OPENTABLE|" $0; next }
      if ($0 ~ /^Table\/File lrecl mismatch/)           { print "OPENTABLE|" $0; next }
      if ($0 ~ /^index_init CONNECT: /)                 { print "OPENTABLE|" $0; next }
      if ($0 ~ /^safe_mutex: /)                         { print "MUTEX_ERROR|" $0; next }
      if ($0 ~ /^Trying to lock uninitialized mutex/)   { print "MUTEX_ERROR|" $0; next }
      if ($0 ~ /^Indirect leak of/)                     { print "LSAN|" $0; next }
      if ($0 ~ /AddressSanitizer/)                      { print "ASAN|" $0; next }
      if ($0 ~ /^(corrupted|malloc\(|free\(|double free|munmap_chunk)/) { print "GLIBC|" $0; next }
      print
    }
  '
}

# aggregate mode: processes ALL passed logs in one bash invocation and emits <UID><tab><trial> rows ready for pquery-results.sh's sort-then-awk grouper. Trial number is read from the first numeric component of the log path (./<trial>/log/master.err, ./<trial>/node<N>/node<N>.err). One invocation handles all logs to avoid per-log subprocess spawns for errors+lastline.
if [ "${MODE}" = "aggregate" ]; then
  for log in ${LOGS}; do
    [ -r "${log}" ] || continue
    trial="$(echo "${log}" | sed -n 's|^\./\([0-9]\+\)/.*|\1|p')"
    [ -z "${trial}" ] && continue
    log_errors="$(grep --binary-files=text -h -Ei "${REGEX_ERRORS_SCAN}" "${log}" 2>/dev/null | sort -u 2>/dev/null | grep --binary-files=text -vE "${REGEX_ERRORS_FILTER}" | grep -vE "^[ \t]*$|^==>")"
    log_lastline="$(tail -n1 "${log}" 2>/dev/null | grep --no-group-separator --binary-files=text -B1 -E "${REGEX_ERRORS_LASTLINE}" | grep --binary-files=text -vE "${REGEX_ERRORS_FILTER}" | grep -vE "^[ \t]*$|^==>")"
    { [ -n "${log_errors}" ] && echo "${log_errors}"; [ -n "${log_lastline}" ] && echo "${log_lastline}"; } \
      | sed -E "${INNODB_RECORD_COLLAPSE}" \
      | sed "${UNIVERSAL_COLLAPSE}" \
      | uid_normalize \
      | uid_prefix \
      | awk '!seen[$0]++' \
      | awk -v t="${trial}" 'NF{print $0 "\t" t}'
  done
  exit 0
fi

ERRORS=""
ERRORS_LAST_LINE=""
# Note: no -m1 on the ERRORS grep. We want all matching ERRORS lines (deduplicated by sort -u) so consumers that present errors to users (pquery-results.sh) see the full picture; consumers that only need "is there an issue?" (pquery-run.sh, dt) treat any non-empty ERRORS the same way regardless of count.
if [ ! -z "${REGEX_ERRORS_SCAN}" ]; then
  ERRORS="$(grep --binary-files=text -h -Ei "${REGEX_ERRORS_SCAN}" ${LOGS} 2>/dev/null | sort -u 2>/dev/null | grep --binary-files=text -vE "${REGEX_ERRORS_FILTER}" | grep -vE "^[ \t]*$|^==>")"
fi
if [ ! -z "${REGEX_ERRORS_LASTLINE}" ]; then
  ERRORS_LAST_LINE="$(tail -n1 ${LOGS} 2>/dev/null | grep --no-group-separator --binary-files=text -B1 -E "${REGEX_ERRORS_LASTLINE}" | grep --binary-files=text -vE "${REGEX_ERRORS_FILTER}" | grep -vE "^[ \t]*$|^==>")"
fi

[ ! -z "${ERRORS}" ]           && ERRORS="$(echo "${ERRORS}"                     | sed -E "${INNODB_RECORD_COLLAPSE}" | sed "${UNIVERSAL_COLLAPSE}")"
[ ! -z "${ERRORS_LAST_LINE}" ] && ERRORS_LAST_LINE="$(echo "${ERRORS_LAST_LINE}" | sed -E "${INNODB_RECORD_COLLAPSE}" | sed "${UNIVERSAL_COLLAPSE}")"

case "${MODE}" in
  errors)   [ -z "${ERRORS}" ]           && exit 1; echo "${ERRORS}"           | uid_normalize | uid_prefix ;;
  lastline) [ -z "${ERRORS_LAST_LINE}" ] && exit 1; echo "${ERRORS_LAST_LINE}" | uid_normalize | uid_prefix ;;
  check)    [ -z "${ERRORS}" -a -z "${ERRORS_LAST_LINE}" ] && exit 1 ;;
  clean)
    [ -z "${ERRORS}" -a -z "${ERRORS_LAST_LINE}" ] && exit 1
    # Reducer-TEXT cleanup pipeline: produces a regex-friendly stable form for reducer TEXT replay matching across testcase replays. Distinct from uid_normalize+uid_prefix (which produce the actual UIDs consumed by pquery-results.sh / kb matching). Aligns with the cleanup style applied by new_text_string.sh to its UniqueIDs (port numbers, GTIDs, binlog positions, temp table names, file paths, line numbers, etc. all stripped/normalised).
    # Trailing `awk '!seen[$0]++'`: order-preserving dedup AFTER all per-line normalisation. Lines that differ only by stripped detail (index names, table suffixes, hex blobs, timestamps) collapse to identical strings here; without this, pquery-prep-red.sh joins the duplicates with '|' into an overly long TEXT regex (e.g. 8x identical "Warning. InnoDB: Record in index..of table..was not found on rollback..." alternations).
    echo "$(if [ ! -z "${ERRORS}" ]; then echo "${ERRORS}"; fi; if [ ! -z "${ERRORS_LAST_LINE}" ]; then echo "${ERRORS_LAST_LINE}"; fi;)" | sed "s|Aborted connection [0-9]\+ to db: '[^']*' user: '[^']*' host: '[^']*'|Aborted connection X to db: 'Y' user: 'Z' host: 'H'|" |  sed "s|^[-0-9: ]*||;s|[]['@/}{#\!$%\^\&\*)(]|.|g" | sed 's|[`"]|.|g' | tr '-' '.' | sed 's|PROCEDURE [^ ]\+ |PROCEDURE.*|' | sed 's|:[0-9][0-9]\+\.|.*|' | sed 's|binlog\.0.*end_log_pos.*gtid.*Internal MariaDB error|binlog.*end_log_pos.*gtid.*Internal MariaDB error|i' | sed 's|\(gtid\) [\.0-9 ]\+|\1.*|i' | sed 's|binlog.[0-9]\+\. at [0-9]\+|binlog.*|g;s| at [0-9]\+|.*|g' | sed 's|\.\*[\.]\+|.*|g;s|[\.]\+\.\*|.*|g;s|^[\.]\+||;s|[\.]\+$||' | sed 's|\.test\.1[^ $]\+|.*|;s|\.dev\.shm\.[^ $]\+|.*|' | sed 's|line [0-9]\+|line |' | sed 's|[\. ]\+$||;s|\.\.\*|.*|' | sed 's|for table.*Lock|for table.*Lock|' | sed 's|ERROR. mariadbd: Table .* is marked as crashed and should be repaired|ERROR. mariadbd: Table .* is marked as crashed and should be repaired|' | awk '!seen[$0]++'
    ;;
esac
exit 0
