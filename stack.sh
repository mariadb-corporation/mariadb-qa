#!/bin/bash
set +H  # Disables history substitution and avoids  -bash: !: event not found  like errors
SCRIPT_PWD=$(dirname $(readlink -f "${0}"))
RANDOM=$(date +%s%N | cut -b10-19 | sed 's|^[0]\+||')  # Random entropy init
RANDF=$(echo $RANDOM$RANDOM$RANDOM$RANDOM | sed 's|.\(..........\).*|\1|')  # Random 10 digits filenr

BIN=
if [ -r ./bin/mariadbd ]; then BIN='./bin/mariadbd'; 
elif [ -r ./bin/mysqld ]; then BIN='./bin/mysqld';
elif [ -r ../mysqld/mariadbd ]; then BIN='../mysqld/mariadbd'; 
elif [ -r ../mysqld/mysqld ]; then BIN='../mysqld/mysqld'; 
elif [ -r ../bin/mariadbd ]; then BIN='../bin/mariadbd';  # For MTR
elif [ -r ../bin/mysqld ]; then BIN='../bin/mysqld';  # For MTR
elif [ -r ../../bin/mariadbd ]; then BIN='../../bin/mariadbd';
elif [ -r ../../bin/mysqld ]; then BIN='../../bin/mysqld';
elif [ -r ./log/master.err ]; then
  POTENTIAL_MYSQLD="$(grep "ready for connections" ./log/master.err | sed 's|: .*||;s|^.* ||' | head -n1)"
  if [ -x ${POTENTIAL_MYSQLD} ]; then BIN="${POTENTIAL_MYSQLD}"; fi
elif [ -r ./log/slave.err ]; then
  POTENTIAL_MYSQLD="$(grep "ready for connections" ./log/slave.err | sed 's|: .*||;s|^.* ||' | head -n1)"
  if [ -x ${POTENTIAL_MYSQLD} ]; then BIN="${POTENTIAL_MYSQLD}"; fi
elif [ -r ./node1/node1.err ]; then
  POTENTIAL_MYSQLD="$(grep "ready for connections" ./node1/node1.err | sed 's|: .*||;s|^.* ||' | head -n1)"
  if [ -x ${POTENTIAL_MYSQLD} ]; then BIN="${POTENTIAL_MYSQLD}"; fi
elif [ -r ./node2/node2.err ]; then
  POTENTIAL_MYSQLD="$(grep "ready for connections" ./node2/node2.err | sed 's|: .*||;s|^.* ||' | head -n1)"
  if [ -x ${POTENTIAL_MYSQLD} ]; then BIN="${POTENTIAL_MYSQLD}"; fi
elif [ -r ./node3/node3.err ]; then
  POTENTIAL_MYSQLD="$(grep "ready for connections" ./node3/node3.err | sed 's|: .*||;s|^.* ||' | head -n1)"
  if [ -x ${POTENTIAL_MYSQLD} ]; then BIN="${POTENTIAL_MYSQLD}"; fi
else echo "Assert: mariadbd nor mysqld found!"; exit 1; fi

if [ -r "${SCRIPT_PWD}/source_code_rev.sh" ]; then
  SOURCE_CODE_REV="$(${SCRIPT_PWD}/source_code_rev.sh)"
elif [ -r "${HOME}/mariadb-qa/source_code_rev.sh" ]; then
  SOURCE_CODE_REV="$(${HOME}/mariadb-qa/source_code_rev.sh)"
else
  SOURCE_CODE_REV='unknown'
fi

# Partial code duplication with homedir_scripts/myver
SVR=''  # ES,CS,MS
if [ "$(echo "${PWD}" | grep -o EMD)" == "EMD" -o "$(grep --binary-files=text "BASEDIR" ./start 2>/dev/null | grep -o 'EMD' | head -n1)" == "EMD" ]; then
  SERVER_VERSION="$(${BIN}  --version | grep -om1 --binary-files=text '[0-9\.]\+-[0-9]-MariaDB' | sed 's|-MariaDB||')"
  SVR='ES'
else
  SERVER_VERSION="$(${BIN} --version | grep -om1 --binary-files=text '[0-9\.]\+-MariaDB' | sed 's|-MariaDB||')"
  SVR='CS'
fi
if [ -z "${SERVER_VERSION}" ]; then  # Likely MS
  SERVER_VERSION="MySQL $(pwd | grep -o 'mysql-[\.0-9]\+' | sed 's|mysql-||')"
  SVR='MS'
fi

BUILD_TYPE=
LAST_THREE="$(echo "${PWD}" | sed 's|.*\(...\)$|\1|')"
# Partial code duplication with homedir_scripts/myver
MDG=0
if [ ! -z "$(ls --color=never ./node*/node*.err 2>/dev/null)" ]; then
  MDG=1
fi
if [ "${LAST_THREE}" != "dbg" -a "${LAST_THREE}" != "opt" ]; then  # in-trial ./stack call
  if [ "${MDG}" -eq 1 ]; then
    LAST_THREE="$(grep --binary-files=text -Eoh "\-dbg|\-opt" ./node*/node*.err 2>/dev/null | head -n1 | sed 's|\-||')"
  else
    LAST_THREE="$(grep --binary-files=text -Eoh "\-dbg|\-opt" ./log/master.err ./var/log/mysqld.*.err 2>/dev/null | head -n1 | sed 's|\-||')"
  fi
fi
if [ "${LAST_THREE}" != "dbg" -a "${LAST_THREE}" != "opt" ]; then  # in-trial ./stack call for ES
  LAST_THREE="$(grep --binary-files=text -oh "BASEDIR.*\-[do][bp][gt]" start 2>/dev/null | grep --binary-files=text -Eoh "\-dbg|\-opt" | head -n1 | sed 's|\-||')"
fi
if [ "${LAST_THREE}" == "opt" ]; then BUILD_TYPE=" (Optimized)"; fi
if [ "${LAST_THREE}" == "dbg" ]; then BUILD_TYPE=" (Debug)"; fi

if [ "${MDG}" -eq 1 ]; then
  CORE_COUNT=$(ls --color=never node*/*core* 2>/dev/null | wc -l)
else
  CORE_COUNT=$(ls --color=never data*/*core* var/log/*/*/data/*core* var/*/log/*/*/data/*core* var/mysqld*/data/*core* 2>/dev/null | wc -l)
fi
if [ ${CORE_COUNT} -eq 0 ]; then
  echo "INFO: no cores found at data*/*core* nor at node*/*core*"
  exit 1
elif [ ${CORE_COUNT} -gt 1 ]; then
  echo "Assert: too many (${CORE_COUNT}) cores found at data*/*core* and/or node*/*core*"
  exit 1
fi

if [ "${MDG}" -eq 1 ]; then
  ERROR_LOG=$(ls --color=never node*/node*.err 2>/dev/null | head -n1)  # This is not perfect in case node2 or node3 crashes TODO
else
  ERROR_LOG=$(ls --color=never log/master.err log/slave.err var/log/mysqld.2.err var/log/mysqld.1.err 2>/dev/null | sort -R | head -n1)  # sort -R: Slave log first, if present (as often the slave asserts). TODO: this is not perfect either, like MDG
fi
if [ ! -z "${ERROR_LOG}" ]; then
  #echo "----${ERROR_LOG} "  # Debug
  ASSERT="$(grep --binary-files=text -m1 'Assertion.*failed.$' ${ERROR_LOG} | head -n1)"
  #echo "----${ASSERT}"  # Debug
  if [ -z "${ASSERT}" ]; then
    ASSERT="$(grep --binary-files=text -m1 'Failing assertion:' ${ERROR_LOG} | head -n1)"
  fi
  if [ ! -z "${ASSERT}" ]; then
    echo -e "{noformat:title=${SVR} ${SERVER_VERSION} ${SOURCE_CODE_REV}${BUILD_TYPE}}\n${ASSERT}\n{noformat}\n"
  fi
fi

# Note that no 'head -n1' or similar is needed here, as the script will terminate if >1 core is found (ref code above)
LATEST_CORE=
if [ "${MDG}" -eq 1 ]; then
  LATEST_CORE="$(ls -t --color=never node*/*core* 2>/dev/null)"
else
  LATEST_CORE="$(ls -t --color=never data*/*core* var/log/*/*/data/*core* var/*/log/*/*/data/*core* var/mysqld*/data/*core* 2>/dev/null)"
fi

gdb -q ${BIN} ${LATEST_CORE} >/tmp/${RANDF}.gdba 2>&1 << EOF
 set pagination off
 set print pretty on
 set print frame-arguments all
 bt
 quit
EOF

# Update March/April 24: a system update now renders stacks as
#10 0x0000562e73a837b4 in mysql_admin_table (thd=thd@entry=0x152110000d58,
#    tables=tables@entry=0x152110016ac0,
#    ...
#    at /test/preview-11.5-preview_dbg/sql/sql_admin.cc:1116
# The awk below fixes this by moving everything back into single lines
# Also changed in bug_report.sh

if [ -r /tmp/${RANDF}.gdba ]; then
  echo "{noformat:title=${SVR} ${SERVER_VERSION} ${SOURCE_CODE_REV}${BUILD_TYPE}}"
  grep --binary-files=text -A999 'Core was generated by' /tmp/${RANDF}.gdba | grep --binary-files=text -v 'No such file or directory' | sed 's|(gdb) (gdb) |(gdb) bt\n|' | sed 's|(gdb) (gdb) ||' | awk '{ if(/^    /) printf("%s", substr($0, 5)); else if(NR > 1) printf("\n%s", $0); else printf("%s", $0); } END { printf("\n"); }' | grep --binary-files=text -v '^(gdb)[ \t]*$' | grep --binary-files=text -vi 'Downloading source file'
  rm -f /tmp/${RANDF}.gdba
else
  echo "Assert: /tmp/${RANDF}.gdba not found after gdb was called"
  exit 1
fi
echo '{noformat}'
