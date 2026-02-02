#!/bin/bash

# Internal variables
SCRIPT_PWD=$(dirname $(readlink -f "${0}"))
WORKD_PWD=$PWD

# Check if this is a MariaDB Galera Cluster run
MDG=0
if grep -qi 'MDG Mode:.*TRUE' ./pquery-run.log 2>/dev/null; then
  MDG=1
fi

#Checking TRIAL number
if [ "" == "$1" ]; then
  echo "This script expects one parameter: the trial number to extract failing queries"
  echo "Please execute this script from within pquery's working/run directory"
  exit 1
else
  TRIAL=$1
  NODE=$2
fi

failing_queries_core(){
  rm -Rf ${WORKD_PWD}/${TRIAL}/gdb_PARSE.txt
  cat ${SCRIPT_PWD}/extract_query.gdb | sed "s|file /tmp/gdb_PARSE.txt|file ${WORKD_PWD}/${TRIAL}/gdb_PARSE.txt|" > ${WORKD_PWD}/${TRIAL}/extract_query.gdb
  # For debugging purposes, remove ">/dev/null" on the next line and observe output
  gdb ${BIN} ${CORE} >/dev/null 2>&1 < ${WORKD_PWD}/${TRIAL}/extract_query.gdb
  # The double quotes ; ; are to prevent parsing mishaps where the query is invalid and has opened a multi-line situation
  grep '^\$' ${WORKD_PWD}/${TRIAL}/gdb_PARSE.txt | sed 's/^[\$0-9a-fx =]*"//;s/"$//;s/[ \t]*$//;s|\\"|"|g;s/$/; ;/' | grep -v '^\$' >> ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing
}

failing_queries_error_log(){
  # The double quotes ; ; are to prevent parsing mishaps where the query is invalid and has opened a multi-line situation
  FAILING_QUERY_ERR=$(grep "Query ([x0-9a-fA-F]*):" $ERRLOG | sed 's|^Query ([x0-9a-fA-F]*): ||;s|$|; ;|')
  if [ "$(echo ${FAILING_QUERY_ERR} | sed 's|: [0-9]\+|: 0|')" != "Connection ID (thread ID): 0; ;" ]; then  # http://bugs.mysql.com/bug.php?id=81651
    echo "${FAILING_QUERY_ERR}" >> ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing
  fi
}

failing_queries_pquery_trace(){
  COUNT_PQ_LOGS="$(ls --color=never ${WORKD_PWD}/${TRIAL}/default.node.tld_thread-*.sql 2>/dev/null | wc -l)"
  if [ "${COUNT_PQ_LOGS}" -gt 0 ]; then
    grep --binary-files=text -i 'lost connection to server during query' ${WORKD_PWD}/${TRIAL}/default.node.tld_thread-*.sql | grep --binary-files=text -vE '^/data/|^/test/' >>${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing 2>/dev/null
  fi
}

# Ideally, we would have a failing_queries_cli_trace as well, to implement when used

rm -Rf ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing
if [[ $MDG -eq 1 ]]; then
  if [[ -z $NODE ]]; then
    ERRLOG="${WORKD_PWD}/${TRIAL}/node$2/node$2.err"
  else
    ERRLOG="${WORKD_PWD}/${TRIAL}/log/master.err"
  fi
else
  ERRLOG="${WORKD_PWD}/${TRIAL}/log/master.err"
fi
if [ -r ${WORKD_PWD}/mysqld/mysqld ]; then BIN="${WORKD_PWD}/mysqld/mysqld"
elif [ -r ${WORKD_PWD}/mysqld/mariadbd ]; then BIN="${WORKD_PWD}/mysqld/mariadbd"
fi
if [ ! -r $BIN ]; then
  echo "Assert: mysqld/mariadbd could not be found in the ${WORKD_PWD}/mysqld/ directory"
  exit 1
fi
CORE="$(ls -1 ${WORKD_PWD}/${TRIAL}/data/*core* 2>&1 | head -n1 | grep -vE 'No such file|Not a directory')"
if [ ! -z "${CORE}" -a -r "${CORE}" -a -f "${CORE}" ]; then
  failing_queries_core
fi
failing_queries_error_log
failing_queries_pquery_trace
echo "SELECT 1;" >> ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing  # Often helps to highlight a crashing instance
echo "SELECT SLEEP(2);" >> ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing  # Regularly helps to trigger a delayed crash
echo "$(cat ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing)" >> ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing  # 2x
echo "$(cat ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing)" >> ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing  # 3x
echo "SHUTDOWN;" >> ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing  # Helps to trigger delayed or shutdown-triggered crashes
if [ "${2}" != "1" ]; then  # Automation in pquery-prep-red does not need this output
  echo "Saved failing queries 3x in ${WORKD_PWD}/${TRIAL}/${TRIAL}.sql.failing - inc. some additional helpful queries"
fi
