#!/bin/bash
# Created by Roel Van de Paar, MariaDB
# Lint checker for the C++ SQL fuzz generator (generator.cpp + pools.h).
#
# Mirrors build.sh's toolchain (clang / libc++ / C++20) and MariaDB basedir pick,
# so a clean lint matches a clean build. The default mode is -fsyntax-only: it parses
# the full 22 MB translation unit without codegen, so it is far lighter than a real
# build (~1 min, <1 GB RSS) and catches errors before the ~5 min release compile.
#
# The generated dispatch tables carry many intentional unused temporaries and pool
# size constants, so the warning posture matches build.sh (unused-* suppressed).
#
# Usage:  ./lint.sh            # syntax + build-flag warnings, fails on any warning (gate)
#         ./lint.sh strict     # + -Wextra -Wshadow, informational (may be noisy)
#         ./lint.sh tidy       # clang-tidy deep static analysis (heavy, opt-in)

set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-syntax}"
CXX="${CXX:-clang++}"

# Same basedir pick as build.sh: highest MariaDB -opt basedir from gendirs.sh.
pick_mariadb_basedir() {
  local best path
  best=$( ( cd /test && /test/gendirs.sh ) 2>/dev/null \
    | grep -E '^MD.*-opt$' \
    | awk -F'-mariadb-' '{ print $2, $0 }' \
    | sort -V | tail -1 | awk '{print $2}')
  [ -n "$best" ] || { echo "[lint.sh] no MariaDB -opt basedir from gendirs.sh" >&2; exit 2; }
  path="/test/$best"
  [ -f "$path/include/mysql/mysql.h" ] || { echo "[lint.sh] $path: include/mysql/mysql.h missing" >&2; exit 2; }
  printf '%s\n' "$path"
}
MARIADB_BASEDIR="$(pick_mariadb_basedir)"

BASE_FLAGS=(-std=c++20 -stdlib=libc++ -I"$MARIADB_BASEDIR/include")
# Warning posture matches build.sh.
WARN_FLAGS=(-Wall -Wno-unused-variable -Wno-unused-but-set-variable -Wno-unused-function)

echo "[lint.sh] mode=$MODE cxx=$CXX basedir=$MARIADB_BASEDIR"

case "$MODE" in
  syntax|"")
    "$CXX" "${BASE_FLAGS[@]}" "${WARN_FLAGS[@]}" -Werror -fsyntax-only generator.cpp
    echo "[lint.sh] clean"
    ;;
  strict)
    "$CXX" "${BASE_FLAGS[@]}" "${WARN_FLAGS[@]}" -Wextra -Wshadow -fsyntax-only generator.cpp
    echo "[lint.sh] strict pass complete"
    ;;
  tidy)
    command -v clang-tidy >/dev/null || { echo "[lint.sh] clang-tidy not found" >&2; exit 2; }
    echo "[lint.sh] clang-tidy on a 22 MB TU is heavy (~15-30 min, several GB). Config: .clang-tidy"
    clang-tidy generator.cpp -- "${BASE_FLAGS[@]}"
    ;;
  *)
    echo "usage: $0 [syntax|strict|tidy]"; exit 2
    ;;
esac
