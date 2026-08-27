#!/bin/bash
# Created by Claude, for Claude work at MariaDB
# Run one MTR testcase against every gendirs.sh BASEDIR and write a Bug Detection Matrix.
# Complements /test/mtr_testrun.sh: it takes a suite-qualified test name, so a test in
# suite/galera (or any other suite) is reachable, and it runs the builds in parallel.

SCRIPT_NAME="$(basename "${0}")"

if [ -z "${1}" ]; then
  echo
  echo "Expected usage:"
  echo "  ${SCRIPT_NAME} {MTR testcase} [suite] [gendirs.sh options] [parallel jobs]"
  echo "For example:"
  echo "  ${SCRIPT_NAME} MDEV-12345.test"
  echo "  ${SCRIPT_NAME} galera_ctas_partition.test galera '' 6"
  echo "  ${SCRIPT_NAME} MDEV-12345.test main SAN 4"
  echo
  echo "* The gendirs.sh option picks the build set: empty for the CS, ES and MySQL"
  echo "  builds without a sanitizer, SAN for the UBASAN builds, MSAN for MSAN, TSAN"
  echo "  for TSAN, VAL for Valgrind, GAL for Galera, M or MDEV for the feature builds,"
  echo "  and ALL for the default set plus the sanitizer, Galera and monty builds."
  echo "* ./mtra is used whenever the BASEDIR has it, so the ASAN, UBSAN, MSAN and TSAN"
  echo "  options are set. A BASEDIR without ./mtra falls back to ./mtr."
  echo "* The testcase is copied into every BASEDIR. With no suite it goes to the main"
  echo "  suite; with a suite it goes to that suite's t/ directory and MTR is called as"
  echo "  'suite.test', which is the only way a non-main test is selected."
  echo "* A matching .result file beside the testcase is copied to the suite's r/ directory."
  echo "* A matching .cnf file beside the testcase is copied next to the testcase."
  echo "* The testcase must be reverse-gated: it fails while the bug is present and passes"
  echo "  once it is fixed. Without that every row reads 'No'."
  echo "* A row reads 'No (gate did not trigger)' when the statement the gate expects to"
  echo "  fail did not fail, so that build does not have the bug. A 'Yes' carries the line"
  echo "  it failed on, so a row that stopped earlier than the others stands out."
  echo "* Give the testcase a non-generic name so MTR selects one test only."
  echo "* Each BASEDIR's mysql-test/var is removed before its run, as mtr_testrun.sh does."
  echo "* Set WSREP_PROVIDER before running a galera-suite test."
  echo "* Default parallel jobs is 48, capped at the number of BASEDIRs, so a normal"
  echo "  sweep runs in one wave. Each job asks MTR for a free port range, so the jobs"
  echo "  do not collide with each other nor with another MTR run on this box."
  exit 1
elif [ ! -r "${1}" ]; then
  echo "Assert: ${1} could not be read by this script"
  exit 1
elif [ ! -r /test/gendirs.sh ]; then
  echo "Assert: /test/gendirs.sh could not be read by this script. It is required."
  exit 1
fi

TESTFILE="$(readlink -f "${1}")"
TEST="$(basename "${TESTFILE}" .test)"
SUITE="${2}"
GENOPT="${3}"
JOBS="${4:-48}"
RESULTFILE="${TESTFILE%.test}.result"
CNFFILE="${TESTFILE%.test}.cnf"
REPORT="${PWD}/report.log"

if [ -z "${SUITE}" ]; then MTRTEST="${TEST}"; else MTRTEST="${SUITE}.${TEST}"; fi

export MTR_PRINT_CORE=no    # skip MTR's slow inline gdb; the matrix stage uses ~/t on saved cores
export DEBUGINFOD_URLS=     # Ubuntu sets this system-wide; llvm-symbolizer then stalls per SAN report

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# gendirs.sh lists with a relative ls and reads REGEX_EXCLUDE from the current directory,
# so it has to run in /test.
# Every gendirs.sh mode is kept, so a sanitizer, Galera or feature build is listed
# as well as a plain one. A line is kept when it is a directory in /test.
( cd /test && ./gendirs.sh "${GENOPT}" 2>/dev/null ) | while read -r DIR; do
  [ -d "/test/${DIR}" ] && echo "${DIR}"
done > "${WORK}/blist"
if [ ! -s "${WORK}/blist" ]; then
  echo "Assert: gendirs.sh '${GENOPT}' returned no BASEDIRs"
  exit 1
fi

echo "Testcase   : ${TESTFILE}"
echo "MTR name   : ${MTRTEST}"
echo "BASEDIRs   : $(grep -c '' "${WORK}/blist") (gendirs.sh '${GENOPT}')"
BCOUNT="$(grep -c '' "${WORK}/blist")"
[ "${JOBS}" -gt "${BCOUNT}" ] && JOBS="${BCOUNT}"
echo "Parallel   : ${JOBS}"
echo

# One build. SLOT only keeps the per-build output files apart; the ports come from MTR.
run_one() {
  local LINE="$1" SLOT="$2"
  local MTRDIR=
  # The test directory is mariadb-test on newer MariaDB and mysql-test on older
  # MariaDB and on every MySQL build, so both names are checked.
  if [ -d "/test/${LINE}/mariadb-test" ]; then MTRDIR="/test/${LINE}/mariadb-test"
  elif [ -d "/test/${LINE}/mysql-test" ]; then MTRDIR="/test/${LINE}/mysql-test"
  else echo "SKIP ${LINE} (no mariadb-test nor mysql-test)"; return; fi

  # ./mtra exports the ASAN, UBSAN, MSAN and TSAN options and then calls ./mtr, so it
  # is used whenever it is there. A BASEDIR without it falls back to ./mtr.
  if [ ! -x "${MTRDIR}/mtr" ]; then
    echo "SKIP ${LINE} (no ./mtr - run ~/mariadb-qa/startup.sh in the BASEDIR)"; return
  fi
  local RUNNER=./mtr
  [ -x "${MTRDIR}/mtra" ] && RUNNER=./mtra

  local TDIR RDIR
  if [ -z "${SUITE}" ]; then
    TDIR="${MTRDIR}/main"; RDIR="${MTRDIR}/main"
    if [ ! -d "${TDIR}" ] && [ -d "${MTRDIR}/t" ]; then TDIR="${MTRDIR}/t"; RDIR="${MTRDIR}/r"; fi
  else
    TDIR="${MTRDIR}/suite/${SUITE}/t"; RDIR="${MTRDIR}/suite/${SUITE}/r"
  fi
  if [ ! -d "${TDIR}" ]; then echo "SKIP ${LINE} (no ${TDIR})"; return; fi

  cp "${TESTFILE}" "${TDIR}/"
  [ -r "${RESULTFILE}" ] && [ -d "${RDIR}" ] && cp "${RESULTFILE}" "${RDIR}/"
  [ -r "${CNFFILE}" ] && cp "${CNFFILE}" "${TDIR}/"

  # Each BASEDIR has its own var/, so parallel builds do not share it. MTR_BUILD_THREAD
  # is left on auto: MTR then takes a free port range under its own lock file, which is
  # what keeps this sweep apart from any other MTR run on this box. A hand-picked thread
  # number does not, as auto starts at 300 as well.
  local VAR="${MTRDIR}/var"
  rm -rf "${VAR}"
  local OUT="${WORK}/out.${SLOT}.${LINE}"
  ( cd "${MTRDIR}" && MTR_BUILD_THREAD=auto timeout 900 "${RUNNER}" "${MTRTEST}" ) > "${OUT}" 2>&1

  # Verdict. A passing run is 'No' whatever the error log holds - a galera run always
  # logs a WSREP_WARNING at startup, and ~/t would report that as a UniqueID.
  local VERDICT='No'
  if ! grep -q 'Completed: All' "${OUT}"; then
    local STR= FAIL
    # ~/t exits 0 only when it produced a UniqueID, so the exit code is the gate here.
    if STR="$(cd "${MTRDIR}" && ~/t 2>/dev/null)"; then
      STR="$(echo "${STR}" | grep -vEi 'no error log|no core file found|no relevant strings were found|no parsable frames|please add a typed prefix rule|^Assert:|^WSREP_WARNING\|' | head -n1)"
    else
      STR=
    fi
    # A reverse gate fails on its --die or on the error it expects, which mysqltest
    # reports as "At line N: <text>".
    local LINENO_FAIL
    FAIL="$(grep -m1 -oE 'At line [0-9]+: .*' "${OUT}" | sed 's|^At line [0-9]*: ||')"
    LINENO_FAIL="$(grep -m1 -oE 'At line [0-9]+' "${OUT}" | grep -oE '[0-9]+')"
    # A crash carries a real UniqueID, and that is registrable with kb, so it is shown
    # in full. A die is not a UniqueID, so the cell stays a plain Yes, with the line it
    # failed on: a row that failed on a different line than the others never reached the
    # gate, so its Yes says nothing about the bug.
    if [ -n "${STR}" ]; then
      VERDICT="${STR}"
    elif echo "${FAIL}" | grep -q 'succeeded - should have failed'; then
      # The statement the gate expects to fail did not fail, so the bug is not present.
      VERDICT="No (gate did not trigger, line ${LINENO_FAIL})"
    elif [ -n "${FAIL}" ]; then
      VERDICT="Yes (line ${LINENO_FAIL})"
    else
      VERDICT='Yes (run did not complete)'
    fi
  fi

  # Matrix row, from the framework's own version helper, run where MTR ran.
  ( cd "${MTRDIR}"
    source "${HOME}/mariadb-qa/version_chk_helper.source" 2>/dev/null
    printf "%-3s %-6s %-4s %-7s %-41s %s\n" "${SVR}" "$(echo "${SERVER_VERSION}" | grep -o '[0-9]\+\.[0-9]\+')" "${BUILD_TYPE_SHORT}" "${BUILD_DATE_SHORT}" "${SOURCE_CODE_REV}" "${VERDICT}"
  ) | sed 's|[[:space:]]*$||' >> "${WORK}/matrix"
  # A real UniqueID (crash, assert, sanitizer) earns a representative stack in the report.
  case "${VERDICT}" in
    'No'|'No ('*|'Yes'|'Yes ('*) ;;
    *) printf '%s\t%s\n' "${VERDICT}" "${MTRDIR}" >> "${WORK}/crash" ;;
  esac
  echo "DONE ${LINE} -> ${VERDICT}"
}

SLOT=0
while read -r LINE; do
  while [ "$(jobs -rp | grep -c '')" -ge "${JOBS}" ]; do sleep 1; done
  SLOT=$((SLOT + 1))
  run_one "${LINE}" "${SLOT}" &
done < "${WORK}/blist"
wait

{
  echo '-------------------- BUG REPORT (b-style) --------------------'
  echo '{code:sql}'
  grep -v --binary-files=text '^$' "${TESTFILE}"
  echo -e '{code}\n'
  # stack.sh wraps a stack in its own {noformat} block. With no core it prints a plain
  # INFO line instead, which is not paste-ready, so a block is kept only when it carries
  # the tags. bug_report.sh checks the same way.
  STACKS=
  if [ -s "${WORK}/crash" ]; then
    STACKS="$(sort -u -t"$(printf '\t')" -k1,1 "${WORK}/crash" | while IFS="$(printf '\t')" read -r SIG MTRD; do
      STACK="$(cd "${MTRD}" && bash "${HOME}/mariadb-qa/stack.sh" 2>/dev/null)"
      echo "${STACK}" | grep -q '{noformat:title' && printf '%s\n\n' "${STACK}"
    done)"
  fi
  if [ -n "${STACKS}" ]; then
    echo -e 'Leads to:\n'
    echo "${STACKS}"
  fi
  if [ -z "${GENOPT}" ]; then
    echo '{noformat:title=Bug Detection Matrix}'
  else
    echo "{noformat:title=Bug Detection Matrix (${GENOPT^^})}"
  fi
  printf "%-3s %-6s %-4s %-7s %-41s %s\n" "" "Rel" "o/d" "Build" "Commit" "Affected" | sed 's|[[:space:]]*$||'
  sort -V "${WORK}/matrix"
  echo '{noformat}'
} | tee "${REPORT}"

echo
echo "Bug report written to ${REPORT}"
