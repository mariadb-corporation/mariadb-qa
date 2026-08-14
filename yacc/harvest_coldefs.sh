#!/bin/bash
# Harvest column definitions from the test suite of one server version, for revgen.
#
# revgen needs real column types to build the tables its generated SQL works on. The test
# suite of the version under test holds thousands of CREATE TABLE statements written for
# that version, so the types, lengths, options and character sets in it are ones the
# server supports. This takes the column definitions out of them, one per line, without
# the column name. revgen puts the names back as c1 to c4.
#
# Usage: ./harvest_coldefs.sh <mysql-test directory> <version> [socket]
#   ./harvest_coldefs.sh /test/13.1/mysql-test 13.1
#   ./harvest_coldefs.sh /test/13.1/mysql-test 13.1 /test/CLAUDE1/socket.sock
#
# With a socket, each definition is offered to that server in a real CREATE TABLE and only
# the accepted ones are kept, so the result holds nothing the version refuses. Without one
# the result is unchecked, and revgen falls back per table to a plain shape where a build
# fails. Writes <version>_coldefs.txt next to this script.

if [ -z "${2}" ]; then
  echo "Usage: ${0} <mysql-test directory> <version> [socket]"
  exit 1
fi
TESTDIR="${1}"
VERSION="${2}"
SOCKET="${3}"
OUTDIR="$(cd "$(dirname "${0}")" && pwd)"
OUT="${OUTDIR}/${VERSION}_coldefs.txt"
if [ ! -d "${TESTDIR}" ]; then
  echo "Assert: '${TESTDIR}' is not a directory. Point it at the mysql-test directory of the source tree of ${VERSION}"
  exit 1
fi

if ! awk --version 2>/dev/null | head -1 | grep -q 'GNU Awk'; then
  echo "Assert: this needs GNU awk. Another awk matches the keywords in one case only and lets index definitions through"
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

echo "Reading ${TESTDIR}"
find "${TESTDIR}" -type f \( -name '*.test' -o -name '*.inc' \) -print0 |
  xargs -0 grep -hoiE "^ *create (or replace )?(temporary )?table (if not exists )?[a-z0-9_.\`]+ *\([^;]*\);" \
  > "${TMP}/creates.sql" 2>/dev/null
echo "CREATE TABLE statements: $(wc -l < "${TMP}/creates.sql")"

# One definition per line, name removed. The column list is split on the commas outside
# brackets and quotes, so DECIMAL(10,2) and ENUM('a','b') stay whole.
awk '
  BEGIN { IGNORECASE = 1 }
  function body(s,   d, q, i, c, out, n) {
    d = 0; q = ""; out = ""
    n = split(s, c, "")
    for (i = 1; i <= n; i++) {
      if (q != "") { out = out c[i]; if (c[i] == q) q = ""; continue }
      if (c[i] == "\"" || c[i] == "'"'"'" || c[i] == "`") { q = c[i]; out = out c[i]; continue }
      if (c[i] == "(") { d++; if (d == 1) { out = ""; continue } }
      else if (c[i] == ")") { d--; if (d == 0) return out }
      out = out c[i]
    }
    return ""
  }
  function emit(item,   t, rest) {
    gsub(/^[ \t]+|[ \t]+$/, "", item)
    if (item == "") return
    # A key, constraint or period is not a column
    if (item ~ /^(PRIMARY|UNIQUE|KEY|INDEX|FULLTEXT|SPATIAL|VECTOR|CONSTRAINT|CHECK|FOREIGN|PERIOD|ROW_START|ROW_END)\y/) return
    # Name, then the definition
    if (item !~ /^(`[^`]+`|[A-Za-z_][A-Za-z0-9_$]*)[ \t]/) return
    sub(/^(`[^`]+`|[A-Za-z_][A-Za-z0-9_$]*)[ \t]+/, "", item)
    # A generated column, a reference or a check names other columns
    if (item ~ /\y(AS|GENERATED|REFERENCES|CHECK|VIRTUAL|PERSISTENT|STORED)\y/) return
    # revgen adds the key and the auto-increment itself
    if (item ~ /\y(PRIMARY|UNIQUE|KEY|AUTO_INCREMENT|INVISIBLE|COMPRESSED)\y/) return
    # A collation the version may not have, and the character set that goes with it, are
    # covered by the generated SQL itself
    gsub(/[ \t]+(COLLATE|CHARACTER SET|CHARSET)[ \t]*=?[ \t]*('"'"'[A-Za-z0-9_]+'"'"'|`[A-Za-z0-9_]+`|[A-Za-z0-9_]+)/, "", item)
    # Keep a plain default, drop one that calls a function or names a column
    if (item ~ /\yDEFAULT\y/) {
      rest = item; sub(/^.*\yDEFAULT[ \t]+/, "", rest)
      if (rest !~ /^([0-9.+-]+|'"'"'[^'"'"']*'"'"'|"[^"]*"|NULL|TRUE|FALSE|CURRENT_TIMESTAMP|NOW\(\))([ \t]|$)/)
        sub(/[ \t]+DEFAULT\y.*$/, "", item)
    }
    gsub(/[ \t]+/, " ", item)
    gsub(/^[ \t]+|[ \t]+$/, "", item)
    if (item == "" || length(item) > 120) return
    if (item !~ /^[A-Za-z]/) return
    print item
  }
  {
    line = $0
    if (line !~ /\(/) next
    inner = body(line)
    if (inner == "") next
    d = 0; q = ""; cur = ""
    n = split(inner, c, "")
    for (i = 1; i <= n; i++) {
      ch = c[i]
      if (q != "") { cur = cur ch; if (ch == q) q = ""; continue }
      if (ch == "\"" || ch == "'"'"'" || ch == "`") { q = ch; cur = cur ch; continue }
      if (ch == "(") d++
      else if (ch == ")") d--
      if (ch == "," && d == 0) { emit(cur); cur = ""; continue }
      cur = cur ch
    }
    emit(cur)
  }
' "${TMP}/creates.sql" | sed 's/[ \t]*$//' | sort -uf > "${TMP}/pool.txt"
echo "Column definitions: $(wc -l < "${TMP}/pool.txt")"

if [ -z "${SOCKET}" ]; then
  cp "${TMP}/pool.txt" "${OUT}"
  echo "Written unchecked: ${OUT}"
  echo "Pass a server socket as the third argument to keep only the definitions that server accepts"
  exit 0
fi
if [ ! -S "${SOCKET}" ]; then
  echo "Assert: '${SOCKET}' is not a socket. Start a ${VERSION} server first, or leave the argument out"
  exit 1
fi
CLIENT="$(dirname "${SOCKET}")/bin/mariadb"
[ ! -x "${CLIENT}" ] && CLIENT="$(command -v mariadb || command -v mysql)"
if [ ! -x "${CLIENT}" ]; then
  echo "Assert: no mariadb client found next to the socket or on the path"
  exit 1
fi

# Each definition is offered to the server in the shape revgen builds. The line number of
# the error maps back to the definition, so one client run checks the whole pool.
echo "Checking against ${SOCKET}"
awk '{printf "CREATE OR REPLACE TABLE revgen_probe (c1 INT NOT NULL AUTO_INCREMENT PRIMARY KEY, c2 %s);\n", $0}' \
  "${TMP}/pool.txt" > "${TMP}/probe.sql"
"${CLIENT}" --no-defaults -uroot -S"${SOCKET}" --force test < "${TMP}/probe.sql" 2> "${TMP}/probe.err" > /dev/null
"${CLIENT}" --no-defaults -uroot -S"${SOCKET}" -e "DROP TABLE IF EXISTS test.revgen_probe" > /dev/null 2>&1
# The line number of the client, not the one the server repeats at the end of a syntax error
sed -n 's/^ERROR [0-9]* ([0-9A-Za-z]*) at line \([0-9]*\):.*/\1/p' "${TMP}/probe.err" | sort -un > "${TMP}/bad.txt"
awk 'NR==FNR{bad[$1];next} !(FNR in bad)' "${TMP}/bad.txt" "${TMP}/pool.txt" > "${OUT}"
echo "Refused by the server: $(wc -l < "${TMP}/bad.txt")"
echo "Written: ${OUT} ($(wc -l < "${OUT}") definitions)"
