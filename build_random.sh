#!/bin/bash
# Build the standalone xoshiro256++ random integer utility (mariadb-qa/random).
# Used by pquery-run.sh PRE_SHUFFLE_SQL=4 for high-entropy per-file sample sizes;
# also a safe drop-in for bash ${RANDOM}. No external dependencies.
SCRIPT_PWD=$(dirname $(readlink -f "${0}"))
CXX="${CXX:-clang++}"
"${CXX}" -O2 -std=c++20 "${SCRIPT_PWD}/random.cpp" -o "${SCRIPT_PWD}/random" && echo "Built ${SCRIPT_PWD}/random"
