#!/bin/bash
# Created by Roel Van de Paar, MariaDB
# MSAN analog of buildall_san_slow.sh. Kept separate on purpose: buildall_san_slow.sh
# sed-flips the shared build_mdpsms_{dbg,opt}_san.sh scripts (USE_SAN/ASAN_OR_MSAN/USE_TSAN),
# so folding MSAN into it would leave those scripts set to MSAN and break other engineers'
# ASAN/TSAN runs. This script only ever touches the dedicated build_mdpsms_{dbg,opt}_msan.sh.
# Prerequisite: the MSAN instrumented libraries (/MSAN_libs) and clang-20; set up once with
# ~/mariadb-qa/msan.instrumentedlibs_ubuntu2404.sh (auto-run below when AUTO_BUILD_MSAN_LIBS=1).
# With FRESH_PULL=1 each enabled version is (re)cloned right before its build, so no separate
# cloneall.sh step is needed. All cloning and building happens in a private source workspace
# (${DIR}/msan_slow_src), so this script never touches the shared /test/<ver> source trees and can run
# concurrently with the other buildall scripts. Build scratch inside the workspace is
# <ver>_dbg_msan / <ver>_opt_msan. Between versions each build's tarballs are moved to /data/TARS and
# the extracted MSAN_*-{dbg,opt} basedirs are moved to this dir ready for use.

AUTO_BUILD_MSAN_LIBS=1  # 1: if the clang-20 toolchain and/or the instrumented /MSAN_libs are missing/incomplete, build them first via msan.instrumentedlibs_ubuntu2404.sh. 0: only pre-check, then abort with instructions.
FRESH_PULL=1            # 1: (re)clone each version right before building (clone.sh for CS, clone_es.sh for ES). 0: build the existing ${DIR}/<ver> as-is.
REMOVE_SOURCE_AFTER=1   # 1: remove the source tree after its builds finish, to reclaim disk between versions. 0: keep it.

BUILD_10_1=0
BUILD_10_2=0
BUILD_10_3=0
BUILD_10_4=0
BUILD_10_5=0
BUILD_10_6=1
BUILD_10_7=0
BUILD_10_8=0
BUILD_10_9=0
BUILD_10_10=0
BUILD_10_11=1
BUILD_11_0=0
BUILD_11_1=0
BUILD_11_2=0
BUILD_11_3=0
BUILD_11_4=1
BUILD_11_5=0
BUILD_11_6=0
BUILD_11_7=0
BUILD_11_8=1
BUILD_12_0=0
BUILD_12_1=0
BUILD_12_2=0
BUILD_12_3=1
BUILD_13_0=1
BUILD_13_1=1
BUILD_ES_10_5=0
BUILD_ES_10_6=1
BUILD_ES_11_4=1
BUILD_ES_11_8=1
BUILD_ES_12_3=1

# Restart inside a screen if this terminal session isn't one already
if [ "${STY}" == "" ]; then
  echo "Not a screen, restarting myself inside a screen"
  screen -admS "buildall_msan_slow" bash -c "$0;bash"
  sleep 1
  screen -d -r "buildall_msan_slow"
  return 2> /dev/null; exit 0
fi

# Pre-check the shared MSAN prerequisites (clang-20 toolchain + instrumented /MSAN_libs). MSAN builds
# link libc++/ssl/... from /MSAN_libs, so these must exist before any build below.
msan_prereq_ok(){
  for b in /usr/bin/clang-20 /usr/bin/clang++-20 /usr/bin/ld.lld-20; do [ -x "${b}" ] || return 1; done
  for lib in libc++.so libc++abi.so libssl.so libcrypto.so; do [ -e "/MSAN_libs/${lib}" ] || return 1; done
  return 0
}
if ! msan_prereq_ok; then
  echo "MSAN prerequisites missing: need the clang-20 toolchain and a populated /MSAN_libs (instrumented libc++/ssl/crypto/...)."
  if [ ${AUTO_BUILD_MSAN_LIBS} -eq 1 ]; then
    echo "AUTO_BUILD_MSAN_LIBS=1: building them now via msan.instrumentedlibs_ubuntu2404.sh (installs clang-20 + builds /MSAN_libs; one-off, slow)..."
    [ -d /MSAN_libs ] && sudo mv /MSAN_libs "/MSAN_libs.$(date +%Y%m%d%H%M%S).OLD"  # the builder refuses to run if /MSAN_libs already exists
    bash ~/mariadb-qa/msan.instrumentedlibs_ubuntu2404.sh
    if ! msan_prereq_ok; then echo "Error: /MSAN_libs / clang-20 still incomplete after the build; aborting."; exit 1; fi
  else
    echo "AUTO_BUILD_MSAN_LIBS=0: set it to 1 to auto-build, or run ~/mariadb-qa/msan.instrumentedlibs_ubuntu2404.sh manually first. Aborting."
    exit 1
  fi
fi

# Ensure the dedicated MSAN scripts are set for MSAN (idempotent; touches only the _msan scripts)
sed -i 's|^USE_SAN=[0-1]|USE_SAN=1|'           ~/mariadb-qa/build_mdpsms_opt_msan.sh ~/mariadb-qa/build_mdpsms_dbg_msan.sh
sed -i 's|^USE_TSAN=[0-1]|USE_TSAN=0|'         ~/mariadb-qa/build_mdpsms_opt_msan.sh ~/mariadb-qa/build_mdpsms_dbg_msan.sh
sed -i 's|^ASAN_OR_MSAN=[0-1]|ASAN_OR_MSAN=1|' ~/mariadb-qa/build_mdpsms_opt_msan.sh ~/mariadb-qa/build_mdpsms_dbg_msan.sh

DIR=${PWD}
TARS_DIR="/data/TARS"   # built tarballs are moved here between versions; the extracted basedirs are moved to ${DIR}
SRC_DIR="${DIR}/msan_slow_src"  # private source workspace: clones + build scratch live here, so the shared ${DIR}/<ver> trees are never touched
mkdir -p "${SRC_DIR}"

cleanup_dirs(){  # $1 = version dir; remove this version's MSAN build scratch (_dbg_msan/_opt_msan)
  rm -Rf "${SRC_DIR}/${1}_dbg_msan" "${SRC_DIR}/${1}_opt_msan"
}

deliver_basedirs(){  # move the extracted MSAN_* basedirs from ${SRC_DIR} to ${DIR}; a same-named dir in ${DIR} is replaced (same-day same-version rebuild)
  local D
  for D in "${SRC_DIR}"/MSAN_*; do
    [ -d "${D}" ] || continue
    rm -Rf "${DIR}/$(basename "${D}")"
    mv "${D}" "${DIR}/"
  done
}

archive_tars(){  # between versions: move the freshly-built tarballs to ${TARS_DIR} (skipped if absent, matching buildall_san_slow.sh)
  if [ -d "${TARS_DIR}" ]; then
    find "${SRC_DIR}" -maxdepth 1 -type f -name 'MSAN_*.tar.gz' -exec mv -t "${TARS_DIR}/" {} +
    sync
  fi
}

build_ver(){  # $1 = version dir under ${SRC_DIR} (e.g. 13.1, 12.3-es)
  local ver="$1"
  cd ${SRC_DIR}
  if [ ${FRESH_PULL} -eq 1 ]; then  # (re)clone fresh; clone.sh/clone_es.sh rm the old tree first and block until done
    case "${ver}" in
      *-es) ~/mariadb-qa/mariadb-build-qa/clone_es.sh "${ver%-es}" ;;  # ES: clone_es.sh <base> clones <base>-es (needs ~/.git-credentials)
      *)    ~/mariadb-qa/mariadb-build-qa/clone.sh "${ver}" ;;         # CS branch/trunk (13.1 -> main)
    esac
  fi
  if [ ! -d "${SRC_DIR}/${ver}" ]; then echo "Skipping ${ver}: no source tree (FRESH_PULL=0 with no tree, or clone failed)"; return; fi
  cleanup_dirs "${ver}"
  ( cd ${SRC_DIR}/${ver} && ~/mariadb-qa/build_mdpsms_opt_msan.sh ) &  # opt + dbg in parallel...
  ( cd ${SRC_DIR}/${ver} && ~/mariadb-qa/build_mdpsms_dbg_msan.sh ) &
  wait                                                                 # ...double wait for both
  cleanup_dirs "${ver}"                                                # remove build scratch immediately
  deliver_basedirs                                                     # move extracted basedirs to ${DIR}
  archive_tars                                                         # move tarballs to /data/TARS
  [ ${REMOVE_SOURCE_AFTER} -eq 1 ] && rm -Rf "${SRC_DIR}/${ver}"       # remove the source tree
}

buildall(){  # Newest first (larger builds first, to optimize initial time-till-ready-for-use)
  [ ${BUILD_13_1} -eq 1 ]   && build_ver 13.1
  [ ${BUILD_13_0} -eq 1 ]   && build_ver 13.0
  [ ${BUILD_ES_12_3} -eq 1 ] && build_ver 12.3-es
  [ ${BUILD_12_3} -eq 1 ]   && build_ver 12.3
  [ ${BUILD_12_2} -eq 1 ]   && build_ver 12.2
  [ ${BUILD_12_1} -eq 1 ]   && build_ver 12.1
  [ ${BUILD_12_0} -eq 1 ]   && build_ver 12.0
  [ ${BUILD_ES_11_8} -eq 1 ] && build_ver 11.8-es
  [ ${BUILD_11_8} -eq 1 ]   && build_ver 11.8
  [ ${BUILD_11_7} -eq 1 ]   && build_ver 11.7
  [ ${BUILD_11_6} -eq 1 ]   && build_ver 11.6
  [ ${BUILD_11_5} -eq 1 ]   && build_ver 11.5
  [ ${BUILD_ES_11_4} -eq 1 ] && build_ver 11.4-es
  [ ${BUILD_11_4} -eq 1 ]   && build_ver 11.4
  [ ${BUILD_11_3} -eq 1 ]   && build_ver 11.3
  [ ${BUILD_11_2} -eq 1 ]   && build_ver 11.2
  [ ${BUILD_11_1} -eq 1 ]   && build_ver 11.1
  [ ${BUILD_11_0} -eq 1 ]   && build_ver 11.0
  [ ${BUILD_10_11} -eq 1 ]  && build_ver 10.11
  [ ${BUILD_10_10} -eq 1 ]  && build_ver 10.10
  [ ${BUILD_10_9} -eq 1 ]   && build_ver 10.9
  [ ${BUILD_10_8} -eq 1 ]   && build_ver 10.8
  [ ${BUILD_10_7} -eq 1 ]   && build_ver 10.7
  [ ${BUILD_ES_10_6} -eq 1 ] && build_ver 10.6-es
  [ ${BUILD_10_6} -eq 1 ]   && build_ver 10.6
  [ ${BUILD_ES_10_5} -eq 1 ] && build_ver 10.5-es
  [ ${BUILD_10_5} -eq 1 ]   && build_ver 10.5
  [ ${BUILD_10_4} -eq 1 ]   && build_ver 10.4
  [ ${BUILD_10_3} -eq 1 ]   && build_ver 10.3
  [ ${BUILD_10_2} -eq 1 ]   && build_ver 10.2
  [ ${BUILD_10_1} -eq 1 ]   && build_ver 10.1
}

buildall
rmdir "${SRC_DIR}" 2>/dev/null  # remove the workspace if empty (leftover trees/scratch from aborted builds are kept for inspection)
