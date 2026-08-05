#!/bin/bash
# Rebuild the heavy parts of the box: clang from source, and the MSAN
# instrumented libraries. Both take about an hour. For the framework itself use
# qa-update, which is the everyday command.
#
#   qa-upgrade            Both parts
#   qa-upgrade clang      clang only. Add a version, for example: qa-upgrade clang 22.1.8
#   qa-upgrade msan       The MSAN instrumented libraries only

set -u
QA_DIR="${HOME}/mariadb-qa"
APT_LLVM_VERSION=20     # The MSAN scripts need this exact version, ref MDEV-38419
WHAT="${1:-all}"
VERSION="${2:-}"

upgrade_clang() {
  echo "[qa-upgrade] building clang from source. It uses /test/llvm-build and"
  echo "[qa-upgrade] needs at least 18 GB of free space there"
  sudo install -d -o "$(id -u)" -g "$(id -g)" /test/llvm-build
  "${QA_DIR}/build_clang.sh" ${VERSION} || return 1
  sudo rm -rf /test/llvm-build

  # build_clang.sh removes the apt clang packages and comments out the
  # apt.llvm.org lines. The MSAN builds still need apt clang, so it comes back
  for LIST in /etc/apt/sources.list.d/*llvm*.list; do
    [ -f "${LIST}" ] || continue
    sudo sed -i -E 's@^# (deb .*llvm-toolchain-)@\1@' "${LIST}"
  done
  sudo apt-get update -qq
  sudo apt-get install -y --no-install-recommends \
    clang-${APT_LLVM_VERSION} libc++-${APT_LLVM_VERSION}-dev \
    libc++abi-${APT_LLVM_VERSION}-dev libclang-rt-${APT_LLVM_VERSION}-dev \
    lld-${APT_LLVM_VERSION} llvm-${APT_LLVM_VERSION} || return 1
  echo "[qa-upgrade] clang: $(clang --version | head -1)"
  echo "[qa-upgrade] clang-${APT_LLVM_VERSION} for MSAN: $(clang-${APT_LLVM_VERSION} --version | head -1)"
}

upgrade_msan() {
  echo "[qa-upgrade] building the MSAN instrumented libraries"
  # The framework script needs to create /MSAN_libs itself, which a mapped
  # directory does not allow
  if mountpoint -q /MSAN_libs; then
    echo "[qa-upgrade] /MSAN_libs is mapped to the host, so it cannot be rebuilt here."
    echo "[qa-upgrade] Start a box without --msan, run qa-upgrade msan there, then copy"
    echo "[qa-upgrade] the result out with: docker cp <box>:/MSAN_libs <host directory>"
    return 1
  fi
  if [ -d /MSAN_libs ]; then
    sudo rm -rf /MSAN_libs.OLD
    sudo mv /MSAN_libs /MSAN_libs.OLD
    echo "[qa-upgrade] the previous set is now /MSAN_libs.OLD"
  fi
  "${QA_DIR}/msan.instrumentedlibs_ubuntu2404.sh" || return 1
  sudo rm -rf /MSAN_libs/build
  echo "[qa-upgrade] /MSAN_libs holds $(ls /MSAN_libs | wc -l) entries"
}

RC=0
case "${WHAT}" in
  clang) upgrade_clang || RC=1 ;;
  msan)  upgrade_msan  || RC=1 ;;
  all)   upgrade_clang || RC=1; upgrade_msan || RC=1 ;;
  *)     echo "usage: qa-upgrade [clang|msan|all] [clang version]"; exit 2 ;;
esac

[ ${RC} -eq 0 ] && echo "[qa-upgrade] done. Run qa-check to check the box."
exit ${RC}
