#!/usr/bin/env bash
# build_clang.sh - build a clean stable clang/llvm from source into /usr/local,
# including the binutils gold plugin (LLVMgold.so), remove any prior clang/llvm
# installs, and repoint the mariadb-qa sanitizer build scripts at it.
#
# Usage: build_clang.sh [llvm_version]   (default: 22.1.6, latest stable)
#
# ---------------------------------------------------------------------------
# Plain-english summary of what this solves and why
# ---------------------------------------------------------------------------
#
# Why LLVMgold.so matters
#   LLVMgold.so is the LLVM plugin that lets the GNU linkers (bfd ld and gold)
#   read the LLVM bitcode that clang produces when compiling with -flto. When a
#   link step uses -flto and is handled by GNU bfd ld, clang automatically adds
#   "-plugin <prefix>/lib/LLVMgold.so" to the linker. If that file is absent the
#   link fails with: "error loading plugin ... LLVMgold.so: cannot open shared
#   object file". The plugin must be the SAME LLVM major version as the clang
#   that emitted the bitcode, since bitcode is not stable across major versions.
#
# Why the apt clang packages do not provide it
#   From LLVM 18 onward the apt.llvm.org packages are built using the mold
#   linker, so their packaging no longer sets -DLLVM_BINUTILS_INCDIR and no
#   longer produces LLVMgold.so. The old llvm-17-linker-tools package still
#   shipped it, but that is LLVM 17 - a version mismatch against a v22 clang.
#   The gold linker itself is legacy (binutils gold is in maintenance mode), and
#   the modern LTO path is LLD/mold, which has built-in LTO and needs no plugin.
#   The only reliable way to get a matched-version LLVMgold.so is to build LLVM
#   from source with the binutils plugin headers available, which is what this
#   script does (-DLLVM_BINUTILS_INCDIR=/usr/include, from binutils-dev).
#
# Is this a MariaDB bug? No.
#   MariaDB builds correctly; this is a toolchain-completeness issue. A -flto
#   build under GNU binutils simply requires the matched gold plugin. MariaDB's
#   static-library merge (cmake/libutils.cmake) uses ar/ranlib, which is normal
#   libtool-style behavior. The sanitizer build scripts here do not pass -flto,
#   so the plugin is only consulted by LTO-enabled builds (WITH_LTO/packaging or
#   a bundled engine). MariaDB-side this can be sidestepped without any source
#   change by either (a) not building with -flto, or (b) when LTO is wanted,
#   pointing CMAKE_AR/CMAKE_RANLIB/CMAKE_NM at llvm-ar/llvm-ranlib/llvm-nm and
#   linking with lld, so bitcode is only ever handled by LLVM tools. Providing
#   the matched LLVMgold.so is the general fix that covers every case.
#
# How -fuse-ld=lld relates
#   -fuse-ld=lld is complementary, not a substitute. lld links with native LTO
#   and never needs the plugin, but it only governs the main link; cmake
#   try_compile checks and static-lib merges can still go through bfd ld. So the
#   sanitizer scripts keep -fuse-ld=lld for speed on the main link, while
#   LLVMgold.so covers any bfd-ld fallback. Keep both.

set -uo pipefail

LLVM_VERSION="${1:-22.1.6}"
LLVM_MAJOR="${LLVM_VERSION%%.*}"
PREFIX="/usr/local"
WORK="/test/llvm-build"
SRC="${WORK}/llvm-project"
BUILD="${WORK}/build"
JOBS="$(nproc)"
MIN_FREE_GB=18
QA_DIR="${HOME}/mariadb-qa"
SAN_SCRIPTS=(build_mdpsms_dbg_san.sh build_mdpsms_opt_san.sh)
OLD_RT_DIR="/usr/lib/llvm-21/lib/clang/21/lib/linux"

log()  { echo "[build_clang $(date +%H:%M:%S)] $*"; }
warn() { echo "[build_clang WARN] $*" >&2; }
die()  { echo "[build_clang FAIL] $*" >&2; exit 1; }
trap 'die "unexpected error at line ${LINENO}"' ERR

# --- 0. Preflight -----------------------------------------------------------
log "target LLVM ${LLVM_VERSION}, prefix ${PREFIX}, ${JOBS} jobs"
sudo -n true 2>/dev/null || die "passwordless sudo required"
for t in cmake ninja git; do command -v "$t" >/dev/null || die "missing tool: $t"; done
if [ ! -f /usr/include/plugin-api.h ]; then
  log "plugin-api.h absent; installing binutils-dev (needed for LLVMgold.so)"
  sudo apt-get update -qq && sudo apt-get install -y binutils-dev || die "binutils-dev install failed"
fi
avail_gb="$(df -BG --output=avail "$(dirname "$WORK")" | tail -1 | tr -dc '0-9')"
[ "${avail_gb:-0}" -ge "$MIN_FREE_GB" ] || die "only ${avail_gb}G free on $(dirname "$WORK"); need >= ${MIN_FREE_GB}G"

# --- 1. Source --------------------------------------------------------------
mkdir -p "$WORK"
if [ ! -d "${SRC}/.git" ]; then
  log "cloning llvmorg-${LLVM_VERSION} (shallow)"
  rm -rf "$SRC"
  git clone --depth 1 --branch "llvmorg-${LLVM_VERSION}" \
    https://github.com/llvm/llvm-project.git "$SRC" || die "clone failed (tag llvmorg-${LLVM_VERSION}?)"
else
  log "reusing existing source tree ${SRC}"
fi

# --- 2. Configure -----------------------------------------------------------
# Bootstrap with an existing clang when present, else gcc.
if command -v clang >/dev/null && command -v clang++ >/dev/null; then
  HOST_CC="$(command -v clang)"; HOST_CXX="$(command -v clang++)"; HOST_LD="lld"
else
  HOST_CC="$(command -v gcc)"; HOST_CXX="$(command -v g++)"; HOST_LD="gold"
fi
log "host compiler: ${HOST_CC}"
if [ "${FORCE_REBUILD:-0}" != "1" ] && [ -f "${BUILD}/lib/LLVMgold.so" ] && [ -x "${BUILD}/bin/clang" ]; then
  log "existing complete build found in ${BUILD}; skipping configure+build (FORCE_REBUILD=1 to override)"
else
rm -rf "$BUILD"; mkdir -p "$BUILD"
cmake -G Ninja -S "${SRC}/llvm" -B "$BUILD" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_C_COMPILER="$HOST_CC" \
  -DCMAKE_CXX_COMPILER="$HOST_CXX" \
  -DLLVM_USE_LINKER="$HOST_LD" \
  -DLLVM_ENABLE_PROJECTS="clang;lld" \
  -DLLVM_ENABLE_RUNTIMES="compiler-rt" \
  -DLLVM_TARGETS_TO_BUILD=X86 \
  -DLLVM_BINUTILS_INCDIR=/usr/include \
  -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF \
  -DCOMPILER_RT_BUILD_SANITIZERS=ON \
  -DLLVM_INSTALL_UTILS=ON \
  -DLLVM_ENABLE_ASSERTIONS=OFF \
  -DLLVM_INCLUDE_TESTS=OFF \
  -DLLVM_INCLUDE_EXAMPLES=OFF \
  -DLLVM_INCLUDE_BENCHMARKS=OFF \
  -DLLVM_PARALLEL_LINK_JOBS=8 \
  || die "cmake configure failed"

# --- 3. Build ---------------------------------------------------------------
log "building (this takes a while)"
ninja -C "$BUILD" -j "$JOBS" || die "ninja build failed"
GOLD_BUILT="$(find "$BUILD" -name LLVMgold.so -print -quit)"
[ -n "$GOLD_BUILT" ] || die "LLVMgold.so was not built; check LLVM_BINUTILS_INCDIR/plugin-api.h"
log "LLVMgold.so built at ${GOLD_BUILT}"
fi

# --- 4. Remove old toolchains ----------------------------------------------
log "removing prior clang/llvm installs"
# Match only version-suffixed LLVM toolchain packages (from apt.llvm.org), never
# bare system libs such as libunwind8. No autoremove: it cascades into unrelated
# packages (perf tools, tcmalloc, etc.) once a base lib is pulled.
old_pkgs="$(dpkg -l 2>/dev/null | awk '/^ii/{print $2}' \
  | grep -E '^(libpolly-[0-9]|llvm-[0-9]|llvm-toolchain|clang-[0-9]|clang-tools-[0-9]|clang-format-[0-9]|clang-tidy-[0-9]|libclang-[0-9]|libclang-common-[0-9]|libclang-cpp[0-9]|libclang1-[0-9]|libclang-rt-[0-9]|lld-[0-9]|lldb-[0-9]|libllvm[0-9]|liblldb-[0-9]|libomp-[0-9]|libomp[0-9]|libunwind-[0-9])' || true)"
if [ -n "$old_pkgs" ]; then
  log "apt purge (llvm-only): ${old_pkgs//$'\n'/ }"
  sudo apt-get purge -y $old_pkgs || warn "apt purge incomplete"
fi
sudo rm -rf /usr/lib/llvm-*
# Do NOT delete the prefix's own clang resource dir here: this script bootstraps
# with the existing /usr/local clang, and "ninja install" can re-touch a compile.
# Same-version files are overwritten by install; stale OTHER-version files under
# the prefix are pruned AFTER install (see step 5).
# stale symlinks
sudo rm -f /usr/bin/llvm-symbolizer-21 /usr/bin/ld.lld /usr/bin/ld.lld-21
# trim old apt.llvm.org channels (-17 / -21) so they are not reinstalled.
# Use @ as the s/// delimiter; | is taken by the (17|21) alternation.
for lst in /etc/apt/sources.list.d/*llvm*.list; do
  [ -f "$lst" ] || continue
  sudo sed -i -E 's@^(deb .*llvm-toolchain-[a-z]+-(17|21) .*)$@# \1@' "$lst"
done

# --- 5. Install -------------------------------------------------------------
log "installing to ${PREFIX}"
sudo ninja -C "$BUILD" install || die "ninja install failed"
sudo ldconfig
[ -f "${PREFIX}/lib/LLVMgold.so" ] || die "LLVMgold.so missing after install"
# Prune stale OTHER-version clang installs left under the prefix (safe now that
# the new toolchain is in place and nothing else compiles with the old one).
for d in "${PREFIX}/lib/clang"/*/; do
  [ -d "$d" ] || continue
  [ "$(basename "$d")" != "$LLVM_MAJOR" ] && { log "pruning stale ${d}"; sudo rm -rf "$d"; }
done
for f in "${PREFIX}/bin/"clang-[0-9]*; do
  [ -e "$f" ] || continue
  [ "$(basename "$f")" != "clang-${LLVM_MAJOR}" ] && { log "pruning stale ${f}"; sudo rm -f "$f"; }
done

# --- 6. Convenience symlinks in /usr/bin -----------------------------------
sudo ln -sf "${PREFIX}/bin/clang"            /usr/bin/clang
sudo ln -sf "${PREFIX}/bin/clang++"          /usr/bin/clang++
sudo ln -sf "${PREFIX}/bin/ld.lld"           /usr/bin/ld.lld
sudo ln -sf "${PREFIX}/bin/ld.lld"           /usr/bin/ld.lld-21
sudo ln -sf "${PREFIX}/bin/llvm-symbolizer"  /usr/bin/llvm-symbolizer

# --- 7. Repoint mariadb-qa sanitizer build scripts -------------------------
NEW_RT_DIR="$(${PREFIX}/bin/clang -print-runtime-dir)"
log "clang runtime dir: ${NEW_RT_DIR}"
for n in asan ubsan_standalone; do
  [ -f "${NEW_RT_DIR}/libclang_rt.${n}-x86_64.a" ] \
    || die "expected ${NEW_RT_DIR}/libclang_rt.${n}-x86_64.a not found"
done
for f in "${SAN_SCRIPTS[@]}"; do
  p="${QA_DIR}/${f}"
  [ -f "$p" ] || { warn "san script not found: $p"; continue; }
  cp -f "$p" "/tmp/${f}.pre_build_clang.bak"
  sed -i "s|${OLD_RT_DIR}|${NEW_RT_DIR}|g" "$p"
  if grep -q "${NEW_RT_DIR}/libclang_rt.asan-x86_64.a" "$p"; then
    log "updated ${f} -> ${NEW_RT_DIR}"
  else
    warn "${f}: sanitizer path not rewritten (already changed?)"
  fi
done

# --- 8. Self-test -----------------------------------------------------------
log "self-test: clang version + LLVMgold.so via bfd ld + sanitizers"
"${PREFIX}/bin/clang" --version | head -1
ct="$(mktemp /tmp/build_clang_test.XXXX.c)"; printf 'int main(){return 0;}\n' > "$ct"
"${PREFIX}/bin/clang" "$ct" -flto -fuse-ld=bfd -o "${ct}.out" \
  || die "self-test: -flto via bfd ld failed (LLVMgold.so problem)"
"${PREFIX}/bin/clang" "$ct" -fsanitize=address,undefined -o "${ct}.san" \
  || die "self-test: asan+ubsan link failed"
rm -f "$ct" "${ct}.out" "${ct}.san"
log "self-test passed"

# --- 9. Cleanup -------------------------------------------------------------
log "removing build tree to reclaim disk"
rm -rf "$WORK"

# --- 10. Report -------------------------------------------------------------
echo
log "DONE."
echo "  clang        : $(${PREFIX}/bin/clang --version | head -1)"
echo "  LLVMgold.so  : ${PREFIX}/lib/LLVMgold.so ($(stat -c%s "${PREFIX}/lib/LLVMgold.so") bytes)"
echo "  runtime dir  : ${NEW_RT_DIR}"
echo "  san scripts  : ${SAN_SCRIPTS[*]} repointed (backups in /tmp/*.pre_build_clang.bak)"
echo "  free on /    : $(df -BG --output=avail / | tail -1 | tr -d ' ')"
