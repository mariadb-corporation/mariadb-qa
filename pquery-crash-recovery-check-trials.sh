#!/bin/bash
# Created by Ramesh Sivaraman, LLC
# Updated by Roel Van de Paar, MariaDB
# This script will check crash recovery of all pquery trials which were killed for crash recovery testing in a given WORKDIR

BASEDIR=$(grep 'Basedir:' ./pquery-run.log | sed 's|^.*Basedir[: \t]*||;;s/|.*$//' | tr -d '[[:space:]]')
WORK_PWD=$PWD

if [ ! -r ./pquery-run.log -o -z "$(grep -i -m 1 'Killed for crash.*testing' ./pquery-run.log 2>/dev/null)" ]; then
  echo "Assert: ./pquery-run.log not found. Please start this script from within a given WORKDIR (usually /data/some_6_digit_nr/), where the pquery run was specifically setup for crash recovery testing ("
  exit 1
elif [ ! -d "${BASEDIR}" ]; then
  echo "Assert: Basedir '${BASEDIR}' does not exist"
  exit 1
fi

while read TRIAL ; do
  cd ${WORK_PWD}
  if [ ! -r ${TRIAL}/start_recovery ]; then
    continue  # Skip trials already deleted by other scripts, for example crashes of known bugs by pquery-run.sh etc.
  fi
  echo -n "Processing trial $(pwd | sed 's|.*/||')/${TRIAL} [CR]... "
  cd ${WORK_PWD}/${TRIAL}
  ./kill 2>/dev/null
  if [ -d ${WORK_PWD}/${TRIAL}/data.original ]; then
    # This script was previously run against this trial: do cleanup first
    rm -Rf ${WORK_PWD}/${TRIAL}/data
    cp -r ${WORK_PWD}/${TRIAL}/data.original ${WORK_PWD}/${TRIAL}/data
  else  # Note that this is duplicated (but safe) in pquery-run.sh
    cp -r ${WORK_PWD}/${TRIAL}/data ${WORK_PWD}/${TRIAL}/data.original
  fi
  if [ -d ${WORK_PWD}/${TRIAL}/tmp.original ]; then
    # This script was previously run against this trial: do cleanup first
    rm -Rf ${WORK_PWD}/${TRIAL}/tmp
    cp -r ${WORK_PWD}/${TRIAL}/tmp.original ${WORK_PWD}/${TRIAL}/tmp
  else  # Note that this is duplicated (but safe) in pquery-run.sh
    cp -r ${WORK_PWD}/${TRIAL}/tmp ${WORK_PWD}/${TRIAL}/tmp.original
  fi
  ./start_recovery
  for X in $(seq 0 60); do
    sleep 1
    ADM="${BASEDIR}/bin/mysqladmin"
    if [ -r "${BASEDIR}/bin/mariadb-admin" ]; then ADM="${BASEDIR}/bin/mariadb-admin"; fi
    if ${ADM} -uroot -S${WORK_PWD}/${TRIAL}/socket.sock ping > /dev/null 2>&1; then
      echo "Server crash recovery was successful, now testing tables"
      sleep 1
      echo -n "Processing trial $(pwd | sed 's|.*/||')/${TRIAL} [TC]... "
      CHK="${BASEDIR}/bin/mysqlcheck"
      if [ -r "${BASEDIR}/bin/mariadb-check" ]; then CHK="${BASEDIR}/bin/mariadb-check"; fi
      OUTPUT="$(${CHK} -uroot -S${WORK_PWD}/${TRIAL}/socket.sock -uroot -Acfe 2>&1 | grep --binary-files=text "^[Ee]rror[ \t]\+:")"
      CHK=
      if [ -z "${OUTPUT}" ]; then
        if [ ! -z "$(ls ${WORK_PWD}/${TRIAL}/data*/*core* 2>/dev/null)" ]; then
          echo "Server table check was successful, however *** a core file was discovered in the trial data directory"
          OUTPUT="core_found"
        elif [ ! -z "$(grep --binary-files=text -i 'assert' ${WORK_PWD}/${TRIAL}/log/master.err | grep --binary-files=text -vE 'debug_assert_on' 2>/dev/null)" ]; then
          echo "Server table check was successful, however *** an assert was discovered in the trial's error log"
          OUTPUT="asset_found"
        else
          echo "Server table check was successful, shutting down instance and removing trial"
        fi
      else
        echo "*** Server table check failed, report below *** (instance is being shutdown)"
        echo "${OUTPUT}"
        echo "Use:  cd ${TRIAL}; ./kill 2>/dev/null; rm -Rf ./data; cp -r data.original data; ./start; sleep 2; ./cl"
        echo "      USE test; CHECK TABLE t1 EXTENDED;  # Change database and table names as necessary"
      fi 
      ${ADM} -uroot -S${WORK_PWD}/${TRIAL}/socket.sock shutdown > /dev/null 2>&1
      ADM=
      if [ -z "${OUTPUT}" ]; then 
        if [ -r ${WORK_PWD}/${TRIAL}/cl ]; then  # Check before delete
          rm -Rf ${WORK_PWD}/${TRIAL}
        fi
      fi
      OUTPUT=
      break
    fi
    if [ $X -eq 60 ]; then
      echo "*** Server startup/crash recovery failed *** (instance not running)"
      grep --binary-files=text -i 'ERROR' ${WORK_PWD}/${TRIAL}/log/master.err | tail -n7
      grep --binary-files=text -i 'assert' ${WORK_PWD}/${TRIAL}/log/master.err | grep --binary-files=text -vE 'debug_assert_on' | tail -n7
      echo "Use:  cd ${TRIAL}; ./kill 2>/dev/null; rm -Rf data tmp; cp -r data.original data; cp -r tmp.original tmp; ./start_recovery; sleep 2; ./cl; vl"
      break
    fi
  done
done < <(grep -B5 -i 'Killed for crash.*testing' ./pquery-run.log | grep --binary-files=text -ioE "log is stored at.*/log|log stored in .*/pquery.log" | sed 's|/log||;s|/pquery.log||;s|.*/||')  # First text is from multi-threaded runs, second from single threaded runs TODO: cleanup later (requires non-backwards-compatible fix)
