#!/bin/bash
set -eo pipefail
shopt -s nullglob
set +H

#m="/test/MD060321-mariadb-10.6.0-linux-x86_64-dbg/bin/mariadb -uroot -S/test/MD060321-mariadb-10.6.0-linux-x86_64-dbg/socket.sock --force --binary-mode test"
m="/test/MD060321-mariadb-10.6.0-linux-x86_64-dbg/bin/mariadb -uroot -S/test/MD060321-mariadb-10.6.0-linux-x86_64-dbg/socket.sock --binary-mode test"

$m -e "SET GLOBAL SQL_MODE = REPLACE(@@SQL_MODE, 'NO_BACKSLASH_ESCAPES', '');"
PREV_PWD=''
FIRST_RUN=1
# Random entropy init
RANDOM=$(date +%s%N | cut -b10-19)
while :; do
	#REAL_PASSWORD=$(pwgen   --numerals   --capitalize  --symbols --secure 32 1)
	read -r -d '' -N 200 REAL_PASSWORD < /dev/urandom
  #echo "REAL_PASSWORD=${REAL_PASSWORD}"; sync
  if [ -r pwd_done.txt ]; then
    mv pwd_done.txt pwd_done.prev
  fi
  echo "|||||${REAL_PASSWORD}|||||" > pwd_done.txt; sync
	# SQL escaping \
	p=${REAL_PASSWORD//\\/\\\\}
	# SQL escaping '
	MARIADB_ROOT_PASSWORD=${p//\'/\\\'}
  #echo "MARIADB_ROOT_PASSWORD=${MARIADB_ROOT_PASSWORD}"; sync
  if [ ${FIRST_RUN} -eq 1 -a -z "${PREV_PWD}" ]; then
    $m <<- EOSQL || exit 1
     SET PASSWORD FOR 'root'@'localhost' = PASSWORD('${MARIADB_ROOT_PASSWORD}');
EOSQL
  else
    $m -p"${PREV_PWD}" <<- EOSQL || exit 1
     SET PASSWORD FOR 'root'@'localhost' = PASSWORD('${MARIADB_ROOT_PASSWORD}');
EOSQL
  fi
  FIRST_RUN=0
	#echo "pass=${MARIADB_ROOT_PASSWORD}"; sync
  $m -p"${REAL_PASSWORD}" -Be 'SELECT 1;' > /dev/null
  PREV_PWD="${REAL_PASSWORD}"
done
