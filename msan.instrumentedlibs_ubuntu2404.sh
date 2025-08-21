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

# Build directory setup
mkdir build && cd build

# Native/System Core libs: libc.so.6, libm.so.6, libresolv.so.2, libgcc_s.so.1 (GCC's runtime support library): there is no need to instrument these. MSAN is designed to work alongside these libs. They will show as having /lib[64] paths in ldd, not $MSAN_LIBDIR.

#System Libraries: no action needed; no need to build instrumented versions of libc.so.6, libm.so.6, libresolv.so.2 (all part of glibc), nor libgcc_s.so.1 (GCC's runtime support library). The Clang sanitizer runtime is designed to work alongside the system's native libc and libgcc. The fact that these are pointing to system directories in ldd output is correct and expected.

# C++ runtime libs (libc++, libc++abi, libunwind)
sudo apt-get update
sudo apt-get install -y git cmake ninja-build build-essential python3 zlib1g-dev
sudo apt purge clang* libclang* libllvm* llvm-17* llvm-spirv* lld* libc++*
dpkg --list | grep -iE 'clang|llvm'  # Should be empty
sudo apt autopurge  # /sbin/ldconfig.real: /lib/x86_64-linux-gnu/libreadline.so.5 is not a symbolic link error is normal (was placed here manually)
sudo apt install clang llvm-18 llvm-18-linker-tools llvm-18-runtime llvm-18-tools llvm-18-dev libstdc++-14-dev llvm-dev lld-18
export CC=/usr/bin/clang
export CXX=/usr/bin/clang++
export LD=/usr/bin/ld.lld-18
git clone --depth 1 https://github.com/llvm/llvm-project.git
cd llvm-project
cat > "./msan_build.cmake" <<EOF
set(CMAKE_C_COMPILER "$CC" CACHE STRING "")
set(CMAKE_CXX_COMPILER "$CXX" CACHE STRING "")
set(LLVM_USE_LINKER "$LD" CACHE STRING "")
set(LLVM_BUILD_RUNTIMES ON CACHE BOOL "")
set(LLVM_RUNTIME_CMAKE_ARGS "-DLLVM_USE_SANITIZER=MemoryWithOrigins;-DLLVM_INCLUDE_TESTS=OFF;-DLIBCXX_INCLUDE_TESTS=OFF" CACHE STRING "")
EOF
cmake -S llvm -B build -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="${PWD}/msan_build.cmake" \
  -DLLVM_ENABLE_PROJECTS='clang;lld' \
  -DLLVM_ENABLE_RUNTIMES='compiler-rt;libcxx;libcxxabi;libunwind' \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DLLVM_PARALLEL_{COMPILE,LINK,TABLEGEN}_JOBS="$[ $(nproc) * 8 ]" \
  -DLLVM_INCLUDE_DOCS=OFF \
  -DLLVM_ENABLE_SPHINX=OFF
sudo ninja -C build install  # Will build+install into /usr/local (DCMAKE_INSTALL_PREFIX, also the default)
mkdir "$MSAN_LIBDIR/include"
cp -aL /usr/local/lib/x86_64-unknown-linux-gnu/* "$MSAN_LIBDIR/"  # libs
cp -aL /usr/local/include/* "$MSAN_LIBDIR/include"  # includes

# Change now to newly build Clang/LLVM 22
export CC=/usr/local/bin/clang
export CXX=/usr/local/bin/clang++
export LD=/usr/local/bin/ld.lld
export MSAN_LIBDIR=/MSAN_libs  # Do not change this path without changing the two build_mdpsms_dbg/opt_san.sh scripts also
# Find the Clang resource directory which contains the MSAN runtime library
CLANG_RESOURCE_DIR=$(clang -print-resource-dir)
CLANG_RUNTIME_LIB_DIR="${CLANG_RESOURCE_DIR}/lib/linux"
# TODO: consider adding -fsanitize-memory-track-origins=2 to CFLAGS (and LDFLAGS?) - also update build scripts to match the same
export CFLAGS="-fPIC -fno-omit-frame-pointer -O2 -g -fsanitize=memory"
export CXXFLAGS="-fPIC -fno-omit-frame-pointer -O2 -g -fsanitize=memory"
export LDFLAGS="-fsanitize=memory -L$MSAN_LIBDIR -Wl,-rpath=$MSAN_LIBDIR"

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
