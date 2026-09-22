#!/bin/bash
# Created by Roel Van de Paar, MariaDB
# MSAN analog of buildall_san_slow.sh. Kept separate on purpose: buildall_san_slow.sh
# sed-flips the shared build_mdpsms_{dbg,opt}_san.sh scripts (USE_SAN/ASAN_OR_MSAN/USE_TSAN),
# so folding MSAN into it would leave those scripts set to MSAN and break other engineers'
# ASAN/TSAN runs. This script only ever touches the dedicated build_mdpsms_{dbg,opt}_msan.sh.
# Prerequisite: the MSAN instrumented libraries (/MSAN_libs) and clang-20; set up once with
# ~/mariadb-qa/msan.instrumentedlibs_ubuntu2404.sh (auto-run below when AUTO_BUILD_MSAN_LIBS=1).
# The enabled versions are built in place from the ${DIR}/<ver> source trees, as buildall_san_slow.sh
# does; a version with no tree is cloned first (CLONE_IF_MISSING=1) and that clone is removed again
# once its builds finish (REMOVE_CLONED_SOURCE=1), to reclaim disk between versions. A tree which was
# already there is used as-is and never removed or re-cloned; to refresh the trees, run cloneall.sh
# first. The build scratch is <ver>_dbg_msan / <ver>_opt_msan, distinct from the plain (_dbg/_opt) and
# ub/asan (_dbg_san/_opt_san) scratch, so this can run concurrently with buildall_slow.sh and
# buildall_san_slow.sh. Do not run it alongside buildall_dbg_msan.sh or buildall_opt_msan.sh: those
# share the MSAN scratch names and wipe them at start. Between versions each build's tarballs are moved
# to /data/TARS; the extracted MSAN_*-{dbg,opt} basedirs stay in this dir ready for use.

AUTO_BUILD_MSAN_LIBS=1  # 1: if the clang-20 toolchain and/or the instrumented /MSAN_libs are missing/incomplete, build them first via msan.instrumentedlibs_ubuntu2404.sh. 0: only pre-check, then abort with instructions.
CLONE_IF_MISSING=1      # 1: clone a version which has no ${DIR}/<ver> source tree (clone.sh for CS, clone_es.sh for ES). 0: skip that version.
REMOVE_CLONED_SOURCE=1  # 1: remove a source tree this script cloned, once its builds finish, to reclaim disk between versions. A tree which was already there is never removed. 0: keep it.

BUILD_10_1=0
BUILD_10_2=0
BUILD_10_3=0
BUILD_10_4=0
BUILD_10_5=0
BUILD_10_6=0
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
TARS_DIR="/data/TARS"   # built tarballs are moved here between versions; the build scripts leave the extracted basedirs in ${DIR}

cleanup_dirs(){  # $1 = version dir; remove this version's MSAN build scratch (_dbg_msan/_opt_msan)
  rm -Rf "${DIR}/${1}_dbg_msan" "${DIR}/${1}_opt_msan"
}

archive_tars(){  # between versions: move the freshly-built tarballs to ${TARS_DIR} (skipped if absent)
  if [ -d "${TARS_DIR}" ]; then
    find "${DIR}" -maxdepth 1 -type f -name 'MSAN_*.tar.gz' -exec mv -t "${TARS_DIR}/" {} +
    sync
  fi
}

build_ver(){  # $1 = version dir under ${DIR} (e.g. 13.1, 12.3-es)
  local ver="$1"
  local cloned=0
  cd ${DIR}
  if [ ! -d "${DIR}/${ver}" ] && [ ${CLONE_IF_MISSING} -eq 1 ]; then  # clone.sh/clone_es.sh clone into ${PWD} and block until done
    cloned=1
    case "${ver}" in
      *-es) ~/mariadb-qa/mariadb-build-qa/clone_es.sh "${ver%-es}" ;;  # ES: clone_es.sh <base> clones <base>-es (needs ~/.git-credentials)
      *)    ~/mariadb-qa/mariadb-build-qa/clone.sh "${ver}" ;;         # CS branch/trunk (13.1 -> main)
    esac
  fi
  if [ ! -d "${DIR}/${ver}" ]; then echo "Skipping ${ver}: no source tree (CLONE_IF_MISSING=0, or clone failed)"; return; fi
  cleanup_dirs "${ver}"
  ( cd ${DIR}/${ver} && ~/mariadb-qa/build_mdpsms_opt_msan.sh ) &  # opt + dbg in parallel...
  ( cd ${DIR}/${ver} && ~/mariadb-qa/build_mdpsms_dbg_msan.sh ) &
  wait                                                             # ...double wait for both
  cleanup_dirs "${ver}"                                            # remove build scratch immediately
  archive_tars                                                     # move tarballs to /data/TARS
  if [ ${cloned} -eq 1 ] && [ ${REMOVE_CLONED_SOURCE} -eq 1 ]; then
    rm -Rf "${DIR}/${ver}"                                         # remove this script's own clone; a pre-existing tree is left alone
  fi
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
