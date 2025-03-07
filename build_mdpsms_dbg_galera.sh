#!/bin/bash
# Created by Roel Van de Paar, Percona LLC
# Modified by Ramesh Sivaraman, MariaDB

MAKE_THREADS=25         # Number of build threads
WITH_EMBEDDED_SERVER=0  # 0 or 1 # Include the embedder server (removed in 8.0)
WITH_LOCAL_INFILE=1     # 0 or 1 # Include the possibility to use LOAD DATA LOCAL INFILE (LOCAL option was removed in 8.0?)
USE_BOOST_LOCATION=0    # 0 or 1 # Use a custom boost location to avoid boost re-download
BOOST_LOCATION=/tmp/boost_465114
USE_CUSTOM_COMPILER=0   # 0 or 1 # Use a customer compiler
CUSTOM_COMPILER_LOCATION="${HOME}/GCC-5.5.0/bin"
USE_CLANG=0             # 0 or 1 # Use the clang compiler instead of gcc
USE_SAN=0               # 0 or 1 # Use ASAN, MSAN, UBSAN
PERFSCHEMA='NO'         # 'NO', 'YES', 'STATIC' or 'DYNAMIC' # Option value is directly passed to -DPLUGIN_PERFSCHEMA=x (i.e. it should always be set to 0 or 1 here). Default is 'NO' to speed up rr.
DISABLE_DBUG_TRACE=1    # 0 or 1 # If 1, then -DWITH_DBUG_TRACE=OFF is used. Default is 'OFF' to speed up rr.
#CLANG_LOCATION="${HOME}/third_party/llvm-build/Release+Asserts/bin/clang"  # Should end in /clang (and assumes presence of /clang++)
CLANG_LOCATION="/usr/bin/clang"  # Should end in /clang (and assumes presence of /clang++)
USE_AFL=0               # 0 or 1 # Use the American Fuzzy Lop gcc/g++ wrapper instead of gcc/g++
AFL_LOCATION="$(cd `dirname $0` && pwd)/fuzzer/afl-2.52b"
IGNORE_WARNINGS=1       # 0 or 1 # Ignore warnings by using -DMYSQL_MAINTAINER_MODE=OFF. When ignoring warnings, regularly check that existing bugs are fixed. Related bugs:
                                 # http://jira.mariadb.org/MDEV-21939
                                 # http://jira.mariadb.org/MDEV-21940

# To install the latest clang from Chromium devs (and this automatically updates previous version installed with this method too);
# sudo yum remove clang    # Or sudo apt-get remove clang    # Only required if this procedure has never been followed yet
# cd ~
# mkdir TMP_CLANG
# cd TMP_CLANG
# git clone --depth=1 https://chromium.googlesource.com/chromium/src/tools/clang
# cd ..
# TMP_CLANG/clang/scripts/update.py

RANDOMD=$(echo $RANDOM$RANDOM$RANDOM | sed 's/..\(......\).*/\1/')  # Random 6 digit for tmp directory name

if [ "${PERFSCHEMA}" != "NO" -a "${PERFSCHEMA}" != "YES" -a "${PERFSCHEMA}" != "STATIC" -a "${PERFSCHEMA}" != "DYNAMIC" ]; then
  if [ -z "${PERFSCHEMA}" ]; then
    echo "Assert: PERFSCHEMA is empty (should be set to 'NO', 'YES', 'STATIC' or 'DYNAMIC' as it is directly passed to -DPLUGIN_PERFSCHEMA=x)."
  else
    echo "Assert: PERFSCHEMA is not set to 'NO', 'YES', 'STATIC' or 'DYNAMIC' (${PERFSCHEMA}), it should be set to 'NO', 'YES', 'STATIC' or 'DYNAMIC' as it is directly passed to -DPLUGIN_PERFSCHEMA=x."
  fi
  exit 1
fi

if [ -r MYSQL_VERSION ]; then
  if [ ! -r VERSION ]; then
    cp MYSQL_VERSION VERSION
  fi
fi
if [ ! -r VERSION ]; then
  echo "Assert: 'VERSION' file not found!"
  exit 1
fi

if [ $USE_CLANG -eq 1 -a $USE_AFL -eq 1 ]; then
  echo "Assert: USE_CLANG and USE_AFL are both set to 1 but they are mutually exclusive. Please set one (or both) to 0."
  exit 1
fi

#Check for gcc version, more than 4.9 required
GCC_VER=$(gcc -dumpversion | cut -d. -f1-2)
if (( $(echo "$GCC_VER < 4.9" |bc -l) )); then
  echo "ERR: The gcc version on the machine is $GCC_VER. Minimum gcc version required for build is 4.9. Please upgrade the gcc version."
  exit 1
fi

# Check RocksDB storage engine.
# Please note when building the facebook-mysql-5.6 tree this setting is automatically ignored
# For daily builds of fb tree (opt and dbg) also see http://jenkins.percona.com/job/fb-mysql-5.6/
# This is also auto-turned off for all 5.5 and 5.6 builds
MYSQL_VERSION_MAJOR=$(grep "MYSQL_VERSION_MAJOR" VERSION | sed 's|.*=||')
MYSQL_VERSION_MINOR=$(grep "MYSQL_VERSION_MINOR" VERSION | sed 's|.*=||')
MYSQL_VERSION_PATCH=$(grep "MYSQL_VERSION_PATCH" VERSION | sed 's|.*=||')
CURRENT_VERSION=$(printf %02d%02d%02d $MYSQL_VERSION_MAJOR $MYSQL_VERSION_MINOR $MYSQL_VERSION_PATCH)

WITH_ROCKSDB=0
if [ -d storage/rocksdb ]; then
  WITH_ROCKSDB=1
  if [[ "$CURRENT_VERSION" < "050700" ]]; then
    WITH_ROCKSDB=0
  fi
fi

SSL_MYSQL57_HACK=0
if [ -f /usr/bin/apt-get ]; then
  if [[ "$CURRENT_VERSION" < "050723" ]]; then
    SSL_MYSQL57_HACK=1
  fi
fi

ZLIB="-DWITH_ZLIB=system"

DATE=$(date +'%d%m%y')
PREFIX=
FB=0
MS=0
MD=0
if [ ${MYSQL_VERSION_MAJOR} -eq 8 ]; then  # CMake Error at cmake/zlib.cmake:136 (MESSAGE): ZLIB version must be at least 1.2.12, found 1.2.11.
  ZLIB="-DWITH_ZLIB=bundled"
fi
if [[ "${MYSQL_VERSION_MAJOR}" =~ ^1[0-1]$ ]]; then
  MD=1
  if [ $(ls support-files/rpm/*enterprise* 2>/dev/null | wc -l) -gt 0 ]; then
    PREFIX="GAL_EMD${DATE}"
  else
    PREFIX="GAL_MD${DATE}"
  fi
  ZLIB="-DWITH_ZLIB=bundled"  # 10.1 will fail with requirement for WITH_ZLIB=bundled. Building 10.1-10.5 with bundled ftm.
elif [ ! -d rocksdb ]; then  # MS, PS
  VERSION_EXTRA="$(grep "MYSQL_VERSION_EXTRA=" VERSION | sed 's|MYSQL_VERSION_EXTRA=||;s|[ \t]||g')"
  if [ "${VERSION_EXTRA}" == "" -o "${VERSION_EXTRA}" == "-dmr" -o "${VERSION_EXTRA}" == "-rc" ]; then  # MS has no extra version number, or shows '-dmr' or '-rc' (both exactly and only) in this place
    MS=1
    PREFIX="GAL_MS${DATE}"
  else
    PREFIX="GAL_PS${DATE}"
  fi
else
  PREFIX="FB${DATE}"
  FB=1
fi

# MySQL8 zlib Hack
# Use -DWITH_ZLIB=bundled instead of =system for bug https://bugs.mysql.com/bug.php?id=89373
# Also see https://bugs.launchpad.net/percona-server/+bug/1521566
# Set this to "0" if you see "Could NOT find ZLIB (missing: ZLIB_INCLUDE_DIR)"
if [[ "$CURRENT_VERSION" > "080000" ]] && [[ "$CURRENT_VERSION" < "080011" ]]; then
  ZLIB="-DWITH_ZLIB=bundled"
fi

# SSL Hack
# PS 5.7.21 will compile fine on Ubuntu Bionic, MS 5.7.21 will not and fail with this error:
# viossl.c:422:44: error: dereferencing pointer to incomplete type 'SSL_COMP {aka struct ssl_comp_st}'
# This hacks sets -DWITH_SSL=bundled of =system | Ref https://bugs.mysql.com/?id=90506 (5.7.23 will have fix)
SSL="-DWITH_SSL=system"
if [ $SSL_MYSQL57_HACK -eq 1 -a $FB -ne 1 ]; then
  SSL="-DWITH_SSL=bundled"
fi

# MariaDB: use bundled SSL
if [ ${MD} -eq 1 ]; then
  SSL="-DWITH_SSL=bundled"
fi

# Use CLANG compiler
CLANG=
if [ $USE_CLANG -eq 1 ]; then
  if [ $USE_CUSTOM_COMPILER -eq 1 ]; then
    echo "Both USE_CLANG and USE_CUSTOM_COMPILER are enabled, while they are mutually exclusive; this script can only one custom compiler! Terminating."
    exit 1
  fi
  echo "======================================================"
  echo "Note: USE_CLANG is set to 1, using the Clang compiler!"
  echo "======================================================"
  sleep 3
  CLANG="-DCMAKE_C_COMPILER=$CLANG_LOCATION -DCMAKE_CXX_COMPILER=${CLANG_LOCATION}++"  # clang++ location is assumed to be same with ++
fi

# Use AFL gcc/g++ wrapper as compiler
AFL=
if [ $USE_AFL -eq 1 ]; then
  if [ $USE_CLANG -eq 1 ]; then
    echo "Both USE_CLANG and USE_AFL are enabled, while they are mutually exclusive; this script can only one custom compiler! Terminating."
    exit 1
  fi
  if [ $USE_CUSTOM_COMPILER -eq 1 ]; then
    echo "Both USE_AFL and USE_CUSTOM_COMPILER are enabled, while they are mutually exclusive; this script can only one custom compiler! Terminating."
    exit 1
  fi
  echo "====================================================================="
  echo "Note: USE_AFL is set to 1, using the AFL gcc/g++ wrapper as compiler!"
  echo "====================================================================="
  echo "Note: ftm, AFL builds exclude RocksDB and TokuDB"
  echo "====================================================================="
  echo "Note: ftm, AFL builds require patching source code, ask Roel how to"
  echo "====================================================================="
  sleep 3
  WITH_ROCKSDB=0
  AFL="-DWITH_TOKUDB=0 -DCMAKE_C_COMPILER=$AFL_LOCATION/afl-gcc -DCMAKE_CXX_COMPILER=$AFL_LOCATION/afl-g++"
  #AFL="-DCMAKE_C_COMPILER=$AFL_LOCATION/afl-gcc -DCMAKE_CXX_COMPILER=$AFL_LOCATION/afl-g++"
fi

# ASAN, MSAN, UBSAN
SAN=
if [ $USE_SAN -eq 1 ]; then
  # MSAN and ASAN cannot be used at the same time, choose one of the two options below.
  # Also note that for MSAN to have an effect, all libs linked to MySQL must also have been compiled with this option enabled
  # Ref https://dev.mysql.com/doc/refman/5.7/en/source-configuration-options.html#option_cmake_with_msan
  #SAN="--DWITH_MSAN=ON -DWITH_UBSAN=ON"
  SAN="-DWITH_ASAN=ON -DWITH_ASAN_SCOPE=ON -DWITH_UBSAN=ON -DWITH_RAPID=OFF -DWSREP_LIB_WITH_ASAN=ON"  # Default
    # The -DWITH_RAPID=OFF is a workaround for https://bugs.mysql.com/bug.php?id=90211 - it disables GR and mysqlx (rapid plugins)
fi

# DISABLE_DBUG_TRACE
DBUG=
if [ "${DISABLE_DBUG_TRACE}" -eq 1 ]; then
  DBUG="-DWITH_DBUG_TRACE=OFF"
fi

# Use a custom compiler
CUSTOM_COMPILER=
if [ $USE_CUSTOM_COMPILER -eq 1 ]; then
  CUSTOM_COMPILER="-DCMAKE_C_COMPILER=${CUSTOM_COMPILER_LOCATION}/gcc -DCMAKE_CXX_COMPILER=${CUSTOM_COMPILER_LOCATION}/g++"
fi

FLAGS=
# Attemting to use something like    -CMAKE_C_FLAGS_DEBUG="-Wno-error" -CMAKE_CXX_FLAGS_DEBUG="-Wno-error -march=native"    Does not work here
# Using -Wno-error does not work either because of BLD-930
# In the end, using -w (produce no warnings at all when AFL is used as warnings are treated as errors and this prevents afl-gcc/afl-g++ from completing)
if [ $USE_AFL -eq 1 ]; then
  if [ $FB -eq 1 ]; then
    # The next line misses the -w but have not figured out a way to make the '-w' work in combination with '-march=native'
    # Single quotes may work
    FLAGS='-DCMAKE_CXX_FLAGS=-march=native'  # -DCMAKE_CXX_FLAGS="-march=native" is the default for FB tree
  else
    FLAGS='-DCMAKE_CXX_FLAGS=-w'
  fi
else
  if [ $FB -eq 1 ]; then
    FLAGS='-DCMAKE_CXX_FLAGS=-march=native'  # -DCMAKE_CXX_FLAGS="-march=native" is the default for FB tree
  else  # Normal builds
    if [ $USE_SAN -eq 1 ]; then
      # TODO: Check following code is correct. This error:
      # c++: error: unrecognized command line option ‘-fsanitize-coverage=trace-pc-guard’; did you mean ‘-fsanitize-coverage=trace-pc’?
      # Is seen when using gcc (i.e. USE_CLANG=0) + USE_SAN=1. Quick hack that needs more research.
      # Also ref https://clang.llvm.org/docs/SanitizerCoverage.html which has '-guard' but uses CLANG (hence the current change)
      if [ $USE_CLANG -eq 1 ]; then
        FLAGS='-DCMAKE_CXX_FLAGS=-fsanitize-coverage=trace-pc-guard'
      else
        # This was disabled also due to the following errors:
        # testCXXCompiler.cxx:(.text+0xa): undefined reference to `__sanitizer_cov_trace_pc'
        # testCXXCompiler.cxx:(.text+0x14): undefined reference to `__sanitizer_cov_trace_pc'
        # FLAGS='-DCMAKE_CXX_FLAGS=-fsanitize-coverage=trace-pc'
        # And the following was needed to avoid this error on mysqld startup:
        # ==PID== ASan runtime does not come first in initial library list; you should either link runtime to your application or manually preload it with LD_PRELOAD.
        FLAGS='-DCMAKE_CXX_FLAGS=-static-libasan'
        echo "Using GCC for ASAN build."
      fi
    fi
  fi
fi
# Also note that -k can be use for make to ignore any errors; if the build fails somewhere in the tests/unit tests then it matters
# little. Note that -k is not a compiler flag as -w is. It is a make option.

# Ignore warnings
if [ ${IGNORE_WARNINGS} -eq 1 ]; then
  FLAGS="${FLAGS} -DMYSQL_MAINTAINER_MODE=OFF"
fi

CURPATH=$(echo $PWD | sed 's|.*/||')

cd ..
rm -Rf ${CURPATH}_dbg
rm -f /tmp/psms_dbg_build_${RANDOMD}
cp -R ${CURPATH} ${CURPATH}_dbg
cd ${CURPATH}_dbg

### TEMPORARY HACK TO AVOID COMPILING TB (WHICH IS NOT READY YET)
rm -Rf ./plugin/tokudb-backup-plugin

BOOST=
if [ ${USE_BOOST_LOCATION} -eq 1 ]; then
  if [ ! -r ${BOOST_LOCATION} ]; then
    echo "Assert; USE_BOOST_LOCATION was set to 1, but the file at BOOST_LOCATION (${BOOST_LOCATION} cannot be read!"
    exit 1
  else
    BOOST="-DDOWNLOAD_BOOST=0 -DWITH_BOOST=${BOOST_LOCATION}"
  fi
else
  # Avoid previously downloaded boost's from creating problems
  rm -Rf /tmp/boost_${RANDOMD}
  mkdir /tmp/boost_${RANDOMD}
  BOOST="-DDOWNLOAD_BOOST=1 -DWITH_BOOST=/tmp/boost_${RANDOMD}"
fi

if [ $FB -eq 0 ]; then
  # MD,PS,MS,PXC build. Consider adding -DWITH_KEYRING_TEST=ON depeding on bug https://bugs.mysql.com/bug.php?id=90212 outcome
  XPAND=''
  if [ -r storage/xpand/ha_xpand.h ]; then
    sleep 0.1
    #XPAND='-DWITH_XPAND=1'  # Disabled ftm due to cnf limitation (https://mariadb.com/kb/en/mariadb-maxscale-25-maxscale-and-xpand-tutorial/)
  fi
  CMD="cmake . $CLANG $AFL $SSL -DCMAKE_BUILD_TYPE=Debug -DBUILD_CONFIG=mysql_release ${EXTRA_AUTO_OPTIONS} ${XPAND} -DWITH_TOKUDB=0 -DWITH_JEMALLOC=no -DFEATURE_SET=community -DDEBUG_EXTNAME=OFF -DWITH_EMBEDDED_SERVER=${WITH_EMBEDDED_SERVER} -DENABLE_DOWNLOADS=1 ${BOOST} -DENABLED_LOCAL_INFILE=${WITH_LOCAL_INFILE} -DENABLE_DTRACE=0 -DWITH_SAFEMALLOC=OFF -DPLUGIN_PERFSCHEMA=${PERFSCHEMA} ${DBUG} ${ZLIB} -DWITH_ROCKSDB=${WITH_ROCKSDB} -DWITH_PAM=ON -DWITH_MARIABACKUP=1 -WITH-WSREP -DFORCE_INSOURCE_BUILD=1 ${SAN} ${FLAGS}"
  echo "Build command used:"
  echo $CMD
  eval "$CMD" 2>&1 | tee /tmp/psms_dbg_build_${RANDOMD}
  if [ $? -ne 0 ]; then echo "Assert: non-0 exit status detected for make!"; exit 1; fi
else
  # FB build, disabled for Galera builds
  #CMD="cmake . $CLANG $AFL $SSL -DCMAKE_BUILD_TYPE=Debug -DBUILD_CONFIG=mysql_release ${EXTRA_AUTO_OPTIONS} -DWITH_JEMALLOC=no -DFEATURE_SET=community -DDEBUG_EXTNAME=OFF -DWITH_EMBEDDED_SERVER=${WITH_EMBEDDED_SERVER} -DENABLE_DOWNLOADS=1 ${BOOST} -DENABLED_LOCAL_INFILE=${WITH_LOCAL_INFILE} -DENABLE_DTRACE=0 -DWITH_SAFEMALLOC=OFF -DPLUGIN_PERFSCHEMA=${PERFSCHEMA} ${DBUG} ${ZLIB} ${FLAGS}"
  echo "Build command used:"
  echo $CMD
  eval "$CMD" 2>&1 | tee /tmp/psms_dbg_build_${RANDOMD}
  if [ $? -ne 0 ]; then echo "Assert: non-0 exit status detected for make!"; exit 1; fi
fi

make -j${MAKE_THREADS} | tee -a /tmp/psms_dbg_build_${RANDOMD}
if [ $? -ne 0 ]; then echo "Assert: non-0 exit status detected for make!"; exit 1; fi

echo $CMD > BUILD_CMD_CMAKE
if [ ! -r ./scripts/make_binary_distribution ]; then  # Note: ./scripts/binary_distribution is created on-the-fly during the make compile
  echo "Assert: ./scripts/make_binary_distribution was not found. Terminating."
  exit 1
else
  ./scripts/make_binary_distribution | tee -a /tmp/psms_dbg_build_${RANDOMD}
  if [ $? -ne 0 ]; then echo "Assert: non-0 exit status detected for ./scripts/make_binary_distribution!"; exit 1; fi
fi

TAR_dbg=$(ls -1 *.tar.gz | grep -v "boost" | head -n1)
if [[ "${TAR_dbg}" == *".tar.gz"* ]]; then
  DIR_dbg=$(echo "${TAR_dbg}" | sed 's|.tar.gz||')
  TAR_dbg_new=$(echo "${PREFIX}-${TAR_dbg}" | sed 's|.tar.gz|-dbg.tar.gz|')
  DIR_dbg_new=$(echo "${TAR_dbg_new}" | sed 's|.tar.gz||')
  if [ "${DIR_dbg}" != "" ]; then rm -Rf ../${DIR_dbg}; fi
  if [ "${DIR_dbg_new}" != "" ]; then rm -Rf ../${DIR_dbg_new}; fi
  if [ "${TAR_dbg_new}" != "" ]; then rm -Rf ../${TAR_dbg_new}; fi
  mv ${TAR_dbg} ../${TAR_dbg_new}
  if [ $? -ne 0 ]; then echo "Assert: non-0 exit status detected for moving of tarball!"; exit 1; fi
  cd ..
  tar -xf ${TAR_dbg_new}
  if [ $? -ne 0 ]; then echo "Assert: non-0 exit status detected for tar!"; exit 1; fi
  mv ${DIR_dbg} ${DIR_dbg_new}
  if [ $? -ne 0 ]; then echo "Assert: non-0 exit status detected for moving of tarball (2)!"; exit 1; fi
  # Store revision (used by source_code_rev.sh to find revision for, for example, MS builds)
  cd - >/dev/null
  git log | grep -om1 'commit.*' | awk '{print $2}' | sed 's|[ \n\t]\+||g' > ../${DIR_dbg_new}/git_revision.txt
  echo $CMD > ../${DIR_dbg_new}/BUILD_CMD_CMAKE
  cd ..
  #rm -Rf ${CURPATH}_dbg  # Best not to delete it; this way gdb dbgging is better quality as source will be available!
  # Create/Copy galera library
  if [[ ${MYSQL_VERSION_MAJOR}.${MYSQL_VERSION_MINOR} =~ 10.[2-3] ]]; then
    GALERA_BUILD_LOC=${PWD}/galera_3x
  else
    GALERA_BUILD_LOC=${PWD}/galera_4x
  fi
  if [ -d ${GALERA_BUILD_LOC}_dbg ]; then
    if [[ -f ${GALERA_BUILD_LOC}_dbg/libgalera_smm.so ]] || [[ -f ${GALERA_BUILD_LOC}_dbg/libgalera_enterprise_smm.so ]] ; then
      if [[ $(echo $PREFIX | cut -c1-7) == "GAL_EMD" ]]; then
        cp ${GALERA_BUILD_LOC}_dbg/libgalera_enterprise_smm.so ${DIR_dbg_new}/lib/libgalera_smm.so
      else
        cp ${GALERA_BUILD_LOC}_dbg/libgalera_smm.so ${DIR_dbg_new}/lib/libgalera_smm.so
        echo "cp ${GALERA_BUILD_LOC}_dbg/libgalera_smm.so ${DIR_dbg_new}/lib/libgalera_smm.so"
      fi
      cp ${GALERA_BUILD_LOC}_dbg/garb/garbd ${DIR_dbg_new}/bin/
    else
      echo "WARNING! Could not copy libgalera_smm.so to ${DIR_dbg_new}, please copy manually"
    fi
  else
    cp -r ${GALERA_BUILD_LOC} ${GALERA_BUILD_LOC}_dbg
    cd ${GALERA_BUILD_LOC}_dbg
    cmake . | tee /tmp/psms_dbg_galera_build_${RANDOMD}
    make | tee -a /tmp/psms_dbg_galera_build_${RANDOMD}
    if [[ $(echo $PREFIX | cut -c1-7) == "GAL_EMD" ]]; then
      cp libgalera_enterprise_smm.so ../${DIR_dbg_new}/lib/libgalera_smm.so
    else
      cp libgalera_smm.so ../${DIR_dbg_new}/lib/libgalera_smm.so
    fi
    cp garb/garbd ${DIR_dbg_new}/bin/
    cd ..
  fi

  exit 0
else
  echo "There was some unknown build issue... Have a nice day!"
  exit 1
fi
