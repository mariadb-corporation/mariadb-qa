#!/bin/bash
# Check that the box can build, run and debug MariaDB servers. Read-only.

set -u
WARN=0
FAIL=0
ok()   { echo "[ ok ] $*"; }
warn() { echo "[warn] $*"; WARN=$((WARN+1)); }
fail() { echo "[fail] $*"; FAIL=$((FAIL+1)); }

echo "MariaDB QA Framework Container - box check"
echo "-----------------------------------------"

ok "user $(id -un) uid=$(id -u) gid=$(id -g)"
if sudo -n true 2> /dev/null; then ok "sudo works without a password"; else fail "sudo needs a password"; fi

# Memory backed run directory. Trials and reducers run in /dev/shm
SHM_KB="$(df -k /dev/shm | awk 'NR==2 {print $2}')"
SHM_H="$(df -h /dev/shm | awk 'NR==2 {print $2}')"
if [ "${SHM_KB}" -ge 8388608 ]; then
  ok "/dev/shm is ${SHM_H}"
else
  warn "/dev/shm is only ${SHM_H}. Start the box with a larger --shm value"
fi

# Core files. The pattern is a host setting: a container cannot change it
CORE_LIMIT="$(ulimit -c)"
if [ "${CORE_LIMIT}" = "unlimited" ]; then
  ok "core file size is unlimited"
else
  fail "core file size is ${CORE_LIMIT}. Start the box with --ulimit core=-1"
fi
CORE_PATTERN="$(cat /proc/sys/kernel/core_pattern 2> /dev/null)"
case "${CORE_PATTERN}" in
  core|core.*) ok "host core pattern is '${CORE_PATTERN}'" ;;
  \|*)         fail "host core pattern pipes to '${CORE_PATTERN}'. Cores never reach the trial directory. Set kernel.core_pattern=core on the host" ;;
  *)           warn "host core pattern is '${CORE_PATTERN}'. Set kernel.core_pattern=core on the host" ;;
esac

NOFILE="$(ulimit -n)"
if [ "${NOFILE}" -ge 1048576 ]; then ok "open files limit is ${NOFILE}"; else warn "open files limit is ${NOFILE}, 1048576 is the target"; fi

STACK="$(ulimit -s)"
if [ "${STACK}" = "unlimited" ]; then
  warn "stack limit is unlimited, which breaks ASAN. 400000 is the target"
elif [ "${STACK}" -ge 400000 ]; then
  ok "stack limit is ${STACK} KB"
else
  warn "stack limit is ${STACK} KB, 400000 is the target for sanitizer builds"
fi

# Mapped directories
for D in /test /data; do
  if [ ! -w "${D}" ]; then
    fail "${D} is not writable"
  elif [ "$(stat -c %d /)" = "$(stat -c %d ${D})" ]; then
    warn "${D} is not mapped to the host. Its content is lost when the box is removed"
  else
    ok "${D} is mapped and writable"
  fi
done

# Toolchain
MISSING=""
for T in clang clang++ ld.lld llvm-symbolizer cmake ninja bison gdb screen valgrind rr; do
  command -v "${T}" > /dev/null 2>&1 || MISSING="${MISSING} ${T}"
done
if [ -z "${MISSING}" ]; then ok "build and debug tools present"; else fail "missing tools:${MISSING}"; fi
ok "$(clang --version | head -1)"
# A sanitizer build script that names a runtime archive by full path has to name
# the one of the clang in this box
RT_DIR="$(clang -print-runtime-dir 2> /dev/null)"
for S in build_mdpsms_dbg_san.sh build_mdpsms_opt_san.sh; do
  if grep -qs 'libclang_rt\.asan-x86_64\.a' "${HOME}/mariadb-qa/${S}" \
     && ! grep -qs "${RT_DIR}/libclang_rt.asan-x86_64.a" "${HOME}/mariadb-qa/${S}"; then
    warn "${S} names a clang runtime directory other than ${RT_DIR}. Run qa-upgrade clang"
  fi
done
if [ -x /usr/bin/clang-20 ]; then ok "clang-20 present, needed for MSAN builds"; else warn "clang-20 is missing, so MSAN builds cannot run"; fi
if [ -n "$(ls -A /MSAN_libs 2> /dev/null)" ]; then ok "/MSAN_libs holds the MSAN instrumented libraries"; else warn "/MSAN_libs is empty. Run qa-upgrade msan to build them"; fi
# An MSAN binary turns ASLR off through personality(). The default seccomp
# profile of a container blocks that call, and the binary then stops at once
if setarch -R /bin/true 2> /dev/null; then
  ok "an MSAN binary can turn ASLR off"
else
  warn "this container blocks personality(ADDR_NO_RANDOMIZE), so no MSAN binary can run. Start the box with the control script, which turns the seccomp profile off"
fi

# Framework
if [ -d "${HOME}/mariadb-qa" ]; then
  ok "mariadb-qa $(git -C ${HOME}/mariadb-qa log -1 --format='%h %cd' --date=short)"
else
  fail "${HOME}/mariadb-qa is missing"
fi
if [ -x "${HOME}/t" ] && [ -x "${HOME}/pr" ]; then ok "linkit has wired the home directory helpers"; else fail "home directory helpers are missing. Run ~/mariadb-qa/linkit"; fi
if grep -qs '^alias anc=' "${HOME}/.bashrc"; then ok "the framework aliases are in .bashrc"; else warn "the framework aliases are missing from .bashrc"; fi

for B in reducercpp/reducer revgen/revgen generatorcpp/generator; do
  if [ -x "${HOME}/mariadb-qa/${B}" ]; then ok "${B} is built"; else warn "${B} is not built. Run qa-tools"; fi
done

# Server builds
BASEDIRS="$( (cd /test 2> /dev/null && ./gendirs.sh ALLALL) 2> /dev/null | wc -l)"
if [ "${BASEDIRS}" -gt 0 ]; then
  ok "${BASEDIRS} server build(s) in /test"
else
  warn "no server build in /test yet. See the usage guide, step 2"
fi

if command -v claude > /dev/null 2>&1; then ok "$(claude --version)"; else warn "Claude Code is not installed in this image"; fi

echo "-----------------------------------------"
echo "warnings: ${WARN}  failures: ${FAIL}"
[ "${FAIL}" -eq 0 ]
