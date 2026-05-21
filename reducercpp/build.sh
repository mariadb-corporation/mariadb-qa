#!/bin/bash
# Created by Roel Van de Paar, MariaDB
# Build script for the C++ port of reducer.sh (MariaDB QA testcase reducer).
# Single TU build. Clang+libc++ is the canonical toolchain (see global memory
# feedback_clang_only_builds).
#
# Usage:  ./build.sh           # release    -> reducer        (LTO, -O3)
#         ./build.sh debug     # debug      -> reducer_dbg    (-O0 -g3)
#         ./build.sh ubsan     # UBSan      -> reducer_ubasan
#         ./build.sh asan      # ASAN+UBSan -> reducer_asan

set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-release}"
CXX="${CXX:-clang++}"

COMMON_FLAGS=(
  -std=c++20
  -stdlib=libc++
  -pthread
  -Wall -Wno-unused-variable -Wno-unused-but-set-variable -Wno-unused-function -Wno-unused-parameter
)

REL_FLAGS=(
  -O3 -march=native -mtune=native
  -flto=thin
  -fomit-frame-pointer
  -fno-stack-protector
  -DNDEBUG
  -pipe
)
REL_LINK_FLAGS=(
  -O3 -flto=thin
  -Wl,-O2 -Wl,--as-needed -Wl,--gc-sections
  -s
  -stdlib=libc++
  -lc++abi
)

DBG_FLAGS=(-O0 -g3 -fno-omit-frame-pointer)
UBSAN_FLAGS=(-O1 -g -fsanitize=undefined -fno-omit-frame-pointer -pipe)
ASAN_FLAGS=(-O1 -g -fsanitize=address -fsanitize=undefined -fno-omit-frame-pointer -pipe)

case "$MODE" in
  release|rel|"")
    OUT="reducer"
    FLAGS=("${COMMON_FLAGS[@]}" "${REL_FLAGS[@]}")
    LINK_FLAGS=("${REL_LINK_FLAGS[@]}")
    ;;
  debug|dbg)
    OUT="reducer_dbg"
    FLAGS=("${COMMON_FLAGS[@]}" "${DBG_FLAGS[@]}")
    LINK_FLAGS=(-stdlib=libc++ -lc++abi)
    ;;
  ubsan)
    OUT="reducer_ubasan"
    FLAGS=("${COMMON_FLAGS[@]}" "${UBSAN_FLAGS[@]}")
    LINK_FLAGS=(-fsanitize=undefined -stdlib=libc++ -lc++abi)
    ;;
  asan)
    OUT="reducer_asan"
    FLAGS=("${COMMON_FLAGS[@]}" "${ASAN_FLAGS[@]}")
    LINK_FLAGS=(-fsanitize=address -fsanitize=undefined -stdlib=libc++ -lc++abi)
    ;;
  *)
    echo "usage: $0 [release|debug|ubsan|asan]"; exit 2
    ;;
esac

echo "[build.sh] mode=$MODE cxx=$CXX out=$OUT"
echo "[build.sh] cxxflags: ${FLAGS[*]}"

# Atomic-rename so concurrent reducer runs never see a partial binary.
TMP="${OUT}.tmp"
rm -f "$TMP"
"$CXX" "${FLAGS[@]}" reducer.cpp -o "$TMP" "${LINK_FLAGS[@]}"
mv -f "$TMP" "$OUT"

echo "[build.sh] built: $OUT ($(stat -c %s "$OUT") bytes)"
