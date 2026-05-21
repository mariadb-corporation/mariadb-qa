#!/bin/bash
# Created by Roel Van de Paar, MariaDB
# Build the standalone xoshiro256++ entropy quality test.
# Usage:  ./build.sh           # release
#         ./build.sh debug     # -O0 -g for stepping through the PRNG

set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-release}"
CXX="${CXX:-g++}"
OUT="entropy_test"
SRC="entropy_test.cpp"

case "$MODE" in
  release|rel|"")
    FLAGS=(-std=c++20 -O3 -march=native -mtune=native -pipe -DNDEBUG)
    ;;
  debug|dbg)
    FLAGS=(-std=c++20 -O0 -g3 -fno-omit-frame-pointer)
    ;;
  *)
    echo "usage: $0 [release|debug]"; exit 2
    ;;
esac

echo "[entropy/build.sh] mode=$MODE cxx=$CXX"
"$CXX" "${FLAGS[@]}" "$SRC" -o "$OUT"
echo "[entropy/build.sh] built: $OUT ($(stat -c %s "$OUT") bytes)"
echo "[entropy/build.sh] sanity: $(./$OUT 100000 2>&1 | head -1)"
