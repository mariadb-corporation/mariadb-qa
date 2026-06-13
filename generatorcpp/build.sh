#!/bin/bash
# Created by Roel Van de Paar, MariaDB
# Build script for the C++ port of the MariaDB SQL fuzz generator.
# Clang+libc++ is the canonical toolchain (gcc's separate `as` step OOMs on the
# multi-GB sanitizer-instrumented .s output of this single-TU 22 MB file; clang has
# an integrated assembler and uses far less peak RSS).
#
# Build profile (clang 21, generator.cpp ≈ 22 MB single TU):
#
#   mode      output             time      peak RSS    use case
#   ----      ------             ----      --------    --------
#   release   generator          ~5 min    ~10-15 GB   production / pquery-run
#   debug     generator_dbg      ~5 s      ~2-3 GB     gdb / iteration
#   ubsan     generator_ubasan   ~33 min   ~20 GB      UB detection
#   asan      generator_asan     ~40 min   ~30 GB      ASAN+UBSAN, heaviest
#
# IMPORTANT: only one mode at a time — two concurrent clang compiles of this TU
# can push the 125 GB host into swap thrashing (peaks combine + page-cache).
# Check `ps -ef | grep clang.*generator.cpp` before starting any build.
#
# Usage:  ./build.sh           # release build
#         ./build.sh debug
#         ./build.sh ubsan
#         ./build.sh asan
#         ./build.sh static

set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-release}"
CXX="${CXX:-clang++}"

# Pick the MariaDB basedir whose libmariadbclient + headers we link against.
# Source: /test/gendirs.sh (default mode emits MD/EMD/MS basedirs, respects
# /test/REGEX_EXCLUDE). We keep MD*-opt only (plain MariaDB, opt variant),
# pull -mariadb-X.Y.Z to the front, sort -V, take the top — so the highest
# MariaDB version wins regardless of MD<DDMMYY> stamp.
pick_mariadb_basedir() {
  local best path
  best=$( ( cd /test && /test/gendirs.sh ) 2>/dev/null \
    | grep -E '^MD.*-opt$' \
    | awk -F'-mariadb-' '{ print $2, $0 }' \
    | sort -V \
    | tail -1 \
    | awk '{print $2}')
  [ -n "$best" ] || { echo "[build.sh] no MariaDB -opt basedir from gendirs.sh" >&2; exit 2; }
  path="/test/$best"
  [ -f "$path/lib/libmariadbclient.a" ] || { echo "[build.sh] $path: libmariadbclient.a missing" >&2; exit 2; }
  [ -f "$path/include/mysql/mysql.h"  ] || { echo "[build.sh] $path: include/mysql/mysql.h missing" >&2; exit 2; }
  printf '%s\n' "$path"
}
MARIADB_BASEDIR="$(pick_mariadb_basedir)"

COMMON_FLAGS=(
  -std=c++20
  -stdlib=libc++             # libc++ avoids gcc-14 libstdc++ header incompat (`++this` in <unicode.h>)
  -pthread
  -Wall -Wno-unused-variable -Wno-unused-but-set-variable -Wno-unused-function
)

REL_FLAGS=(
  -Os -march=native -mtune=native
  -flto=thin                  # clang's ThinLTO — fast, multi-threaded link-phase
  -fomit-frame-pointer
  -fno-stack-protector
  -DNDEBUG
  -pipe
)
REL_LINK_FLAGS=(
  -Os -flto=thin
  -fuse-ld=lld                # clang 22's LTO needs lld; GNU ld lacks LLVMgold.so
  -Wl,-O2 -Wl,--as-needed -Wl,--gc-sections
  -s
  -stdlib=libc++
  -lc++abi
)

DBG_FLAGS=(-O0 -g3 -fno-omit-frame-pointer)
UBSAN_FLAGS=(-O1 -g -fsanitize=undefined -fno-omit-frame-pointer -pipe)
ASAN_FLAGS=(-O1 -g -fsanitize=address -fsanitize=undefined -fno-omit-frame-pointer -pipe)

# Client lib: MariaDB's libmariadbclient from the picked basedir (not system libmysqlclient).
# Dynamic builds embed an rpath so the loader finds libmariadb.so.3 at runtime.
# Static build links libmariadbclient.a + all transitive deps as archives.
MYSQL_FLAGS=(-I"$MARIADB_BASEDIR/include")
MYSQL_LIBS=(-L"$MARIADB_BASEDIR/lib" -lmariadbclient -lgnutls -lssl -lcrypto -lz -lzstd -lresolv -lm -ldl)
MYSQL_RPATH=(-Wl,-rpath,"$MARIADB_BASEDIR/lib")

case "$MODE" in
  release|rel|"")
    OUT="generator"
    FLAGS=("${COMMON_FLAGS[@]}" "${REL_FLAGS[@]}")
    LINK_FLAGS=("${REL_LINK_FLAGS[@]}" "${MYSQL_RPATH[@]}")
    ;;
  debug|dbg)
    OUT="generator_dbg"
    FLAGS=("${COMMON_FLAGS[@]}" "${DBG_FLAGS[@]}")
    LINK_FLAGS=(-stdlib=libc++ -lc++abi "${MYSQL_RPATH[@]}")
    ;;
  ubsan)
    OUT="generator_ubasan"
    FLAGS=("${COMMON_FLAGS[@]}" "${UBSAN_FLAGS[@]}")
    LINK_FLAGS=(-fsanitize=undefined -stdlib=libc++ -lc++abi "${MYSQL_RPATH[@]}")
    ;;
  asan)
    OUT="generator_asan"
    FLAGS=("${COMMON_FLAGS[@]}" "${ASAN_FLAGS[@]}")
    LINK_FLAGS=(-fsanitize=address -fsanitize=undefined -stdlib=libc++ -lc++abi "${MYSQL_RPATH[@]}")
    ;;
  static|stat)
    # Fully-static release build. No rpath (everything baked in). Transitive
    # libmariadbclient deps (-lssl -lcrypto -lz -lzstd -lresolv -lm) must be
    # named explicitly — .a archives carry no DT_NEEDED.
    OUT="generator_static"
    FLAGS=("${COMMON_FLAGS[@]}" "${REL_FLAGS[@]}")
    LINK_FLAGS=(
      -Os -flto=thin
      -fuse-ld=lld
      -Wl,-O2 -Wl,--gc-sections
      -s
      -static
      -stdlib=libc++
      -lc++abi
    )
    MYSQL_LIBS+=(-lssl -lcrypto -lz -lzstd -lresolv -lm -ldl -lpthread)
    ;;
  *)
    echo "usage: $0 [release|debug|ubsan|asan|static]"; exit 2
    ;;
esac

echo "[build.sh] mode=$MODE cxx=$CXX"
echo "[build.sh] mariadb basedir: $MARIADB_BASEDIR"
echo "[build.sh] cxxflags: ${FLAGS[*]}"

# Atomic-rename pattern: compile to .tmp, then mv into place so any
# concurrently-running pquery-run.sh trial never sees a partial binary.
TMP="${OUT}.tmp"
rm -f "$TMP"
"$CXX" "${FLAGS[@]}" "${MYSQL_FLAGS[@]}" generator.cpp -o "$TMP" "${LINK_FLAGS[@]}" "${MYSQL_LIBS[@]}"
mv -f "$TMP" "$OUT"

echo "[build.sh] built: $OUT ($(stat -c %s "$OUT") bytes)"
echo "[build.sh] sanity: $(./$OUT --help 2>&1 | head -1)"
