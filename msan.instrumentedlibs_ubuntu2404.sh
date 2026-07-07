#!/bin/bash
# Script to generate MSAN instrumented libraries from sources
# To see if a lib is MSAN instrumented use readelf, nm, or strings <somelib> | grep -i msan

# Modified for Ubuntu 24.04 LTS by Roel based, with thanks, on the original by Daniel at;
# https://raw.githubusercontent.com/MariaDB/buildbot/refs/heads/main/ci_build_images/msan.instrumentedlibs.sh
# Which in turn is based on the invaluable build-msanX.sh scripts in https://jira.mariadb.org/browse/MDEV-20377 by Marko

# The general principle here is:
# 0. for all runtime dependencies of MariaDB
# 1. take the debian source file (for consistent library ABI compatibility)
# 2. install the build dependencies of that source library
# 3. Use the CFLAGS/CXXFLAGS/LDFLAGS from the environment to perform the msan instrumentation
# 4. roughly follow what's in the debian/rules, but minimize to just produce the shared library
# 5. move the build library to $MSAN_LIBDIR

set -o errexit
set -o nounset
set -o pipefail
set -o posix

# Some things depend on OS version. Expose these env variable for ease of determination
. /etc/os-release
if [ "$(grep -o 'DISTRIB_RELEASE=.*' /etc/lsb-release | grep -o '24.04')" != "24.04" ]; then
  echo "Assert: this script was made for Ubuntu 24.04 only"
  exit 1
fi

# Clang version used for all MSAN instrumentation. IMPORTANT: clang-21 MSAN flags InnoDB startup code and the
# server cannot even bootstrap (https://jira.mariadb.org/browse/MDEV-38419, stalled). Use clang-20 until resolved.
# Keep this in sync with CLANG_VERSION in build_mdpsms_dbg_msan.sh and build_mdpsms_opt_msan.sh
CLANG_VERSION="${CLANG_VERSION:-20}"

export MSAN_LIBDIR=/MSAN_libs  # Do not change this path without changing the two build_mdpsms_dbg/opt_san.sh scripts also
if [ -d "${MSAN_LIBDIR}" ]; then
  echo "The directory ${MSAN_LIBDIR} already exists, please remove it, or rename it (to .OLD for example)"
  exit 1
fi

# Directory setup
sudo mkdir -p "${MSAN_LIBDIR}/build" "${MSAN_LIBDIR}/include"
sudo chown -R $(whoami):$(whoami) "${MSAN_LIBDIR}"
cd "${MSAN_LIBDIR}/build"

# Add sources if needed
if ! grep -q "^Types: deb-src$" /etc/apt/sources.list.d/ubuntu.sources; then
  sudo bash -c 'echo -e "\nTypes: deb-src\nURIs: http://archive.ubuntu.com/ubuntu/\nSuites: noble noble-updates noble-backports noble-security\nComponents: main restricted universe multiverse\nEnabled: yes\nSigned-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg" >> /etc/apt/sources.list.d/ubuntu.sources'
  sudo apt-get update  # Required for the apt-get source/build-dep calls below to see the just-added deb-src entries
fi
# Tools needed by the library builds below (idempotent; build-essential/git/cmake/ninja are also covered by SKIP_CLEANUP=0)
sudo apt-get install -y git cmake ninja-build build-essential python3 zlib1g-dev equivs quilt

SKIP_CLEANUP=1
if [ "${SKIP_CLEANUP}" -ne 1 ]; then
  # Remove Clang/LLVM 17/18 if present, and default packages, install required packages
  sudo apt purge -y clang*17* clang*18* libclang*17* libclang*18* libllvm-*17* libllvm-*18* llvm-17* llvm-18* llvm-spirv* lld*17* lld*18* libc++*17* libc++*18* clang llvm llvm-dev llvm-runtime
  sudo apt-get update
  sudo apt-get install -y git cmake ninja-build build-essential python3 zlib1g-dev equivs quilt
  #dpkg --list | grep -iE 'clang|llvm'  # Should be empty
  sudo apt -y autopurge  # /sbin/ldconfig.real: /lib/x86_64-linux-gnu/libreadline.so.5 is not a symbolic link error is normal (was placed here manually)
fi

# Clang/LLVM install. Auto-detected: only installs if clang-${CLANG_VERSION} + lld + libc++ dev are not already
# present, so this script is self-sufficient on a fresh Ubuntu 24.04 box yet a no-op on an already-set-up one.
# Force a (re)install by exporting SKIP_CLANG_INSTALL=0 ; force skip with SKIP_CLANG_INSTALL=1
if [ -z "${SKIP_CLANG_INSTALL:-}" ]; then
  if [ -x "/usr/bin/clang-${CLANG_VERSION}" ] && [ -x "/usr/bin/clang++-${CLANG_VERSION}" ] \
     && [ -x "/usr/bin/ld.lld-${CLANG_VERSION}" ] && dpkg -s "libc++-${CLANG_VERSION}-dev" >/dev/null 2>&1; then
    SKIP_CLANG_INSTALL=1
    echo "clang-${CLANG_VERSION} toolchain already present; skipping install."
  else
    SKIP_CLANG_INSTALL=0
  fi
fi
if [ "${SKIP_CLANG_INSTALL}" -ne 1 ]; then
  # apt.llvm.org ships versioned libc++-N-dev that all depend on the UNVERSIONED libc++1/libc++abi1; a leftover
  # apt.llvm.org repo for a DIFFERENT llvm version makes apt try to co-install two versions of those and fail with
  # "held broken packages". Remove any apt.llvm.org repo line that is not for our CLANG_VERSION before installing,
  # including an UNVERSIONED llvm-toolchain-<suite> line (no -N suffix) which tracks the latest llvm and pulls a
  # newer libc++1/libc++abi1 than our CLANG_VERSION -dev packages depend on.
  for f in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    [ -r "$f" ] || continue
    if grep -q "apt.llvm.org" "$f" && grep -qvE "llvm-toolchain-[a-z]+-${CLANG_VERSION}([^0-9]|\$)" <(grep "apt.llvm.org" "$f"); then
      sudo sed -i "/apt.llvm.org.*llvm-toolchain/{/llvm-toolchain-[a-z]*-${CLANG_VERSION}\([^0-9]\|\$\)/!d}" "$f"
    fi
  done
  wget https://apt.llvm.org/llvm.sh
  chmod +x llvm.sh
  sed -i 's|libunwind-$LLVM_VERSION-dev"|libunwind-$LLVM_VERSION-dev python3-lldb-$LLVM_VERSION"|' llvm.sh
  sudo ./llvm.sh ${CLANG_VERSION} all
  rm llvm.sh
  # llvm.sh installs clang/lld but not always the libc++ runtime+dev we link against; ensure they are present
  sudo apt-get install -y libc++-${CLANG_VERSION}-dev libc++abi-${CLANG_VERSION}-dev libclang-rt-${CLANG_VERSION}-dev
  # IMPORTANT: do NOT repoint the unversioned /usr/bin/{clang,clang++,ld.lld,ld} system symlinks. The MSAN scripts
  # all call fully-versioned binaries (clang-${CLANG_VERSION}, ld.lld-${CLANG_VERSION}), so these are not needed, and
  # clobbering them - especially /usr/bin/ld (the global default linker) - would silently change the compiler/linker
  # for everything else on the machine (e.g. a clang-18 pquery build). Only create them if they are MISSING entirely.
  [ -e /usr/bin/clang ]   || sudo ln -s /usr/bin/clang-${CLANG_VERSION}   /usr/bin/clang
  [ -e /usr/bin/clang++ ] || sudo ln -s /usr/bin/clang++-${CLANG_VERSION} /usr/bin/clang++
  sudo ldconfig
  # To remove, use:
  # sudo rm -f /usr/bin/clang /usr/bin/clang++ /usr/bin/lld
  # apt purge -y clang-${CLANG_VERSION} lldb-${CLANG_VERSION} lld-${CLANG_VERSION} 'clang*-${CLANG_VERSION}' 'llvm-${CLANG_VERSION}*' 'libc++*-${CLANG_VERSION}*' 'libclang*-${CLANG_VERSION}*' 'libunwind-${CLANG_VERSION}*' 'libllvm${CLANG_VERSION}*' 'libpolly-${CLANG_VERSION}*'
fi

SKIP_CMAKE_UPGRADE=1
if [ "${SKIP_CMAKE_UPGRADE}" -ne 1 ]; then
  # Upgrade cmake to at least 3.29 (currently 4.1.0 is used) to enable custom ld path support, using the official kitware.com linked from cmake.org
  sudo apt purge -y cmake
  sudo apt install ca-certificates gpg wget
  test -f /usr/share/doc/kitware-archive-keyring/copyright || \
    wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null \
    | gpg --dearmor | sudo tee /usr/share/keyrings/kitware-archive-keyring.gpg >/dev/null
  echo 'deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ noble main' \
    | sudo tee /etc/apt/sources.list.d/kitware.list >/dev/null
  sudo apt update
  sudo apt autopurge -y
  sudo apt install -y kitware-archive-keyring
  sudo apt update
  sudo apt install -y cmake
fi

# Now point to the just-installed Clang/LLVM
export MSAN_LIBDIR=/MSAN_libs   # handy for copy/paste
export CC=/usr/bin/clang-${CLANG_VERSION}
export CXX=/usr/bin/clang++-${CLANG_VERSION}
export LD=/usr/bin/ld.lld-${CLANG_VERSION}
# TODO: consider adding -fsanitize-memory-track-origins=2 to CFLAGS (and LDFLAGS?) - also update build scripts to match the same
# Note that -fsanitize=memory is required for the compiler *and* the linker
# -fuse-ld=lld is included here as the CMAKE_LINKER_TYPE/CMAKE_*_USING_LINKER_* options below require cmake >= 3.29 (silently ignored on older cmake)
export LDFLAGS="-fuse-ld=lld -fsanitize=memory -L$MSAN_LIBDIR -Wl,-rpath=$MSAN_LIBDIR"
unset CFLAGS CXXFLAGS
#  -DCMAKE_C_FLAGS="${CFLAGS}" \
#  -DCMAKE_CXX_FLAGS="${CXXFLAGS}" \

# Native/System Core libs: libc.so.6, libm.so.6, libresolv.so.2, libgcc_s.so.1 (GCC's runtime support library): there is no need to instrument these. MSAN is designed to work alongside these libs. They will point to system directories in ldd output.

# C++ runtime libs (libc++, libc++abi, libunwind)
# Pin to the release branch matching the installed clang: building llvm main with an older
# clang host risks compile failures and produces a libc++ that mismatches the clang libc++ headers
git clone --depth 1 --branch release/${CLANG_VERSION}.x https://github.com/llvm/llvm-project.git
# libunwind's findUnwindSections probes glibc via dlsym("_dl_find_object"); glibc's _dlerror_run
# calls free(), which at shutdown (no MsanThread) re-enters MSAN's free interceptor -> forced slow
# unwind -> back into this probe -> infinite recursion -> bogus SIGSEGV. Force the dl_iterate_phdr
# path instead (no dlsym, no free). Same throwaway-clone patch pattern as the libaio/gmp/xml2 seds.
AS=llvm-project/libunwind/src/AddressSpace.hpp
if ! grep -q 'defined(DLFO_STRUCT_HAS_EH_DBASE)' "${AS}"; then
  echo "Assert: DLFO_STRUCT_HAS_EH_DBASE gate not found in ${AS} (libunwind layout changed for clang-${CLANG_VERSION}?). Terminating."
  exit 1
fi
sed -i '/defined(DLFO_STRUCT_HAS_EH_DBASE)/s/^#if .*/#if 0/' "${AS}"
cd llvm-project/runtimes

# Note: libunwind must be in LLVM_ENABLE_RUNTIMES (libcxxabi's LIBCXXABI_USE_LLVM_UNWINDER=ON requires it),
# but the instrumented libunwind.so produced here is REPLACED by an uninstrumented one below. An instrumented
# libunwind reports a false positive on the asm-written unw_context_t (getReg in UnwindCursor.hpp) the moment
# the MSAN runtime (or mariadbd's fatal signal handler) tries to unwind the stack to print a report, which
# recurses (warning -> unwind -> warning -> ...) until the stack overflows: every report becomes a bare SIGSEGV.
# -S: Source dir
cmake . -B build -G Ninja \
  -DLLVM_ENABLE_RUNTIMES='compiler-rt;libcxx;libcxxabi;libunwind' \
  -DCMAKE_C_COMPILER="${CC}" \
  -DCMAKE_CXX_COMPILER="${CXX}" \
  -DCMAKE_LINKER_TYPE=LLD \
  -DCMAKE_C_USING_LINKER_LLD="${LD}" \
  -DCMAKE_C_USING_LINKER_MODE=TOOL \
  -DCMAKE_CXX_USING_LINKER_LLD="${LD}" \
  -DCMAKE_CXX_USING_LINKER_MODE=TOOL \
  -DCMAKE_{EXE,SHARED,MODULE}_LINKER_FLAGS="${LDFLAGS}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_USE_SANITIZER="MemoryWithOrigins" \
  -DLLVM_PARALLEL_{COMPILE,LINK,TABLEGEN}_JOBS="$[ $(nproc) * 8 ]" \
  -DLLVM_INCLUDE_TESTS=OFF \
  -DLIBCXX_INCLUDE_TESTS=OFF \
  -DLLVM_INCLUDE_DOCS=OFF \
  -DLLVM_ENABLE_SPHINX=OFF
ninja -C build
cp -aL build/lib/* "$MSAN_LIBDIR/"  # libs
cp -aL build/include/* "$MSAN_LIBDIR/include"  # includes

# libunwind: build UNINSTRUMENTED (see note above) but with frame pointers and debug info.
# This intentionally OVERWRITES the instrumented libunwind.so* copied from the build above.
cmake . -B build-unwind -G Ninja \
  -DLLVM_ENABLE_RUNTIMES='libunwind' \
  -DCMAKE_C_COMPILER="${CC}" \
  -DCMAKE_CXX_COMPILER="${CXX}" \
  -DCMAKE_C_FLAGS='-fno-omit-frame-pointer -g' \
  -DCMAKE_CXX_FLAGS='-fno-omit-frame-pointer -g' \
  -DCMAKE_{EXE,SHARED,MODULE}_LINKER_FLAGS='-fuse-ld=lld' \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_INCLUDE_TESTS=OFF \
  -DLLVM_INCLUDE_DOCS=OFF
ninja -C build-unwind
cp -aL build-unwind/lib/libunwind.so* "$MSAN_LIBDIR/"
cd "$MSAN_LIBDIR/build"
rm -Rf llvm-project

# Set {C,CXX,LD}FLAGS for all subsequent lib builds. Note that ldd will be found via the LD= export set earlier
# -Wno-error=... demotes clang-20's default-error diagnostics (C23 strictness + OpenSSL-3 deprecations) back to
# warnings so legacy third-party C (cyrus-sasl2, openldap, rtmpdump, curl, ...) still compiles.
export CFLAGS="-fsanitize=memory -fno-omit-frame-pointer -fPIC -O2 -g -Wno-error=incompatible-function-pointer-types -Wno-error=deprecated-declarations -Wno-error=implicit-function-declaration -Wno-error=int-conversion -Wno-error=implicit-int"
export CXXFLAGS="$CFLAGS"
# -Wl,--undefined-version: lld (unlike bfd) errors when a version script assigns a symbol the objects do not
# define (e.g. keyutils' version.lds lists optional keyctl_* symbols). This flag restores bfd's lenient behaviour.
export LDFLAGS="-fuse-ld=lld -fsanitize=memory -L$MSAN_LIBDIR -Wl,-rpath=$MSAN_LIBDIR -Wl,--undefined-version"

# ncurses libtinfo.so - used by the mariadb client
sudo apt-get build-dep -y ncurses
apt-get source ncurses
cd ncurses-*/
#./configure --prefix=/usr --with-shared --without-normal --without-debug --enable-widec --enable-pc-files --with-pkg-config-libdir=/usr/lib/pkgconfig --enable-symlinks --with
#./configure --with-shared --without-normal --without-debug --enable-widec --enable-pc-files --enable-symlinks --with-termlib=tinfo --with-versioned-syms
./configure --with-shared --without-normal --without-debug --enable-widec --enable-pc-files --enable-symlinks --with-termlib=tinfo
make -j "$(nproc)" sources libs
cp -aL lib/lib*so* "$MSAN_LIBDIR/"
cp -aL include/* "$MSAN_LIBDIR/include"
cd "$MSAN_LIBDIR"
ln -sf libtinfo.so.6 libtinfo.so
cd -
cd ..
rm -rf -- ncurses-*

# libedit - used by the mariadb client | TODO: this newer version gives more 'version not found' issues on libedit use; use temporary workaround ftm (export MYSQL_HISTFILE=/dev/null) TODO: remove the same from mariadb-qa/startup.sh when fixed
# Check https://thrysoee.dk/editline/ for the latest version
# LIBEDIT_VERSION="20250104-3.1" # This versiom contains a fix for the MemorySanitizer: use-of-uninitialized-value in mariadbd's main(), caused by libedit before version 3.1-20240517-1. Note that this issue was in the mariadb CLI history (a simple SELECT 1 in the client would trigger it). If an older MSAN instrumented libedit is present,  export MYSQL_HISTFILE=/dev/null  can workaround the issue also
#wget "https://thrysoee.dk/editline/libedit-${LIBEDIT_VERSION}.tar.gz"
#tar -xzf "libedit-${LIBEDIT_VERSION}.tar.gz"
#cd "libedit-${LIBEDIT_VERSION}"
# Configure libedit with MSAN and point it to the libtinfo.so to avoid "/MSAN_libs/libtinfo.so.6: no version information available (required by /MSAN_libs/libedit.so.2)" like errors
#./configure --prefix="$NC_BUILD_DIR/libedit-install" CFLAGS="$MSAN_CFLAGS" CXXFLAGS="$MSAN_CXXFLAGS" LDFLAGS="$MSAN_LDFLAGS -L$MSAN_LIBDIR/lib" CPPFLAGS="-I$MSAN_LIBDIR/include"
#make -j"$(nproc)"
#cp -aL src/.libs/libedit.so* "$MSAN_LIBDIR"
#cd..
#rm -rf -- libedit-*

# libedit - used by the mariadb client
sudo apt-get build-dep -y libedit-dev
apt-get source libedit
cd libedit-*/
#quilt push -a || true  # Apply all official Debian/Ubuntu patches to the source code
./configure
# Configure libedit with MSAN and point it to the libtinfo.so to avoid "/MSAN_libs/libtinfo.so.6: no version information available (required by /MSAN_libs/libedit.so.2)" like errors  TODO: use ncurses full lib
#./configure --prefix="$NC_BUILD_DIR/libedit-install" CFLAGS="$MSAN_CFLAGS" CXXFLAGS="$MSAN_CXXFLAGS" LDFLAGS="$MSAN_LDFLAGS -L$MSAN_LIBDIR//lib" CPPFLAGS="-I$MSAN_LIBDIR/include"
make -j "$(nproc)"
cp -aL src/.libs/libedit.so* "$MSAN_LIBDIR"
cd ..
rm -rf -- libedit-*

# libaio
sudo apt-get build-dep -y libaio
apt-get source libaio
cd libaio-*/
sed -i '/io_getevents_time64/d; /io_pgetevents_time64/d' src/libaio.map  # Enabling the Y2038 compliance (to handle 64-bit time correctly) to avoid missing symbols 'io_getevents_time64' and 'io_pgetevents_time64' errors
make -j "$(nproc)"
cp -aL src/libaio.so* "$MSAN_LIBDIR"
cd ..
rm -rf -- libaio-*

# libcrypt (from libxcrypt source)
sudo apt-get build-dep -y libxcrypt
apt-get source libxcrypt
cd libxcrypt-*/
./autogen.sh
./configure --enable-shared
# Remove the -Wl,-z,defs flag from the generated Makefile as this conflicts with the MSAN linking model for shared libs
sed -i 's/-Wl,-z,defs//g' Makefile
make -j "$(nproc)"
cp -aL .libs/libcrypt.so* "$MSAN_LIBDIR/"
cd ..
rm -rf -- libxcrypt-*

# liburing  # This fails for the moment with:
#==858431==WARNING: MemorySanitizer: use-of-uninitialized-value
#    #0 0x5555585c0abd in io_uring_cqe_get_data(io_uring_cqe const*) /usr/include/liburing.h:229:35
#    #1 0x5555585c0abd in (anonymous namespace)::aio_uring::thread_routine((anonymous namespace)::aio_uring*) /test/11.8_dbg_san/tpool/aio_liburing.cc:166:46
#    #3 0x5555585c19ff in void std::__1::__thread_execute[abi:ne180100]<std::__1::unique_ptr<std::__1::__thread_struct, std::__1::default_delete<std::__1::__thread_struct>>, void (*)((anonymous namespace)::aio_uring*), (anonymous namespace)::aio_uring*, 2ul>(std::__1::tuple<std::__1::unique_ptr<std::__1::__thread_struct, std::__1::default_delete<std::__1::__thread_struct>>, void (*)((anonymous namespace)::aio_uring*), (anonymous namespace)::aio_uring*>&, std::__1::__tuple_indices<2ul>) /usr/lib/llvm-18/bin/../include/c++/v1/__thread/thread.h:193:3
#    #4 0x5555585c19ff in void* std::__1::__thread_proxy[abi:ne180100]<std::__1::tuple<std::__1::unique_ptr<std::__1::__thread_struct, std::__1::default_delete<std::__1::__thread_struct>>, void (*)((anonymous namespace)::aio_uring*), (anonymous namespace)::aio_uring*>>(void*) /usr/lib/llvm-18/bin/../include/c++/v1/__thread/thread.h:202:3
#    #5 0x7fffe689ca93 in start_thread nptl/pthread_create.c:447:8
#    #6 0x7fffe6929c3b in clone3 misc/../sysdeps/unix/sysv/linux/x86_64/clone3.S:78
#  Uninitialized value was created by an allocation of 'cqe' in the stack frame
#    #0 0x5555585c0569 in (anonymous namespace)::aio_uring::thread_routine((anonymous namespace)::aio_uring*) /test/11.8_dbg_san/tpool/aio_liburing.cc:155:7
#SUMMARY: MemorySanitizer: use-of-uninitialized-value /usr/include/liburing.h:229:35 in io_uring_cqe_get_data(io_uring_cqe const*)
# So used -DCMAKE_DISABLE_FIND_PACKAGE_URING=1 for the moment
#sudo apt-get build-dep -y liburing
#apt-get source liburing
#cd liburing-*/
#./configure
## The liburing Makefile uses its own LINK_FLAGS variable and ignores LDFLAGS
## Directly replace the line in src/Makefile to add the sanitizer flags
#sed -i "s/LINK_FLAGS=-Wl,-z,defs/LINK_FLAGS=-fsanitize=memory/" src/Makefile
## The version script references a symbol which is not being compiled, remove it from the map file
#sed -i '/io_uring_prep_sock_cmd/d' src/liburing-ffi.map
## Now build with the patched Makefiles.
#make -j "$(nproc)"
#cp -aL src/liburing.so* "$MSAN_LIBDIR/"
#cd ..
#rm -rf -- liburing-*

# gnutls used by libmariadb
sudo apt-get build-dep -y gnutls28
apt-get source gnutls28
cd gnutls28-*/
aclocal
automake --add-missing
./configure \
 --with-included-libtasn1 \
 --with-included-unistring \
 --without-p11-kit \
 --disable-hardware-acceleration \
 --disable-guile
make -j "$(nproc)"
cp -aL lib/.libs/libgnutls.so* "$MSAN_LIBDIR"
cd ..
rm -rf -- gnutls28-*

# From: https://jira.mariadb.org/browse/MDEV-20377?focusedCommentId=290259&page=com.atlassian.jira.plugin.system.issuetabpanels:comment-tabpanel#comment-290259
# In the current Debian Sid, apt source libnettle8 would fetch Nettle 3.9, while libnettle8t64 includes Nettle 3.10, which the libgnutls would be built against.
# Note: If Valgrind is installed, the configure script for Nettle 3.10 build may hit Valgrind bug 492255 (hang when trying to execute valgrind on an empty MemorySanitizer compiled program). You can send SIGKILL to the memcheck (or similar) process to work around that, or you can uninstall Valgrind before executing the build script.

# An uninstrumented nettle produces a fault like:
# #0  0x00007ffff7769c02 in ?? () from /lib/x86_64-linux-gnu/libnettle.so.8
# #1  0x00007ffff7769e0b in nettle_sha512_digest () from /lib/x86_64-linux-gnu/libnettle.so.8
# #2  0x00007ffff7e48e8a in wrap_nettle_hash_output (src_ctx=0xbcf74c967d490141, digest=0x713000000008, digestsize=140737488331568) at mac.c:843
# #3  0x00007ffff765ffbf in ma_hash (algorithm=6, buffer=0x701000000110 "foo", buffer_length=3, digest=0x7fffffffa2f0 "\367\366\363\367\377\177") at /home/marko/11.2/libmariadb/include/ma_crypt.h:151
sudo apt-get build-dep -y nettle
apt-get source nettle
cd nettle-*/
# native assembly isn't understood by the msan instrumentation when it performs initialization of memory resulting in the above trace.
./configure  --disable-assembler
make -j "$(nproc)"
cp -aL .lib/lib*.so* "$MSAN_LIBDIR"
cd ..
rm -rf -- nettle-*

# LIBIDN2 - GNUTLS and openssl use this library so it needs to be instrumented too
#
sudo apt-get build-dep -y libidn2
apt-get source libidn2
cd libidn2-*/
./configure --enable-valgrind-tests=no
make -j "$(nproc)"
cp -aL lib/.libs/libidn2.so* "$MSAN_LIBDIR"
cd ..
rm -rf -- libidn2-*

# GMP - the maths library for gnutls
sudo apt-get build-dep -y gmp
apt-get source gmp
cd gmp-*/
# There where dependency problems with documentation, and we don't need the documentation so its removed.
sed -e '/^.*"doc\/Makefile".*/d;s/doc\/Makefile //;' -i configure
sed -e 's/^\(SUBDIRS = .*\) doc$/\1/;' -i Makefile.in
./configure --disable-assembly
make -j "$(nproc)"
cp -aL .libs/libgmp.so* "$MSAN_LIBDIR"
cd ..
rm -rf -- gmp-*

# XML2 - MariaDB connect engine and Columnstore(?) uses this
sudo apt-get build-dep -y libxml2
apt-get source libxml2
cd libxml2-*/
aclocal
automake --add-missing
sed -i -e /docbDefaultSAXHandlerInit/d -e /initdocbDefaultSAXHandler/d -e /docbDefaultSAXHandler/d -e /xmlSAX2InitDocbDefaultSAXHandler/d -e /docbCreateFileParserCtxt/d -e /docbCreatePushParserCtxt/d -e /docbEncodeEntities/d -e /docbFreeParserCtxt/d -e /docbParseChunk/d -e /docbParseDoc/d -e /docbParseDocument/d -e /docbParseFile/d -e /docbSAXParseDoc/d -e /docbSAXParseFile/d -e /xmlDllMain/d libxml2.syms  # Remove failing symbols
./configure  --without-python --without-docbook --with-icu
make -j "$(nproc)"
cp -aL .libs/libxml2.so* "$MSAN_LIBDIR"
cd ..
rm -rf -- libxml2-*

# Unixodbc used by MariaDB Connect engine.
sudo apt-get build-dep -y unixodbc-dev
apt-get source unixodbc-dev
cd unixodbc-*/
autoreconf -fi
./configure --enable-gui=no --enable-drivermanager --enable-fastvalidate --with-pth=no --with-included-ltdl=no
make -j "$(nproc)"
mv ./DriverManager/.libs/libodbc.so* "$MSAN_LIBDIR"
cd ..
rm -rf -- unixodbc-*
# libfmt -  used by server for SFORMAT function will be hit by mtr test main.func_sformat
sudo apt-get build-dep -y libfmt-dev
apt-get source libfmt-dev
cd fmtlib-*/
mkdir build
cmake -DFMT_DOC=OFF -DFMT_TEST=OFF  -DBUILD_SHARED_LIBS=on  -DFMT_PEDANTIC=on -S . -B build
cmake --build build
mv build/libfmt.so* "$MSAN_LIBDIR"
cd ..
rm -rf -- fmtlib-*

# openssl - used by tls connections and parsec authentication in the server
sudo apt-get build-dep -y libssl-dev
apt-get source libssl-dev
cd openssl-*/
# note no-asm and enable-msan were't option for less than clang-19, something about libxcrypt instrumentation for libcrypt intentional word splitting of CFLAGS
# shellcheck disable=SC2086
./Configure  shared no-idea no-mdc2 no-rc5 no-zlib no-ssl3 enable-unit-test no-ssl3-method enable-rfc3779 enable-cms no-capieng no-rdrand no-asm enable-msan $CFLAGS
make -j "$(nproc)" build_libs
mv ./*.so* "$MSAN_LIBDIR"
cd ..
rm -rf -- openssl-*

# >>> MSAN_ADDLIBS_BEGIN
# System libraries pulled in transitively by mariadbd and its loaded plugins (auth_gssapi, auth_pam, ha_connect,
# ha_s3, ha_videx, hashicorp_key_management, provider_*). Built AFTER the base libs above so each links the
# instrumented deps already in $MSAN_LIBDIR. Hand-written assembly / CPU-SIMD is disabled per lib (MSAN cannot
# instrument it and would report false use-of-uninitialized-value). Leaf libs first; curl near the end (links most).

# zlib - compression; linked by mariadbd and many plugins. No asm. Its configure shared-probe rejects the MSAN
# flags (disables shared), its `make shared` also links test programs that fail, and the .dfsg source drops win32/
# (breaks CMake). So run configure only to generate a correct zconf.h (Z_HAVE_UNISTD_H), then compile the library
# sources and link the shared object directly. SONAME libz.so.1 is the zlib 1.x ABI name that mariadbd links.
sudo apt-get build-dep -y zlib
apt-get source zlib
cd zlib-*/
CFLAGS='' LDFLAGS='' ./configure
$CC $CFLAGS -DHAVE_HIDDEN -c adler32.c compress.c crc32.c deflate.c gzclose.c gzlib.c gzread.c gzwrite.c infback.c inffast.c inflate.c inftrees.c trees.c uncompr.c zutil.c
$CC -shared -Wl,-soname,libz.so.1 $LDFLAGS -o libz.so.1 adler32.o compress.o crc32.o deflate.o gzclose.o gzlib.o gzread.o gzwrite.o infback.o inffast.o inflate.o inftrees.o trees.o uncompr.o zutil.o
find . \( -name 'libz.so.*' \) -exec cp -aL {} "$MSAN_LIBDIR/" \;
cd ..
rm -rf -- zlib-*

# libunistring - Unicode strings; pulled by libidn2 and libpsl. Pure C.
sudo apt-get build-dep -y libunistring
apt-get source libunistring
cd libunistring-*/
./configure --disable-static
make -j "$(nproc)"
find . \( -name 'libunistring.so.*' \) -exec cp -aL {} "$MSAN_LIBDIR/" \;
cd ..
rm -rf -- libunistring-*

# libtasn1 - ASN.1 parser; linked by gnutls and p11-kit. Pure C.
sudo apt-get build-dep -y libtasn1-6
apt-get source libtasn1-6
cd libtasn1-6-*/
./configure --disable-static --disable-doc --enable-ld-version-script
make -j "$(nproc)"
find . \( -name 'libtasn1.so.*' \) -exec cp -aL {} "$MSAN_LIBDIR/" \;
cd ..
rm -rf -- libtasn1-6-*

# keyutils - kernel keyring; linked by the krb5 stack. Plain Makefile, pure C; pass CC/CFLAGS on the command line
# to override the Makefile's -Werror append while keeping MSAN flags. NO_ARLIB=1 skips the static lib.
sudo apt-get build-dep -y keyutils
apt-get source keyutils
cd keyutils-*/
make -j "$(nproc)" CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" NO_ARLIB=1
find . \( -name 'libkeyutils.so.*' \) -exec cp -aL {} "$MSAN_LIBDIR/" \;
cd ..
rm -rf -- keyutils-*

# libcap-ng - POSIX capabilities; pulled by libaudit. Ships no ./configure (touch NEWS + autoreconf, per Debian).
sudo apt-get build-dep -y libcap-ng
apt-get source libcap-ng
cd libcap-ng-*/
touch NEWS
autoreconf -fi
./configure --disable-static --without-python3
make -j "$(nproc)"
find . \( -name 'libcap-ng.so.*' \) -exec cp -aL {} "$MSAN_LIBDIR/" \;
cd ..
rm -rf -- libcap-ng-*

# bzip2 - compression; provider_bzip2. Pure C. Makefile-libbz2_so builds the shared lib (soname libbz2.so.1.0).
sudo apt-get build-dep -y bzip2
apt-get source bzip2
cd bzip2-*/
make -f Makefile-libbz2_so CC="$CC" CFLAGS="$CFLAGS -D_FILE_OFFSET_BITS=64"
find . \( -name 'libbz2.so.*' \) -exec cp -aL {} "$MSAN_LIBDIR/" \;
cd ..
rm -rf -- bzip2-*

# lz4 - compression; provider_lz4 and libcurl. Pure C, no SIMD.
sudo apt-get build-dep -y lz4
apt-get source lz4
cd lz4-*/
make -C lib CC="$CC" CFLAGS="$CFLAGS"
find . \( -name 'liblz4.so.*' \) -exec cp -aL {} "$MSAN_LIBDIR/" \;
cd ..
rm -rf -- lz4-*

# xz-utils (liblzma) - compression; provider_lzma. --disable-assembler + --disable-clmul-crc drop the asm/SIMD paths.
sudo apt-get build-dep -y xz-utils
apt-get source xz-utils
cd xz-utils-*/
./configure --disable-static --disable-assembler --disable-clmul-crc --disable-xz --disable-xzdec --disable-lzmadec --disable-lzmainfo --disable-scripts --disable-doc
make -j "$(nproc)"
find . \( -name 'liblzma.so.*' \) -exec cp -aL {} "$MSAN_LIBDIR/" \;
cd ..
rm -rf -- xz-utils-*

# lzo2 - compression; provider_lzo. --disable-asm: amd64 asm is used by default and MSAN cannot instrument it.
sudo apt-get build-dep -y lzo2
apt-get source lzo2
cd lzo2-*/
./configure --disable-static --enable-shared --disable-asm
make -j "$(nproc)"
find . \( -name 'liblzo2.so.*' \) -exec cp -aL {} "$MSAN_LIBDIR/" \;
cd ..
rm -rf -- lzo2-*

# snappy - compression; provider_snappy. Force the SSSE3/BMI2 checks off (MSAN cannot instrument those paths).
# Strip -Werror: clang-20 flags a -Wsign-compare in snappy's own code that its CMakeLists would treat as fatal.
sudo apt-get build-dep -y snappy
apt-get source snappy
cd snappy-*/
sed -i 's/-Werror//g' CMakeLists.txt
cmake -S . -B build -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DBUILD_SHARED_LIBS=ON -DSNAPPY_BUILD_TESTS=OFF -DSNAPPY_BUILD_BENCHMARKS=OFF \
  -DHAVE_SSSE3=0 -DHAVE_SSE41=0 -DHAVE_BMI2=0 \
  -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_C_FLAGS="$CFLAGS" -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
  -DCMAKE_SHARED_LINKER_FLAGS="$LDFLAGS" -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS"
cmake --build build -j "$(nproc)"
find . \( -name 'libsnappy.so.*' \) -exec cp -aL {} "$MSAN_LIBDIR/" \;
cd ..
rm -rf -- snappy-*

# nghttp2 - HTTP/2; linked by libcurl. Pure C; --enable-lib-only builds only libnghttp2.
sudo apt-get build-dep -y nghttp2
apt-get source nghttp2
cd nghttp2-*/
[ -x ./configure ] || autoreconf -fi
./configure --disable-static --enable-lib-only
make -j "$(nproc)"
find . \( -name 'libnghttp2.so.*' \) -exec cp -aL {} "$MSAN_LIBDIR/" \;
cd ..
rm -rf -- nghttp2-*

# brotli - compression; linked by libcurl. NEON path is ARM-only, no x86 SIMD.
sudo apt-get build-dep -y brotli
apt-get source brotli
cd brotli-*/
cmake -S . -B build -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DBUILD_SHARED_LIBS=ON -DBROTLI_DISABLE_TESTS=ON \
  -DCMAKE_C_COMPILER="$CC" -DCMAKE_C_FLAGS="$CFLAGS" \
  -DCMAKE_SHARED_LINKER_FLAGS="$LDFLAGS" -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS"
cmake --build build -j "$(nproc)"
find . \( -name 'libbrotlicommon.so.*' -o -name 'libbrotlidec.so.*' -o -name 'libbrotlienc.so.*' \) -exec cp -aL {} "$MSAN_LIBDIR/" \;
cd ..
rm -rf -- brotli-*

# libzstd - compression; linked by libcurl and mariadbd. ZSTD_NO_ASM=1 sets -DZSTD_DISABLE_ASM (drops BMI2 asm).
sudo apt-get build-dep -y libzstd
apt-get source libzstd
cd libzstd-*/
make -C lib ZSTD_NO_ASM=1 CC="$CC" CFLAGS="$CFLAGS"
find . \( -name 'libzstd.so.*' \) -exec cp -aL {} "$MSAN_LIBDIR/" \;
cd ..
rm -rf -- libzstd-*

# e2fsprogs - libcom_err only; linked by the krb5/gssapi stack.
sudo apt-get build-dep -y e2fsprogs
apt-get source e2fsprogs
cd e2fsprogs-*/
./configure --enable-elf-shlibs
make -j "$(nproc)" -C lib/et
find . \( -name 'libcom_err.so.*' \) -exec cp -aL {} "$MSAN_LIBDIR/" \;
cd ..
rm -rf -- e2fsprogs-*

# p11-kit - PKCS#11 loader; linked by gnutls. --without-libffi avoids the un-instrumentable libffi asm trampolines;
# --with-hash-impl=internal avoids the freebl/NSS dependency. Needs the instrumented libtasn1 (built above).
sudo apt-get build-dep -y p11-kit
apt-get source p11-kit
cd p11-kit-*/
./configure --disable-static --without-libffi --with-hash-impl=internal --without-bash-completion --disable-doc
make -j "$(nproc)"
find . \( -name 'libp11-kit.so.*' \) -exec cp -aL {} "$MSAN_LIBDIR/" \;
cd ..
rm -rf -- p11-kit-*

# audit (libaudit) - linked by auth_pam. Links libcap-ng (built above).
sudo apt-get build-dep -y audit
apt-get source audit
cd audit-*/
[ -x ./configure ] || autoreconf -fi
./configure --disable-static --enable-shared --without-python --without-python3 --disable-zos-remote --without-golang
make -j "$(nproc)"
find . \( -name 'libaudit.so.*' -o -name 'libauparse.so.*' \) -exec cp -aL {} "$MSAN_LIBDIR/" \;
cd ..
rm -rf -- audit-*

# pam (libpam) - linked by auth_pam / auth_pam_v1. Links libaudit (built above).
sudo apt-get build-dep -y pam
apt-get source pam
cd pam-*/
[ -x ./configure ] || autoreconf -fi
./configure --disable-static --disable-doc --disable-nis --disable-selinux
# Build only libpam, overriding BUILD_LDFLAGS/LDFLAGS to drop Debian's -Wl,--no-undefined: the instrumented
# libpam.so legitimately leaves the MSAN interceptors (__msan_memcpy etc.) for mariadbd's runtime to resolve.
make -j "$(nproc)" -C libpam BUILD_LDFLAGS="$LDFLAGS" LDFLAGS="$LDFLAGS"
find . \( -name 'libpam.so.*' \) -exec cp -aL {} "$MSAN_LIBDIR/" \;
cd ..
rm -rf -- pam-*

# libpsl - public suffix list; linked by libcurl. Uses the instrumented libidn2 (present).
sudo apt-get build-dep -y libpsl
apt-get source libpsl
cd libpsl-*/
[ -x ./configure ] || autoreconf -fi
# The suffix-list data lives in a git submodule (list/) absent from the tarball; point PSL_FILE/PSL_DISTFILE at
# the system publicsuffix package instead (the Debian approach) so the dafsa header generates.
./configure --disable-static --enable-runtime=libidn2 --with-psl-file=/usr/share/publicsuffix/public_suffix_list.dat --with-psl-distfile=/usr/share/publicsuffix/public_suffix_list.dafsa
make -j "$(nproc)"
find . \( -name 'libpsl.so.*' \) -exec cp -aL {} "$MSAN_LIBDIR/" \;
cd ..
rm -rf -- libpsl-*

# krb5 - MIT Kerberos (libkrb5, libgssapi_krb5, libk5crypto, libkrb5support); auth_gssapi at plugin init calls
# krb5_init_context_profile() and an uninstrumented libkrb5 gives a false uninit report in profile_make_prf_data.
# --disable-aesni: MSAN cannot instrument the AES-NI asm (C fallback used).
sudo apt-get build-dep -y krb5
apt-get source krb5
cd krb5-*/src
./configure --disable-aesni --enable-shared --disable-static
# krb5's shlib config adds -Wl,--no-undefined, which makes the MSAN TLS globals (__msan_param_tls etc., resolved
# from mariadbd's runtime) fatal at link. Strip it from every file that carries it.
grep -rlZ -- '-Wl,--no-undefined' . 2>/dev/null | xargs -0 -r sed -i 's/-Wl,--no-undefined//g'
make -j "$(nproc)"
find . \( -name 'libkrb5.so.*' -o -name 'libgssapi_krb5.so.*' -o -name 'libk5crypto.so.*' -o -name 'libkrb5support.so.*' \) -exec cp -aL {} "$MSAN_LIBDIR/" \;
cd ../..
rm -rf -- krb5-*

# cyrus-sasl2 (libsasl2) - SASL; linked by libldap and libcurl. Links krb5 (gssapi) and openssl (both present).
sudo apt-get build-dep -y cyrus-sasl2
apt-get source cyrus-sasl2
cd cyrus-sasl2-*/
[ -x ./configure ] || autoreconf -fi
# Debian's override_dh_auto_configure writes these empty stubs; common/Makefile references them unconditionally.
: > common/crypto-compat.c
: > common/crypto-compat.h
./configure --disable-static --enable-shared --with-dblib=none --enable-gssapi
find . -name Makefile -exec sed -i 's/-no-undefined//g; s/-Wl,--no-undefined//g; s/-Wl,-z,defs//g' {} +
make -j "$(nproc)" -C common
make -j "$(nproc)" -C lib
find . \( -name 'libsasl2.so.*' \) -exec cp -aL {} "$MSAN_LIBDIR/" \;
cd ..
rm -rf -- cyrus-sasl2-*

# librtmp (rtmpdump) is intentionally omitted: it does not build against OpenSSL 3 (Debian builds it against GnuTLS,
# which drags in an uninstrumented libgcrypt) and it is only reached by libcurl for rtmp:// URLs, which the MariaDB
# plugins never use. curl below is built --without-librtmp, so librtmp leaves the dependency closure entirely.

# libssh - SSH; linked by libcurl. CMake; OpenSSL backend + zlib (present); GSSAPI via the instrumented krb5.
sudo apt-get build-dep -y libssh
apt-get source libssh
cd libssh-*/
cmake -S . -B build -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DBUILD_SHARED_LIBS=ON -DWITH_EXAMPLES=OFF -DUNIT_TESTING=OFF -DWITH_GSSAPI=ON \
  -DCMAKE_C_COMPILER="$CC" -DCMAKE_C_FLAGS="$CFLAGS" \
  -DCMAKE_SHARED_LINKER_FLAGS="$LDFLAGS" -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS"
cmake --build build -j "$(nproc)"
find . \( -name 'libssh.so.*' \) -exec cp -aL {} "$MSAN_LIBDIR/" \;
cd ..
rm -rf -- libssh-*

# openldap (liblber, libldap) - LDAP client; linked by libcurl. Links cyrus-sasl2 and openssl (present).
sudo apt-get build-dep -y openldap
apt-get source openldap
cd openldap-*/
./configure --disable-static --disable-slapd --with-tls=openssl --with-cyrus-sasl
find . -name Makefile -exec sed -i 's/-no-undefined//g; s/-Wl,--no-undefined//g; s/-Wl,-z,defs//g' {} +
make -j "$(nproc)" depend
make -j "$(nproc)" -C libraries
find . \( -name 'liblber.so.*' -o -name 'libldap.so.*' \) -exec cp -aL {} "$MSAN_LIBDIR/" \;
cd ..
rm -rf -- openldap-*

# curl (libcurl) - HTTP client; linked by ha_s3 / ha_videx / hashicorp_key_management. Links nghttp2, libssh,
# openldap, cyrus-sasl2, libpsl, brotli, zstd, krb5, zlib, idn2, openssl (all built above / present). librtmp omitted.
sudo apt-get build-dep -y curl
apt-get source curl
cd curl-*/
./configure --disable-static --with-openssl --with-nghttp2 --with-libssh --with-zstd --with-brotli --with-libidn2 --enable-ldap --enable-ldaps --without-librtmp --disable-manual --without-libssh2
make -j "$(nproc)"
find . \( -name 'libcurl.so.*' \) -exec cp -aL {} "$MSAN_LIBDIR/" \;
cd ..
rm -rf -- curl-*

# icu (libicudata, libicui18n, libicuuc) - Unicode; linked by ha_connect. Configure lives in source/. No asm.
sudo apt-get build-dep -y icu
apt-get source icu
cd icu-*/source
./configure --disable-static --enable-shared --disable-samples --disable-tests --disable-layoutex
make -j "$(nproc)"
find . \( -name 'libicudata.so.*' -o -name 'libicui18n.so.*' -o -name 'libicuuc.so.*' \) -exec cp -aL {} "$MSAN_LIBDIR/" \;
cd ../..
rm -rf -- icu-*
# <<< MSAN_ADDLIBS_END

# pcre used by server
sudo apt-get build-dep -y libpcre2-dev
apt-get source  libpcre2-dev
cd pcre2-*/
cmake -S . -B build/ -DBUILD_SHARED_LIBS=ON -DBUILD_STATIC_LIBS=OFF -DPCRE2_BUILD_TESTS=OFF -DPCRE2_SUPPORT_JIT=ON  -DCMAKE_C_FLAGS="${CFLAGS} -Dregcomp=PCRE2regcomp -Dregexec=PCRE2regexec -Dregerror=PCRE2regerror -Dregfree=PCRE2regfree"
cmake --build build/
mv ./build/libpcre2*so* "$MSAN_LIBDIR"
cd ..
rm -rf -- pcre2-*

# cppunit used by galera
# intend to reuse this image for galera testing
sudo apt-get build-dep -y cppunit
apt-get source cppunit
cd cppunit-*/
./configure
make -j "$(nproc)"
cp -aL ./src/cppunit/.libs/libcppunit.so* "$MSAN_LIBDIR"
cd ..
rm -rf -- cppunit-*

# subunit
sudo apt-get build-dep -y subunit
apt-get source subunit
cd subunit-*/
autoreconf  -vi
./configure
make libsubunit.la
mv .libs/libsubunit.so* "$MSAN_LIBDIR"
cd ..
rm -rf -- subunit-*

# cracklib used by mariadb-plugin-cracklib-password-check
sudo apt-get build-dep -y cracklib2
apt-get source cracklib2
cd cracklib2-*/
aclocal
libtoolize
automake --add-missing
autoreconf
CFLAGS="$CFLAGS -Wno-error=int-conversion" ./configure --without-python \
 --with-default-dict=/usr/share/dict/cracklib-small
make -j "$(nproc)"
cp -aL lib/.libs/*.so* "$MSAN_LIBDIR"
cd ..
rm -rf -- cracklib2-*
# MTR tests plugins.two_password_validations and plugins.cracklib_password_check
# indirectly via the shared lib attempt to access the packed version of this library

# This isn't overriding the file that its reading.
# shellcheck disable=SC2094
# Requires apt install cracklib-runtime
#/usr/sbin/cracklib-packer /usr/share/dict/cracklib-small < /usr/share/dict/cracklib-small
