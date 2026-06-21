#!/usr/bin/env bash
# build_clang.sh - build a clean stable clang/llvm from source into /usr/local,
# including the binutils gold plugin (LLVMgold.so), remove any prior clang/llvm
# installs, and repoint the mariadb-qa sanitizer build scripts at it.
#
# Usage: build_clang.sh [llvm_version]   (default: latest stable, auto-discovered)
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

# Version to build: defaults to the latest stable LLVM release (auto-discovered in
# preflight from upstream tags); pass an explicit llvmorg version as $1 to pin it.
LLVM_VERSION="${1:-}"
PREFIX="/usr/local"
WORK="/test/llvm-build"
SRC="${WORK}/llvm-project"
BUILD="${WORK}/build"
JOBS="$(nproc)"
MIN_FREE_GB=18
QA_DIR="${HOME}/mariadb-qa"
SAN_SCRIPTS=(build_mdpsms_dbg_san.sh build_mdpsms_opt_san.sh)

log()  { echo "[build_clang $(date +%H:%M:%S)] $*"; }
warn() { echo "[build_clang WARN] $*" >&2; }
die()  { echo "[build_clang FAIL] $*" >&2; exit 1; }
trap 'die "unexpected error at line ${LINENO}"' ERR

# --- 0. Preflight -----------------------------------------------------------
sudo -n true 2>/dev/null || die "passwordless sudo required"
for t in cmake ninja git; do command -v "$t" >/dev/null || die "missing tool: $t"; done
# Resolve the version to build: default = highest stable llvmorg-X.Y.Z tag upstream
# (release-candidate and -init tags are excluded by the pure X.Y.Z match).
if [ -z "$LLVM_VERSION" ]; then
  log "discovering latest stable LLVM release tag"
  LLVM_VERSION="$(git ls-remote --tags --refs https://github.com/llvm/llvm-project.git 'llvmorg-*' 2>/dev/null \
    | sed -n 's#.*/llvmorg-\([0-9]\+\.[0-9]\+\.[0-9]\+\)$#\1#p' | sort -V | tail -1 || true)"
  [ -n "$LLVM_VERSION" ] || die "could not determine latest stable LLVM release (network down?)"
fi
LLVM_MAJOR="${LLVM_VERSION%%.*}"
log "target LLVM ${LLVM_VERSION}, prefix ${PREFIX}, ${JOBS} jobs"
if [ ! -f /usr/include/plugin-api.h ]; then
  log "plugin-api.h absent; installing binutils-dev (needed for LLVMgold.so)"
  sudo apt-get update -qq && sudo apt-get install -y binutils-dev || die "binutils-dev install failed"
fi
avail_gb="$(df -BG --output=avail "$(dirname "$WORK")" | tail -1 | tr -dc '0-9')"
[ "${avail_gb:-0}" -ge "$MIN_FREE_GB" ] || die "only ${avail_gb}G free on $(dirname "$WORK"); need >= ${MIN_FREE_GB}G"

# --- 1. Source --------------------------------------------------------------
mkdir -p "$WORK"
want_tag="llvmorg-${LLVM_VERSION}"
have_tag=""
[ -d "${SRC}/.git" ] && have_tag="$(git -C "$SRC" describe --tags --exact-match 2>/dev/null || true)"
if [ "$have_tag" = "$want_tag" ]; then
  log "reusing existing source tree ${SRC} (${want_tag})"
else
  # Version changed (or no tree yet): drop any stale source AND build so a
  # leftover tree from an interrupted run cannot install the wrong version.
  log "cloning ${want_tag} (shallow)"
  rm -rf "$SRC" "$BUILD"
  git clone --depth 1 --branch "$want_tag" \
    https://github.com/llvm/llvm-project.git "$SRC" || die "clone failed (tag ${want_tag}?)"
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
# Record version-suffixed symbolizer links already present (left by a prior apt
# clang). Their suffix is the path baked into legacy SAN binaries still under test;
# the apt purge below removes the package-owned ones, so they are recreated against
# the freshly built symbolizer in step 6 to keep those binaries symbolizing.
EXISTING_SUFFIXED_SYMBOLIZERS=()
for s in /usr/bin/llvm-symbolizer-* /usr/local/bin/llvm-symbolizer-*; do
  if [ -e "$s" ]; then EXISTING_SUFFIXED_SYMBOLIZERS+=("$s"); fi
done
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
# stale linker symlinks (ld.lld is recreated in step 6; ld.lld-21 is unused). The
# suffixed symbolizers captured above are deliberately left for step 6 to re-link.
sudo rm -f /usr/bin/ld.lld /usr/bin/ld.lld-21
# Comment out version-suffixed apt.llvm.org channels so an apt upgrade cannot
# reinstall a packaged clang/llvm that would shadow this source build. The
# unversioned channel is left active. @ is the s/// delimiter (URLs contain /).
for lst in /etc/apt/sources.list.d/*llvm*.list; do
  [ -f "$lst" ] || continue
  sudo sed -i -E 's@^(deb .*llvm-toolchain-[a-z]+-[0-9]+ .*)$@# \1@' "$lst"
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
# unversioned symbolizer: resolved by source-built sanitizer binaries (no suffix)
sudo ln -sf "${PREFIX}/bin/llvm-symbolizer"  /usr/bin/llvm-symbolizer
# version-suffixed symbolizer: re-link every suffixed link that existed before the
# purge (apt-built legacy SAN binaries bake /usr/bin/llvm-symbolizer-<major>) at the
# freshly built symbolizer; its protocol is version-compatible across LLVM majors
if [ "${#EXISTING_SUFFIXED_SYMBOLIZERS[@]}" -gt 0 ]; then
  for s in "${EXISTING_SUFFIXED_SYMBOLIZERS[@]}"; do
    sudo ln -sf "${PREFIX}/bin/llvm-symbolizer" "$s"
    log "re-linked ${s} -> ${PREFIX}/bin/llvm-symbolizer"
  done
fi

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
  # Repoint whatever runtime-archive dir the script currently names (any prefix,
  # any clang major) at the freshly built one, keyed on the libclang_rt filename.
  sed -i -E "s#[^ ']*/libclang_rt\.(asan|ubsan_standalone)-x86_64\.a#${NEW_RT_DIR}/libclang_rt.\1-x86_64.a#g" "$p"
  if grep -q "${NEW_RT_DIR}/libclang_rt.asan-x86_64.a" "$p"; then
    log "updated ${f} -> ${NEW_RT_DIR}"
  else
    warn "${f}: sanitizer path not rewritten (libclang_rt path not found?)"
  fi
done

# --- 8. Self-test -----------------------------------------------------------
log "self-test: clang version + LLVMgold.so via bfd ld + sanitizers + symbolizer"
"${PREFIX}/bin/clang" --version | head -1
ct="$(mktemp /tmp/build_clang_test.XXXX.c)"; printf 'int main(){return 0;}\n' > "$ct"
"${PREFIX}/bin/clang" "$ct" -flto -fuse-ld=bfd -o "${ct}.out" \
  || die "self-test: -flto via bfd ld failed (LLVMgold.so problem)"
"${PREFIX}/bin/clang" "$ct" -fsanitize=address,undefined -o "${ct}.san" \
  || die "self-test: asan+ubsan link failed"
rm -f "$ct" "${ct}.out" "${ct}.san"
"$(readlink -f /usr/bin/llvm-symbolizer)" --version >/dev/null \
  || die "self-test: /usr/bin/llvm-symbolizer not working"
if [ "${#EXISTING_SUFFIXED_SYMBOLIZERS[@]}" -gt 0 ]; then
  for s in "${EXISTING_SUFFIXED_SYMBOLIZERS[@]}"; do
    [ -x "$(readlink -f "$s")" ] || die "self-test: ${s} does not resolve to an executable"
  done
fi
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
echo "  symbolizer   : /usr/bin/llvm-symbolizer + ${#EXISTING_SUFFIXED_SYMBOLIZERS[@]} re-linked suffixed link(s) -> ${PREFIX}/bin/llvm-symbolizer"
echo "  san scripts  : ${SAN_SCRIPTS[*]} repointed (backups in /tmp/*.pre_build_clang.bak)"
echo "  free on /    : $(df -BG --output=avail / | tail -1 | tr -d ' ')"
