#!/bin/bash
# Created by Roel Van de Paar, MariaDB
# Build script for the C++ port of the MariaDB SQL fuzz generator.
# Clang+libc++ is the canonical toolchain (gcc's separate `as` step OOMs on the
# multi-GB sanitizer-instrumented .s output of this single-TU 16 MB file; clang has
# an integrated assembler and uses ~50× less peak RSS at the same phase).
#
# Usage:  ./build.sh           # release build (LTO, -O3)
#         ./build.sh debug     # -O0 + -g for debugging
#         ./build.sh ubsan     # UndefinedBehaviorSanitizer
#         ./build.sh asan      # ASAN + UBSAN

set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-release}"
CXX="${CXX:-clang++}"

COMMON_FLAGS=(
  -std=c++20
  -stdlib=libc++             # libc++ avoids gcc-14 libstdc++ header incompat (`++this` in <unicode.h>)
  -pthread
  -Wall -Wno-unused-variable -Wno-unused-but-set-variable -Wno-unused-function
)

REL_FLAGS=(
  -O3 -march=native -mtune=native
  -flto=thin                  # clang's ThinLTO — fast, multi-threaded link-phase
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

# libmysqlclient — used by --validate-sql; system /usr/include/mysql/mysql.h + libmysqlclient.
MYSQL_LIBS=(-lmysqlclient)

case "$MODE" in
  release|rel|"")
    OUT="generator"
    FLAGS=("${COMMON_FLAGS[@]}" "${REL_FLAGS[@]}")
    LINK_FLAGS=("${REL_LINK_FLAGS[@]}")
    ;;
  debug|dbg)
    OUT="generator_dbg"
    FLAGS=("${COMMON_FLAGS[@]}" "${DBG_FLAGS[@]}")
    LINK_FLAGS=(-stdlib=libc++ -lc++abi)
    ;;
  ubsan)
    OUT="generator_ubasan"
    FLAGS=("${COMMON_FLAGS[@]}" "${UBSAN_FLAGS[@]}")
    LINK_FLAGS=(-fsanitize=undefined -stdlib=libc++ -lc++abi)
    ;;
  asan)
    OUT="generator_asan"
    FLAGS=("${COMMON_FLAGS[@]}" "${ASAN_FLAGS[@]}")
    LINK_FLAGS=(-fsanitize=address -fsanitize=undefined -stdlib=libc++ -lc++abi)
    ;;
  *)
    echo "usage: $0 [release|debug|ubsan|asan]"; exit 2
    ;;
esac

echo "[build.sh] mode=$MODE cxx=$CXX"
echo "[build.sh] cxxflags: ${FLAGS[*]}"

# Atomic-rename pattern: compile to .tmp, then mv into place so any
# concurrently-running pquery-run.sh trial never sees a partial binary.
TMP="${OUT}.tmp"
rm -f "$TMP"
"$CXX" "${FLAGS[@]}" generator.cpp -o "$TMP" "${LINK_FLAGS[@]}" "${MYSQL_LIBS[@]}"
mv -f "$TMP" "$OUT"

echo "[build.sh] built: $OUT ($(stat -c %s "$OUT") bytes)"
echo "[build.sh] sanity: $(./$OUT --help 2>&1 | head -1)"
