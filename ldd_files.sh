#!/bin/bash
# Created by Roel Van de Paar, Percona LLC

# This script quickly gathers all ldd dep files for mysqld/mariadbd/xtrabackup in the current directory into the current directory

if [ ! -r ./mysqld -a ! -r ./mariadbd -a ! -r ./xtrabackup ]; then
  echo "Assert: ./mysqld nor ./mariadbd nor ./xtrabackup exist?"
  exit 1
fi

SERVER=0
if [ -r ./mariadbd ]; then
  BIN='mariadbd'
  SERVER=1
elif [ -r ./mysqld ]; then
  BIN='mysqld'
  SERVER=1
fi
if [ "${SERVER}" -eq 1 ]; then
  ldd ${BIN} | sed 's|(.*||;s|=>[ \t]*$||;s|.*=>||;s|[ \t\n\r]*||;s|[^0-9a-zA-Z]$||' | grep -v "^[a-zA-Z]" | xargs -I_ cp _ .

  CORE=`ls -1 *core* 2>&1 | head -n1 | grep -v "No such file"`
  if [ -f "$CORE" -a "" != "${CORE}" ]; then
    mkdir -p lib64
    gdb ./${BIN} $CORE -ex "info sharedlibrary" -ex "quit" 2>&1 | grep "0x0" | grep -vE "lib.mysql.plugin|^#0 " | grep -vE '/lib/' | sed 's|.*/lib64|/lib64|' | xargs -I_ cp _ ./lib64/  # Both /lib/ and /lib/x86_64-linux-gnu/ are excluded here
    gdb ./${BIN} $CORE -ex "info sharedlibrary" -ex "quit" 2>&1 | grep "0x0" | grep -vE "lib.mysql.plugin|^#0 " | grep '/lib/x86_64-linux-gnu/' | sed 's|.*/lib/x86_64-linux-gnu/|/lib/x86_64-linux-gnu/|' | xargs -I_ cp -n _ .
    gdb ./${BIN} $CORE -ex "info sharedlibrary" -ex "quit" 2>&1 | grep "0x0" | grep -vE "lib.mysql.plugin|^#0 " | grep '/lib/' | grep -v 'x86_64-linux-gnu/' | sed 's|.*/lib/|/lib/|' | xargs -I_ cp -n _ .
  fi
fi
SERVER=
BIN=

if [ -r ./xtrabackup ]; then
  ldd xtrabackup | sed 's|(.*||;s|=>[ \t]*$||;s|.*=>||;s|[ \t\n\r]*||;s|[^0-9a-zA-Z]$||' | grep -v "^[a-zA-Z]" | xargs -I_ cp _ .
fi
