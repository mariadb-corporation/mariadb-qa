#!/bin/bash
# Clone the MariaDB sources and build them, in one command. Called through a
# short name, where the name picks the build flavour:
#
#   cb        Optimised plus debug builds       (buildall_slow.sh)
#   cb-san    UBSAN plus ASAN builds            (buildall_san_slow.sh)
#   cb-msan   MSAN builds                       (buildall_msan_slow.sh)
#   cb-tsan   TSAN builds                       (buildall_tsan_slow.sh)
#   cb-val    Valgrind builds                   (buildall_val_slow.sh)
#
# The version list of each build lives in the build script itself, and the list
# of trees to clone lives in cloneall.sh. Edit those first when you want other
# versions. Community sources need nothing; Enterprise sources need
# ~/.git-credentials, and are skipped when that file is absent.
#
# The build script puts itself in a screen. Reattach with: s buildall

set -u
FLAVOUR="$(basename "${0}")"
case "${FLAVOUR}" in
  cb|qa-clonebuild.sh|qa-clonebuild) BUILD_SCRIPT="buildall_slow.sh" ;;
  cb-san)                            BUILD_SCRIPT="buildall_san_slow.sh" ;;
  cb-msan)                           BUILD_SCRIPT="buildall_msan_slow.sh" ;;
  cb-tsan)                           BUILD_SCRIPT="buildall_tsan_slow.sh" ;;
  cb-val)                            BUILD_SCRIPT="buildall_val_slow.sh" ;;
  *) echo "unknown name ${FLAVOUR}. Use cb, cb-san, cb-msan, cb-tsan or cb-val"; exit 2 ;;
esac

cd /test || { echo "[cb] /test is missing"; exit 1; }
[ -x "./${BUILD_SCRIPT}" ] || { echo "[cb] /test/${BUILD_SCRIPT} is missing. Run linkit"; exit 1; }

echo "[cb] cloning the Community sources"
./cloneall.sh || { echo "[cb] cloneall.sh failed"; exit 1; }

if [ -r "${HOME}/.git-credentials" ]; then
  echo "[cb] cloning the Enterprise sources"
  ./cloneall_es.sh || echo "[cb] cloneall_es.sh failed, going on with the Community sources"
else
  echo "[cb] no ~/.git-credentials, so the Enterprise sources are skipped."
  echo "[cb] To add them: put a line https://<id>:<token>@github.com in that file,"
  echo "[cb] chmod 600 it, then run: git config --global credential.helper store"
fi

echo "[cb] starting ${BUILD_SCRIPT}. This takes hours and runs in a screen"
exec "./${BUILD_SCRIPT}"
