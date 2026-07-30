#!/bin/bash
# Build revgen and verify it.
#
#   ./build.sh              release build, then test.sh, then the coverage gate
#   BUILD=dbg ./build.sh    revgen_dbg (-O0 -g), then test.sh
#   BUILD=cov ./build.sh    coverage build and report only
#   BUILD=asan|ubasan|msan|tsan ./build.sh    sanitizer build, then test.sh
#   SKIP_TESTS=1 ./build.sh      build only
#   SKIP_COVERAGE=1 ./build.sh   build and test, no coverage gate
#
# Links the system MariaDB/MySQL client for --validate-sql (PREPARE testing).
set -e
cd "$(dirname "$0")"
# libc++ avoids the gcc-14 libstdc++ <unicode.h> incompatibility with clang.
FLAGS="-std=c++20 -stdlib=libc++ -Wall -Wextra -pthread"
LIBS="-lmysqlclient"
# The release binary is committed and has to run on machines whose shared
# libc++ is older than the build box's, so its C++ runtime links statically.
# -nostdlib++ keeps the driver from appending the shared libc++ after the
# archives. A box without the archives builds a dynamic, local-only binary.
CXXA=$(clang++ -print-file-name=libc++.a)
ABIA=$(clang++ -print-file-name=libc++abi.a)
UNWA=$(clang++ -print-file-name=libunwind.a)
CXXRT=""
if [ -f "$CXXA" ] && [ -f "$ABIA" ]; then
  [ -f "$UNWA" ] || UNWA=""
  CXXRT="-nostdlib++ $CXXA $ABIA $UNWA -static-libgcc"
fi
COV_MIN=${COV_MIN:-95}

# Line coverage of revgen.cpp from a run of the test suite. Gated, because the
# suite is what stands between a grammar-handling regression and thousands of
# wasted trials.
coverage() {
  local bin=revgen_cov prof=.cov lines
  for t in llvm-profdata llvm-cov; do
    command -v $t >/dev/null || {
      echo "coverage: $t not on PATH - skipping the coverage gate"; return 0; }
  done
  rm -rf $prof; mkdir -p $prof
  clang++ $FLAGS -O1 -g -fprofile-instr-generate -fcoverage-mapping \
    -o $bin revgen.cpp $LIBS
  LLVM_PROFILE_FILE="$PWD/$prof/r-%p.profraw" ./test.sh ./$bin >$prof/test.log 2>&1 || {
    echo "coverage run: test.sh failed"; tail -20 $prof/test.log; return 1; }
  llvm-profdata merge -sparse $prof/r-*.profraw -o $prof/all.profdata
  llvm-cov report ./$bin -instr-profile=$prof/all.profdata revgen.cpp | tail -3
  lines=$(llvm-cov export ./$bin -instr-profile=$prof/all.profdata revgen.cpp \
    --summary-only | grep -oP '"lines":\{"count":[0-9]+,"covered":[0-9]+' | head -1 |
    awk -F'[:,]' '{printf "%.1f", 100*$5/$3}')
  echo "line coverage: ${lines}% (floor ${COV_MIN}%)"
  awk -v l="$lines" -v m="$COV_MIN" 'BEGIN{exit !(l+0 >= m+0)}' || {
    echo "below floor - uncovered lines:"
    llvm-cov show ./$bin -instr-profile=$prof/all.profdata revgen.cpp \
      --show-line-counts 2>/dev/null | grep -E "^ *[0-9]+\| *0\|" | head -40
    return 1; }
}

# san <suffix> <sanitizer flags...>
san() {
  local suffix=$1; shift
  clang++ $FLAGS -O1 -g -fno-omit-frame-pointer "$@" \
    -o revgen_$suffix revgen.cpp $LIBS
  echo "built revgen_$suffix"
  [ -n "${SKIP_TESTS}" ] || ./test.sh ./revgen_$suffix
}

# MSAN reports uninitialised reads inside any library it links that was not
# itself instrumented, so it uses the instrumented libc++ from /MSAN_libs rather
# than the system one. libmysqlclient has no instrumented build and neither does
# the OpenSSL it initialises, so the tests that enter it are excluded.
MSAN_LIBS=${MSAN_LIBS:-/MSAN_libs}
msan_build() {
  [ -f "$MSAN_LIBS/libc++.so" ] || {
    echo "msan: no instrumented libc++ at $MSAN_LIBS - build it first"; return 1; }
  clang++ -std=c++20 -Wall -Wextra -pthread -O1 -g -fno-omit-frame-pointer \
    -fsanitize=memory -fsanitize-memory-track-origins=2 \
    -nostdinc++ -isystem $MSAN_LIBS/include/c++/v1 \
    -L$MSAN_LIBS -Wl,-rpath,$MSAN_LIBS \
    -o revgen_msan revgen.cpp -lc++ -lc++abi $LIBS
  echo "built revgen_msan"
  [ -n "${SKIP_TESTS}" ] || REVGEN_TEST_NO_CLIENT=1 ./test.sh ./revgen_msan
}

case "${BUILD}" in
  dbg)
    clang++ $FLAGS -O0 -g -o revgen_dbg revgen.cpp $LIBS
    echo "built revgen_dbg"
    [ -n "${SKIP_TESTS}" ] || ./test.sh ./revgen_dbg
    ;;
  cov)    coverage ;;
  asan)   san asan   -fsanitize=address ;;
  ubasan) san ubasan -fsanitize=address,undefined -fno-sanitize-recover=undefined ;;
  msan)   msan_build ;;
  tsan)   san tsan   -fsanitize=thread ;;
  *)
    clang++ $FLAGS -O2 -o revgen revgen.cpp $CXXRT $LIBS
    echo "built revgen"
    [ -n "$CXXRT" ] || echo "note: static libc++ archives not found -" \
      "built against shared libc++; fine to run, do not commit this binary"
    [ -n "${SKIP_TESTS}" ] || ./test.sh ./revgen
    [ -n "${SKIP_COVERAGE}" ] || coverage
    ;;
esac
