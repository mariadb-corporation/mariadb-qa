#!/bin/bash
# Created by Roel Van de Paar, MariaDB
# Dry run of the clone and buildall scripts: nothing is cloned or built, and no screen starts
# The scripts run in a fake home with stub build scripts, and in a fake test dir with empty source dirs
# git, sudo, screen, sync and sleep are stubbed. Each clone or build call becomes one output line
# Usage: dry_run.sh <dir with clone.sh, cloneall.sh, buildall_*.sh> [clone_all_full_for_bisect.sh]
# Compare old and new: diff <(dry_run.sh <old dir> <old bisect script>) <(dry_run.sh <new dir> <new bisect script>)

SRC="$(readlink -f "${1}")"
BISECT="${2:+$(readlink -f "${2}")}"
if [ ! -r "${SRC}/clone.sh" -o ! -r "${SRC}/cloneall.sh" ]; then echo "Assert: clone.sh or cloneall.sh not found in '${1}'"; exit 1; fi
unset USE_TSAN EXTRA_AUTO_OPTIONS
W="$(mktemp -d /tmp/dry_run.XXXXXX)"
trap 'rm -Rf "${W}"' EXIT
export LOG="${W}/log"
mkdir -p "${W}/bin" "${W}/home/mariadb-qa/mariadb-build-qa"

cat > "${W}/bin/git" <<'EOF'
#!/bin/bash
echo "git $*" >> "${LOG}"
if [ "${1}" == "clone" ]; then mkdir -p "${@: -1}"; fi
EOF
printf '#!/bin/bash\necho "sudo $*" >> "${LOG}"\n' > "${W}/bin/sudo"
printf '#!/bin/bash\necho "screen $*" >> "${LOG}"\n' > "${W}/bin/screen"
printf '#!/bin/bash\n' > "${W}/bin/sync"
printf '#!/bin/bash\n' > "${W}/bin/sleep"
for V in dbg opt dbg_san opt_san dbg_msan opt_msan dbg_valgrind opt_valgrind; do
  printf '#!/bin/bash\necho "build_mdpsms_%s.sh $(basename "${PWD}")${USE_TSAN:+ USE_TSAN=${USE_TSAN}}${EXTRA_AUTO_OPTIONS:+ EXTRA_AUTO_OPTIONS=${EXTRA_AUTO_OPTIONS}}" >> "${LOG}"\n' "${V}" > "${W}/home/mariadb-qa/build_mdpsms_${V}.sh"
done
cp "${SRC}/clone.sh" "${SRC}/clone_es.sh" "${W}/home/mariadb-qa/mariadb-build-qa/"  # The msan and tsan slow scripts call these by their home path
: > "${W}/home/mariadb-qa/mariadb-build-qa/credentials_helper.source"  # No credentials check
chmod +x "${W}"/bin/* "${W}"/home/mariadb-qa/*.sh "${W}"/home/mariadb-qa/mariadb-build-qa/*.sh

# One empty source dir for each version a buildall script names
VERS="$(grep -ohE '(\$\{(DIR|PWD)\}/|build_ver )[0-9]+\.[0-9]+(-es)?' "${SRC}"/buildall_*.sh | sed 's|.* ||;s|.*/||' | sort -uV)"

run(){  # $1 = label; the rest is the command, run in a fresh fake test dir
  local LABEL="${1}"; shift
  rm -Rf "${W}/test"; mkdir -p "${W}/test"
  for V in ${VERS}; do mkdir -p "${W}/test/${V}"; done
  : > "${LOG}"
  ( cd "${W}/test" && HOME="${W}/home" PATH="${W}/bin:${PATH}" STY=dry_run "$@" ) > /dev/null 2>&1
  echo "== ${LABEL} (exit $?)"
  if [[ "${LABEL}" == *_slow.sh ]]; then  # Sequential scripts: the build order counts too
    echo "order: $(awk '/^build_mdpsms/{print $2}' "${LOG}" | uniq | tr '\n' ' ')"
  fi
  sort -V "${LOG}"  # Parallel jobs log in random order
}

for S in "${SRC}"/buildall_*.sh; do
  T="${S}"
  if [ "$(basename "${S}")" == "buildall_msan_slow.sh" ]; then  # Skip its toolchain check, which reads the real /usr/bin and /MSAN_libs
    T="${W}/buildall_msan_slow.sh"
    sed 's|^msan_prereq_ok(){$|msan_prereq_ok(){ return 0;|' "${S}" > "${T}"
  fi
  run "$(basename "${S}")" bash -c 'source "${0}"; wait' "${T}"  # Sourced, so the wait covers the jobs it starts
done
run cloneall.sh bash -c 'cp "${1}" ./clone.sh; source "${0}"; wait' "${SRC}/cloneall.sh" "${SRC}/clone.sh"
TRUNK="$(grep -oE '^if \[ "\$\{1\}" == "[0-9]+\.[0-9]+" \]' "${SRC}/clone.sh" | grep -oE '[0-9]+\.[0-9]+')"
run "clone.sh ${TRUNK}" bash "${SRC}/clone.sh" "${TRUNK}"
if [ -n "${BISECT}" ]; then
  run "$(basename "${BISECT}")" bash -c 'source "${0}"; wait' "${BISECT}"
fi
