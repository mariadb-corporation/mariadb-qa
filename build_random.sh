#!/bin/bash
# Build the standalone xoshiro256++ random utility (mariadb-qa/random), the entropy source
# for the framework shell scripts. Clang+libc++ is the canonical toolchain, matching
# generatorcpp, revgen and reducercpp. No other dependencies.
# Built atomically so a concurrent run never sees a partial binary.
SCRIPT_PWD=$(dirname $(readlink -f "${0}"))
CXX="${CXX:-clang++}"
TMP="${SCRIPT_PWD}/random.tmp"
rm -f "${TMP}"
"${CXX}" -O2 -std=c++20 -stdlib=libc++ -Wl,--build-id=sha1 "${SCRIPT_PWD}/random.cpp" -o "${TMP}" -lc++abi || exit 1
mv -f "${TMP}" "${SCRIPT_PWD}/random"
echo "Built ${SCRIPT_PWD}/random"
