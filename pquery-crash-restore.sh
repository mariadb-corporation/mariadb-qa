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
    echo "Skipping trial ${TRIAL} as the trial directory was previously removed by other scripts"
    continue  # Skip trials already deleted by other scripts, for example crashes of known bugs by pquery-run.sh etc.
  fi
  echo "Processing trial ${TRIAL}"
  cd ${WORK_PWD}/${TRIAL}
  ./start_recovery
  for X in $(seq 0 60); do
    sleep 1
    if ${BASEDIR}/bin/mysqladmin -uroot -S${WORK_PWD}/${TRIAL}/socket.sock ping > /dev/null 2>&1; then
      echo "(${TRIAL}) Server crash recovery was successful"
      sleep 2
      ${BASEDIR}/bin/mysqladmin -uroot -S${WORK_PWD}/${TRIAL}/socket.sock shutdown > /dev/null 2>&1
      break
    fi
    if [ $X -eq 60 ]; then
      echo "(${TRIAL}) Server startup failed.."
      grep -1 "ERROR" ${WORK_PWD}/${TRIAL}/log/master.err | tail -n7
    fi
  done
done < <(grep -B5 -i 'Killed for crash.*testing' ./pquery-run.log | grep -io "log is stored at.*/log" | sed 's|/log||;s|.*/||')

