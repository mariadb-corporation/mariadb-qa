#!/bin/bash
# capped_error_log.sh - Bound what an error log scan has to read.
#
# Prints one path per input log: the log itself when it is 10MB or less, and a
# capped copy holding its first and last 5MB when it is larger. A server bug
# can drive a log to gigabytes, and reading one of those in full takes minutes.
# The first 5MB holds the start of the run and the point the trouble began,
# the last 5MB holds the end of the log, so both signature sources survive.
#
# Usage: capped_error_log.sh <outdir> <log>...
#
# The caller creates <outdir> and removes it when done. A capped copy is written
# to <outdir>/<log path>, so removing the "<outdir>/" prefix from a printed path
# gives the original log path back. Callers that read a trial number out of the
# path rely on that.
set +H

OUTDIR="${1}"
shift 2>/dev/null
[ -z "${OUTDIR}" -o ! -d "${OUTDIR}" ] && exit 1
[ $# -eq 0 ] && exit 1

# These two numbers own the cap. Every caller that decides whether to build a temp
# directory holds a copy of MAX_SIZE, so a change here belongs in each of them too:
# new_text_string.sh, san_text_string.sh, fallback_text_string.sh, error_log_scan.sh
# and pquery-prep-red.sh. UniqueID_unit_test.sh fails when one of them drifts
MAX_SIZE=10485760  # 10MB. A log at or below this size is scanned as it is
HALF_SIZE=5242880  # 5MB from the top and 5MB from the bottom of a larger log

OUTDIR_REAL="$(readlink -m "${OUTDIR}" 2>/dev/null)"
[ -z "${OUTDIR_REAL}" ] && exit 1  # Without it the check below has nothing to compare a copy's location against

# One stat for every log. A caller passing a whole workdir of logs pays a process per
# log otherwise, and that is the largest part of what this script costs. -L: a log
# reached through a symlink is measured at the file that is actually read, not at the
# link. A log stat cannot read stays out of the sizes and counts as within the cap
declare -A LOG_SIZE
while read -r SIZE NAME; do LOG_SIZE["${NAME}"]="${SIZE}"; done < <(stat -Lc'%s %n' "$@" 2>/dev/null)

for LOG in "$@"; do
  [ -r "${LOG}" ] || continue
  if [ "${LOG_SIZE[${LOG}]:-0}" -le "${MAX_SIZE}" ]; then
    printf '%s\n' "${LOG}"
    continue
  fi
  CAPPED="${OUTDIR}/${LOG}"
  # A log path holding a '..' component points the copy back out of <outdir>, onto
  # a real file, and a log passed as ../<trial>/log/master.err lands on the log
  # itself. The log is handed back instead, so nothing outside <outdir> is written
  case "$(readlink -m "${CAPPED}" 2>/dev/null)" in
    "${OUTDIR_REAL}"/*) ;;
    *) printf '%s\n' "${LOG}"; continue ;;
  esac
  if ! mkdir -p "$(dirname "${CAPPED}")" 2>/dev/null; then
    printf '%s\n' "${LOG}"  # Nowhere to write the copy, so hand back the log itself
    continue
  fi
  # head -n -1 drops the part-line at the end of the first block and tail -n +2
  # drops the part-line at the start of the last block, so every line stays whole
  WRITE_OK=1
  { head -c "${HALF_SIZE}" "${LOG}" 2>/dev/null | head -n -1 || WRITE_OK=0
    tail -c "${HALF_SIZE}" "${LOG}" 2>/dev/null | tail -n +2 || WRITE_OK=0
  } > "${CAPPED}" 2>/dev/null
  # A copy cut short by a full disk or a size limit still looks like a valid one. Scanning it would give a signature drawn from part of the log, so the log itself is handed back instead
  if [ -s "${CAPPED}" -a "${WRITE_OK}" -eq 1 ]; then printf '%s\n' "${CAPPED}"; else printf '%s\n' "${LOG}"; fi
done
exit 0
