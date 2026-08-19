#!/bin/bash
# UniqueID_unit_test.sh - regression test for the UniqueID extraction chain.
#
# The UniqueID of a trial decides everything downstream: whether a trial is
# saved, whether it is dropped as a known bug, what a reducer searches for, and
# what a bug report is filed against. A change to any script in that chain must
# leave the UniqueID of every existing trial exactly as it was. This test proves
# that, by running the chain twice over real trials in /data - once with the
# scripts as they are now, once with a reference copy - and comparing byte for
# byte.
#
# Usage:
#   UniqueID_unit_test.sh                 Compare the working tree against git HEAD, 25 trials per bug class
#   UniqueID_unit_test.sh 100             The same, with 100 trials per bug class
#   UniqueID_unit_test.sh all             The same, over every trial in /data (slow)
#   UniqueID_unit_test.sh --ref <dir>     Compare against a copy of mariadb-qa in <dir> instead of git HEAD
#   UniqueID_unit_test.sh --census        Only print how many trials of each bug class exist, and stop
#   UniqueID_unit_test.sh --no-gdb        Leave out new_text_string.sh, which needs gdb and is the slow one
#
# Run it before and after any change to:
#   error_log_scan.sh, new_text_string.sh, san_text_string.sh,
#   fallback_text_string.sh, capped_error_log.sh, pquery-results.sh
#
# Keep a run under 20 minutes. terminate_long_running.sh matches any command line
# holding 'mariadb', which includes the path of this script, and kills it at 1200
# seconds. Lower the trials per class, or use --no-gdb, rather than let it be cut
# off part way with no result.
#
# What it covers, per trial:
#   error_log_scan.sh        all six modes (errors, lastline, top, check, clean, aggregate)
#   fallback_text_string.sh  the fallback UniqueID
#   san_text_string.sh       the sanitizer UniqueID
#   new_text_string.sh       the full UniqueID, core and gdb included (left out by --no-gdb)
# Output and exit code are both compared, as callers branch on the exit code.
#
# The corpus comes from the MYBUG file of each trial, grouped by the class the
# UniqueID starts with (SIGNAL, ASSERT, ASAN, UBSAN, MSAN, TSAN, LSAN, and the
# typed error-log prefixes). Sampling per class keeps every class represented
# however many trials of one kind happen to be on the box.
#
# Exit code: 0 when every trial matched, 1 when any differed or the run failed
# to start. A difference is printed with the trial, the tool, and the diff.
set +H

SCRIPT_PWD="$(dirname "$(readlink -f "${0}")")"
PER_CLASS=25
REF_DIR=
CENSUS_ONLY=0
USE_GDB=1
KEEP_REF=0

while [ ! -z "${1}" ]; do
  case "${1}" in
    --ref) REF_DIR="${2}"; KEEP_REF=1; shift 2 ;;
    --census) CENSUS_ONLY=1; shift ;;
    --no-gdb) USE_GDB=0; shift ;;
    all) PER_CLASS=0; shift ;;
    ''|*[!0-9]*) echo "Usage: ${0##*/} [<trials per class>|all] [--ref <dir>] [--census] [--no-gdb]" >&2; exit 1 ;;
    *) PER_CLASS="${1}"; shift ;;
  esac
done

WORK="$(mktemp -d)" || { echo "Assert: mktemp -d failed"; exit 1; }
cleanup(){ [ "${KEEP_REF}" -eq 0 -a ! -z "${REF_DIR}" ] && rm -rf "${REF_DIR}"; rm -rf "${WORK}"; }
trap cleanup EXIT

# The corpus: every trial with a MYBUG file, labelled with its bug class
find /data -maxdepth 3 -name MYBUG 2>/dev/null | while read -r MYBUG; do
  read -r UID_LINE < "${MYBUG}" 2>/dev/null
  TRIAL_DIR="${MYBUG%/MYBUG}"
  [ -r "${TRIAL_DIR}/log/master.err" ] || continue
  printf '%s\t%s\n' "${UID_LINE}" "${TRIAL_DIR}"
done | awk -F'\t' '
  { u=$1
    if (u ~ /^SIG/) { k="SIGNAL" }
    else if (u ~ /[Aa]ssert/) { k="ASSERT" }
    else { n=index(u,"|"); k=(n>1 ? substr(u,1,n-1) : "OTHER") }
    gsub(/[^A-Za-z0-9_]/,"_",k)
    print k "\t" $2 }' | sort -u > "${WORK}/corpus"

if [ ! -s "${WORK}/corpus" ]; then
  echo "Assert: no trials with a MYBUG file and a readable error log were found under /data"
  exit 1
fi

echo "=== Bug classes found under /data ==="
awk -F'\t' '{n[$1]++} END{for(k in n) printf "%6d  %s\n", n[k], k}' "${WORK}/corpus" | sort -rn
echo "    total: $(wc -l < "${WORK}/corpus") trials"
[ "${CENSUS_ONLY}" -eq 1 ] && exit 0

# Sample per class, so a class with few trials is still covered
if [ "${PER_CLASS}" -eq 0 ]; then
  cut -f2 "${WORK}/corpus" > "${WORK}/trials"
else
  awk -F'\t' -v max="${PER_CLASS}" '{ if (++n[$1] <= max) print $2 }' "${WORK}/corpus" > "${WORK}/trials"
fi
TRIAL_COUNT="$(wc -l < "${WORK}/trials")"

# The reference copy. Files are symlinked so the reference reads the same
# REGEX_ERRORS_* and known-bug lists; only the chain scripts are real copies,
# taken from git HEAD unless --ref named a directory already
CHAIN='error_log_scan.sh new_text_string.sh san_text_string.sh fallback_text_string.sh capped_error_log.sh pquery-results.sh'
if [ -z "${REF_DIR}" ]; then
  REF_DIR="$(mktemp -d)" || { echo "Assert: mktemp -d failed"; exit 1; }
  for F in "${SCRIPT_PWD}"/*; do
    ln -s "$(readlink -f "${F}")" "${REF_DIR}/$(basename "${F}")" 2>/dev/null
  done
  for F in ${CHAIN}; do
    rm -f "${REF_DIR}/${F}"
    if ( cd "${SCRIPT_PWD}" && git show "HEAD:${F}" ) > "${REF_DIR}/${F}" 2>/dev/null && [ -s "${REF_DIR}/${F}" ]; then
      chmod +x "${REF_DIR}/${F}"
    else  # Not in git yet, so it is new: the reference simply does not have it
      rm -f "${REF_DIR}/${F}"
    fi
  done
fi

echo
echo "=== Comparing ${TRIAL_COUNT} trials ==="
echo "    reference: ${REF_DIR}"
echo "    current:   ${SCRIPT_PWD}"
[ "${USE_GDB}" -eq 0 ] && echo "    new_text_string.sh left out (--no-gdb)"

# One trial, every tool, both versions. Runs as a child of this script so the
# comparison can be spread over the cores
if [ "${1}" = '' -a ! -z "${UNIT_TEST_ONE}" ]; then :; fi
run_one(){
  local TRIAL_DIR="${1}" OUT="${2}" REF="${3}" CUR="${4}" GDB="${5}"
  local PARENT="$(dirname "${TRIAL_DIR}")" NAME="$(basename "${TRIAL_DIR}")"
  local LOG="./${NAME}/log/master.err" TOOL MODE A B
  # Both sides get the same limit, so a tool that runs away is still compared fairly: each side reports exit=124
  local TMO='timeout 600'
  for MODE in errors lastline top check clean aggregate; do
    A="$( cd "${PARENT}" && ${TMO} "${REF}/error_log_scan.sh" "${MODE}" "${LOG}" 2>&1; echo "exit=$?" )"
    B="$( cd "${PARENT}" && ${TMO} "${CUR}/error_log_scan.sh" "${MODE}" "${LOG}" 2>&1; echo "exit=$?" )"
    [ "${A}" != "${B}" ] && { printf '%s\terror_log_scan.sh %s\n' "${TRIAL_DIR}" "${MODE}" >> "${OUT}/diffs"
      { echo "--- ${TRIAL_DIR} error_log_scan.sh ${MODE}"; diff <(printf '%s\n' "${A}") <(printf '%s\n' "${B}"); } >> "${OUT}/detail"; }
  done
  for TOOL in fallback_text_string.sh san_text_string.sh; do
    [ -x "${REF}/${TOOL}" ] || continue
    A="$( cd "${TRIAL_DIR}" && ${TMO} "${REF}/${TOOL}" ./log/master.err 2>&1; echo "exit=$?" )"
    B="$( cd "${TRIAL_DIR}" && ${TMO} "${CUR}/${TOOL}" ./log/master.err 2>&1; echo "exit=$?" )"
    [ "${A}" != "${B}" ] && { printf '%s\t%s\n' "${TRIAL_DIR}" "${TOOL}" >> "${OUT}/diffs"
      { echo "--- ${TRIAL_DIR} ${TOOL}"; diff <(printf '%s\n' "${A}") <(printf '%s\n' "${B}"); } >> "${OUT}/detail"; }
  done
  if [ "${GDB}" -eq 1 ]; then
    A="$( cd "${TRIAL_DIR}" && ${TMO} "${REF}/new_text_string.sh" 2>&1; echo "exit=$?" )"
    B="$( cd "${TRIAL_DIR}" && ${TMO} "${CUR}/new_text_string.sh" 2>&1; echo "exit=$?" )"
    # The two sides run one after the other, and the automation deletes trials while
    # this runs. A trial that went away in between gives one side a core and the other
    # nothing, which is not a difference between the two versions
    [ "${A}" != "${B}" ] && [ -d "${TRIAL_DIR}" ] && { printf '%s\tnew_text_string.sh\n' "${TRIAL_DIR}" >> "${OUT}/diffs"
      { echo "--- ${TRIAL_DIR} new_text_string.sh"; diff <(printf '%s\n' "${A}") <(printf '%s\n' "${B}"); } >> "${OUT}/detail"; }
  fi
  printf '.' >> "${OUT}/progress"
}
export -f run_one

touch "${WORK}/diffs" "${WORK}/detail" "${WORK}/progress"
CORES="$(nproc 2>/dev/null || echo 4)"
[ "${CORES}" -gt 16 ] && CORES=16
xargs -a "${WORK}/trials" -r -d '\n' -P "${CORES}" -I{} \
  bash -c 'run_one "$1" "$2" "$3" "$4" "$5"' _ {} "${WORK}" "${REF_DIR}" "${SCRIPT_PWD}" "${USE_GDB}"

# capped_error_log.sh owns the cap size, and every caller that decides whether to
# build a temp directory holds its own copy of that number. A caller left behind
# stops capping logs between the two sizes, silently, so the numbers are compared
# here before anything else
echo
echo "=== Cap size check ==="
CAP_MAX="$(grep -m1 '^MAX_SIZE=' "${SCRIPT_PWD}/capped_error_log.sh" 2>/dev/null | sed 's|^MAX_SIZE=||;s|[^0-9].*||')"
if [ -z "${CAP_MAX}" ]; then
  echo "    FAIL: no MAX_SIZE found in ${SCRIPT_PWD}/capped_error_log.sh"
  printf 'capped_error_log.sh\tno MAX_SIZE found\n' >> "${WORK}/diffs"
else
  echo "    capped_error_log.sh MAX_SIZE: ${CAP_MAX}"
  for CAP_CALLER in new_text_string.sh san_text_string.sh fallback_text_string.sh error_log_scan.sh pquery-prep-red.sh; do
    CAP_SEEN="$(grep -h 'stat -Lc%s' "${SCRIPT_PWD}/${CAP_CALLER}" 2>/dev/null | grep -ohE -- '-gt [0-9]+' | sed 's|-gt ||' | sort -u | tr '\n' ' ' | sed 's| $||')"
    if [ "${CAP_SEEN}" != "${CAP_MAX}" ]; then
      echo "    FAIL: ${CAP_CALLER} tests against '${CAP_SEEN}', not ${CAP_MAX}"
      printf '%s\tcap size out of step with capped_error_log.sh\n' "${CAP_CALLER}" >> "${WORK}/diffs"
    fi
  done
fi

# Every trial in /data has a log well under the cap, so the comparison above never
# reaches capped_error_log.sh. This builds an oversized log instead: a real log
# with filler pushed into the middle of it, so capping has to drop that middle and
# keep both ends. The signature has to come out the same as for the log it was
# built from. The filler is sized from the cap, so the padded log is over it
# whatever the cap is set to
echo
echo "=== Oversized log check ==="
mkdir -p "${WORK}/cap"
CAP_FILLER_LINE='note: routine progress line, nothing of interest here'
CAP_FILLER_LINES=$(( ( ${CAP_MAX:-10485760} * 3 ) / ( ${#CAP_FILLER_LINE} + 1 ) ))
yes "${CAP_FILLER_LINE}" 2>/dev/null | head -"${CAP_FILLER_LINES}" > "${WORK}/cap/filler"
CAP_CHECKED=0
for TRIAL_DIR in $(head -n 40 "${WORK}/trials"); do
  [ "${CAP_CHECKED}" -ge 3 ] && break
  LOG="${TRIAL_DIR}/log/master.err"
  [ -r "${LOG}" ] || continue
  [ "$(stat -Lc%s "${LOG}" 2>/dev/null || echo 0)" -gt "${CAP_MAX:-10485760}" ] && continue
  NAME="$(basename "${TRIAL_DIR}")_${CAP_CHECKED}"
  mkdir -p "${WORK}/cap/${NAME}/plain/log" "${WORK}/cap/${NAME}/padded/log"
  cp "${LOG}" "${WORK}/cap/${NAME}/plain/log/master.err"
  HALF="$(( $(wc -l < "${LOG}") / 2 ))"
  { head -n "${HALF}" "${LOG}"; cat "${WORK}/cap/filler"; tail -n +"$(( HALF + 1 ))" "${LOG}"; } > "${WORK}/cap/${NAME}/padded/log/master.err"
  # A log reached through a symlink has to be measured at the file that is read,
  # not at the link, or it never gets capped at all
  mkdir -p "${WORK}/cap/${NAME}/linked/log"
  ln -sf "${WORK}/cap/${NAME}/padded/log/master.err" "${WORK}/cap/${NAME}/linked/log/master.err"
  for MODE in errors lastline top check clean aggregate; do
    A="$( cd "${WORK}/cap/${NAME}/plain"  && "${SCRIPT_PWD}/error_log_scan.sh" "${MODE}" ./log/master.err 2>&1; echo "exit=$?" )"
    B="$( cd "${WORK}/cap/${NAME}/padded" && "${SCRIPT_PWD}/error_log_scan.sh" "${MODE}" ./log/master.err 2>&1; echo "exit=$?" )"
    [ "${A}" != "${B}" ] && { printf '%s\toversized log, error_log_scan.sh %s\n' "${TRIAL_DIR}" "${MODE}" >> "${WORK}/diffs"
      { echo "--- ${TRIAL_DIR} oversized log, error_log_scan.sh ${MODE}"; diff <(printf '%s\n' "${A}") <(printf '%s\n' "${B}"); } >> "${WORK}/detail"; }
    C="$( cd "${WORK}/cap/${NAME}/linked" && "${SCRIPT_PWD}/error_log_scan.sh" "${MODE}" ./log/master.err 2>&1; echo "exit=$?" )"
    [ "${A}" != "${C}" ] && { printf '%s\toversized log through a symlink, error_log_scan.sh %s\n' "${TRIAL_DIR}" "${MODE}" >> "${WORK}/diffs"
      { echo "--- ${TRIAL_DIR} oversized log through a symlink, error_log_scan.sh ${MODE}"; diff <(printf '%s\n' "${A}") <(printf '%s\n' "${C}"); } >> "${WORK}/detail"; }
  done
  for TOOL in fallback_text_string.sh san_text_string.sh; do
    A="$( cd "${WORK}/cap/${NAME}/plain"  && "${SCRIPT_PWD}/${TOOL}" ./log/master.err 2>&1; echo "exit=$?" )"
    B="$( cd "${WORK}/cap/${NAME}/padded" && "${SCRIPT_PWD}/${TOOL}" ./log/master.err 2>&1; echo "exit=$?" )"
    [ "${A}" != "${B}" ] && { printf '%s\toversized log, %s\n' "${TRIAL_DIR}" "${TOOL}" >> "${WORK}/diffs"
      { echo "--- ${TRIAL_DIR} oversized log, ${TOOL}"; diff <(printf '%s\n' "${A}") <(printf '%s\n' "${B}"); } >> "${WORK}/detail"; }
  done
  rm -rf "${WORK}/cap/${NAME}"
  CAP_CHECKED=$(( CAP_CHECKED + 1 ))
done
rm -rf "${WORK}/cap"
echo "    ${CAP_CHECKED} logs padded past the cap and rechecked"

# A log can reach capped_error_log.sh by a path holding a '..', and joining that onto
# the output directory points the copy back out of it, onto a real file. Passed as
# ../<trial>/log/master.err the copy lands on the log itself, and the redirect empties
# it before anything is read. The log has to come back untouched
echo
echo "=== Output directory check ==="
mkdir -p "${WORK}/contain/out" "${WORK}/contain/real/log"
yes "${CAP_FILLER_LINE}" 2>/dev/null | head -"${CAP_FILLER_LINES}" > "${WORK}/contain/real/log/master.err"
CONTAIN_WAS="$(stat -Lc%s "${WORK}/contain/real/log/master.err" 2>/dev/null || echo 0)"
CONTAIN_GOT="$( cd "${WORK}/contain/out" && "${SCRIPT_PWD}/capped_error_log.sh" "${WORK}/contain/out" '../real/log/master.err' 2>/dev/null )"
CONTAIN_NOW="$(stat -Lc%s "${WORK}/contain/real/log/master.err" 2>/dev/null || echo 0)"
if [ "${CONTAIN_NOW}" != "${CONTAIN_WAS}" ]; then
  echo "    FAIL: the log was written to through a '..' path (${CONTAIN_WAS} -> ${CONTAIN_NOW} bytes)"
  printf 'capped_error_log.sh\ta .. path wrote outside the output directory\n' >> "${WORK}/diffs"
elif [ "${CONTAIN_GOT}" != '../real/log/master.err' ]; then
  echo "    FAIL: expected the log itself back, got '${CONTAIN_GOT}'"
  printf 'capped_error_log.sh\ta .. path did not hand the log back\n' >> "${WORK}/diffs"
else
  echo "    a '..' path leaves the log alone and hands it back"
fi
rm -rf "${WORK}/contain"

DIFF_COUNT="$(wc -l < "${WORK}/diffs")"
echo
if [ "${DIFF_COUNT}" -eq 0 ]; then
  echo "PASS: ${TRIAL_COUNT} trials, every UniqueID and exit code identical"
  exit 0
fi
echo "FAIL: ${DIFF_COUNT} differences over ${TRIAL_COUNT} trials"
echo
echo "=== Differences per tool ==="
awk -F'\t' '{n[$2]++} END{for(t in n) printf "%6d  %s\n", n[t], t}' "${WORK}/diffs" | sort -rn
echo
echo "=== First differences ==="
head -n 60 "${WORK}/detail"
cp "${WORK}/detail" "${PWD}/UniqueID_unit_test_differences.txt" 2>/dev/null && echo && echo "Full list written to ${PWD}/UniqueID_unit_test_differences.txt"
exit 1
