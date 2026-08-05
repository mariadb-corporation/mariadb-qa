#!/bin/bash
# Build the framework C++ tools: the testcase reducer and the two testing SQL
# generators. Run this after a mariadb-qa update, and after the first server
# build, because the generatorcpp generator links against a MariaDB basedir.

set -u
QA_DIR="${HOME}/mariadb-qa"
RC=0

build_one() {  # $1 = directory under mariadb-qa, $2 = expected binary
  local DIR="${QA_DIR}/${1}"
  if [ ! -x "${DIR}/build.sh" ]; then
    echo "[qa-tools] skip ${1}: no build.sh"
    return 0
  fi
  echo "[qa-tools] building ${1}"
  # The build scripts can also produce a coverage report of the tool itself.
  # That is a developer step, so it stays out of the box build
  if ( cd "${DIR}" && SKIP_COVERAGE=1 ./build.sh ); then
    echo "[qa-tools] ${1}: $(ls -la "${DIR}/${2}" 2>/dev/null | awk '{print $5" bytes"}')"
  else
    echo "[qa-tools] ${1}: build failed"
    RC=1
  fi
}

build_one reducercpp reducer
build_one revgen revgen

# The generator needs an -opt basedir with lib/libmariadbclient.a, which only
# exists once a server build is complete
if ls -d /test/MD*-opt >/dev/null 2>&1; then
  build_one generatorcpp generator
else
  echo "[qa-tools] skip generatorcpp: no MariaDB -opt basedir in /test yet."
  echo "[qa-tools] The generator that ships with the framework runs as it is."
  echo "[qa-tools] Rebuild it with qa-tools once a server build is there."
fi

exit ${RC}
