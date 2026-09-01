#!/bin/bash
# Install the grammar files revgen needs, pulled from the MariaDB server repository on GitHub.
#
# revgen walks the server's own yacc grammar, and pairs it with the keyword table that sits
# beside it in the same directory. Both files must come from the same version, so they are
# fetched together, one pair per version:
#
#   sql/sql_yacc.yy  the grammar        ->  yacc/<version>_sql_yacc.yy
#   sql/lex.h        the keyword table  ->  yacc/<version>_lex.h
#
# sql/sql_lex.h sits next to sql/lex.h and is a different file. It carries no SYM() entries.
# With that file in place revgen finds no keyword text, so every keyword drops out of the
# generated SQL and what comes out is unparsable fragments. Each file is checked here before
# it is installed, and a version that fails a check installs nothing.
#
# A version also needs a third file, <version>_coldefs.txt, the column types revgen builds its
# tables from. That one comes from a running server rather than from GitHub, so where it is
# missing this brings up a copy of that version's own build and calls harvest_coldefs.sh
# against it. Delete a coldefs file to have it built again.
#
# With no arguments the versions come from /test/gendirs.sh, so the grammar set follows the
# builds this box tests. The newest version has no branch of its own and lives on main, which
# is looked up rather than listed here.
#
# Usage: ./refresh_grammars.sh                 # every version /test/gendirs.sh reports
#        ./refresh_grammars.sh main 12.3       # only these branches
#        ./refresh_grammars.sh --no-coldefs    # grammar and keyword table only

SCRIPT_PWD="$(cd "$(dirname "${0}")" && pwd)"
YACCDIR="$(cd "${SCRIPT_PWD}/../yacc" 2>/dev/null && pwd)"
RAW="https://raw.githubusercontent.com/MariaDB/server"
TESTDIR="/test"
MIN_SYM=100  # A real lex.h holds over 700. Anything near zero is the wrong file
COLDEFS=1

if [ -z "${YACCDIR}" ]; then
  echo "Assert: the yacc directory was not found next to ${SCRIPT_PWD}. Run this from the revgen directory of a mariadb-qa checkout"
  exit 1
fi

# fetch <branch> <path in repo> <target file>
fetch() {
  curl -sS --fail --location --max-time 120 --retry 2 --retry-delay 3 -o "${3}" "${RAW}/${1}/${2}"
}

# branch_for <version>: the branch that carries it. The newest version has no branch of its own
branch_for() {
  if fetch "${1}" VERSION /dev/null 2>/dev/null; then echo "${1}"; else echo main; fi
}

# coldefs <version>: build <version>_coldefs.txt from a running server of that version
coldefs() {
  local ver="${1}" vre base tmp suite i
  vre="${ver//./\.}"
  # An optimised build of this version, a plain one ahead of a sanitizer or Galera build
  base="$( (cd "${TESTDIR}" && ./gendirs.sh ALLALL) 2>/dev/null | grep -E "^E?MD[0-9]+-mariadb-${vre}\..*-opt\$" | tail -1 )"
  if [ -z "${base}" ]; then
    base="$( (cd "${TESTDIR}" && ./gendirs.sh ALLALL) 2>/dev/null | grep -E -- "-mariadb-${vre}\..*-opt\$" | tail -1 )"
  fi
  if [ -z "${base}" ]; then
    echo "${ver}: no optimised build of this version in ${TESTDIR}, so no ${ver}_coldefs.txt. Build one, or run ${SCRIPT_PWD}/harvest_coldefs.sh by hand"
    return 1
  fi

  # A basedir under /test is live, so the server runs from a copy
  tmp="/tmp/refresh_grammars_${ver}"
  rm -rf "${tmp}"
  echo "${ver}: copying ${base} to build the column definitions"
  if ! rsync -a --exclude=data --exclude=tmp --exclude=log "${TESTDIR}/${base}/" "${tmp}/"; then
    echo "${ver}: could not copy ${base}. No ${ver}_coldefs.txt"
    rm -rf "${tmp}"; return 1
  fi
  ( cd "${tmp}" && "${HOME}/st" >/dev/null 2>&1 && ./anc >/dev/null 2>&1 )
  for i in $(seq 30); do [ -S "${tmp}/socket.sock" ] && break; sleep 2; done
  if [ ! -S "${tmp}/socket.sock" ]; then
    echo "${ver}: the server of ${base} did not come up, so no ${ver}_coldefs.txt. Last lines of its error log:"
    tail -5 "${tmp}/log/master.err" 2>/dev/null
    ( cd "${tmp}" && ./kill >/dev/null 2>&1 ); rm -rf "${tmp}"; return 1
  fi

  # The test suite the definitions are read from. Older builds name that directory mysql-test
  for i in mariadb-test mysql-test; do [ -d "${tmp}/${i}" ] && { suite="${tmp}/${i}"; break; }; done
  if [ -n "${suite}" ]; then
    "${SCRIPT_PWD}/harvest_coldefs.sh" "${suite}" "${ver}" "${tmp}/socket.sock"
  else
    echo "${ver}: ${base} holds no test suite directory, so no ${ver}_coldefs.txt"
  fi
  ( cd "${tmp}" && ./kill >/dev/null 2>&1 ); rm -rf "${tmp}"
  [ -r "${YACCDIR}/${ver}_coldefs.txt" ]
}

# refresh <branch> [expected version]
refresh() {
  local br="${1}" want="${2:-}" tmp ver nsym
  tmp="$(mktemp -d)" || return 1
  trap 'rm -rf "${tmp}"' RETURN

  for f in VERSION sql/lex.h sql/sql_yacc.yy; do
    if ! fetch "${br}" "${f}" "${tmp}/$(basename "${f}")"; then
      echo "Assert: could not fetch ${f} of branch '${br}'. Check the branch name and the network"
      return 1
    fi
  done

  # The version number the files are named after
  ver="$(awk -F= '/^MYSQL_VERSION_MAJOR=/{maj=$2} /^MYSQL_VERSION_MINOR=/{min=$2} END{if (maj != "" && min != "") print maj"."min}' "${tmp}/VERSION")"
  if [ -z "${ver}" ]; then
    echo "Assert: the VERSION file of branch '${br}' carries no version number. Nothing installed"
    return 1
  fi
  if [ -n "${want}" ] && [ "${ver}" != "${want}" ]; then
    echo "Assert: no branch is named ${want} and branch '${br}' carries ${ver}, so the grammar of ${want} is not on GitHub. Nothing installed"
    return 1
  fi

  # The keyword table. Its SYM() entries are what revgen turns into keyword text
  nsym="$(grep -c 'SYM(' "${tmp}/lex.h")"
  if [ "${nsym}" -lt "${MIN_SYM}" ]; then
    echo "Assert: the lex.h of branch '${br}' holds ${nsym} SYM( entries, under the ${MIN_SYM} a real keyword table has. Nothing installed"
    return 1
  fi
  # The grammar. '%%' opens its rules section, which is the part revgen walks
  if ! grep -q '^%%' "${tmp}/sql_yacc.yy"; then
    echo "Assert: the sql_yacc.yy of branch '${br}' has no '%%' rules section. Nothing installed"
    return 1
  fi

  mv "${tmp}/sql_yacc.yy" "${YACCDIR}/${ver}_sql_yacc.yy" || return 1
  mv "${tmp}/lex.h" "${YACCDIR}/${ver}_lex.h" || return 1
  echo "${ver}: installed ${ver}_sql_yacc.yy and ${ver}_lex.h (${nsym} keywords) from branch ${br}"

  if [ ! -r "${YACCDIR}/${ver}_coldefs.txt" ]; then
    if [ "${COLDEFS}" -eq 1 ]; then
      coldefs "${ver}"
    else
      echo "${ver}: no ${ver}_coldefs.txt yet. Build it with: ${SCRIPT_PWD}/harvest_coldefs.sh <test suite dir> ${ver} <socket>"
    fi
  fi
  return 0
}

if [ "${1:-}" = "--no-coldefs" ]; then COLDEFS=0; shift; fi

RC=0
if [ -n "${1:-}" ]; then
  for br in "${@}"; do
    refresh "${br}" || RC=1
  done
else
  # The MariaDB versions this box has builds of. MySQL builds carry no mariadb- in their name
  VERSIONS="$( (cd "${TESTDIR}" && ./gendirs.sh ALLALL) 2>/dev/null | grep -oP 'mariadb-\K[0-9]+\.[0-9]+' | sort -uV )"
  if [ -z "${VERSIONS}" ]; then
    echo "Assert: ${TESTDIR}/gendirs.sh reported no MariaDB build, so there is no version list to work from. Name the branches instead, e.g. ${0} main 12.3"
    exit 1
  fi
  for v in ${VERSIONS}; do
    refresh "$(branch_for "${v}")" "${v}" || RC=1
  done
fi
exit ${RC}
