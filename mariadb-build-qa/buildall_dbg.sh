#!/bin/bash
# Created by Roel Van de Paar, MariaDB
# This script can likely be sourced (. ./buildall_dbg.sh) to be able to use job control ('jobs', 'fg' etc)

if [ ! -r ./terminate_ds_memory.sh ]; then
  echo './terminate_ds_memory.sh missing!'
  exit 1
else
  ./terminate_ds_memory.sh  # Terminate ~/ds and ~/memory if running (with 3 sec delay)
fi

DIR=${PWD}
rm -Rf 10.1_dbg 10.2_dbg 10.3_dbg 10.4_dbg 10.5_dbg 10.6_dbg 10.7_dbg 10.8_dbg 10.9_dbg 10.10_dbg
#cd ${DIR}/10.1 && ~/mariadb-qa/build_mdpsms_dbg.sh &
#cd ${DIR}/10.2 && ~/mariadb-qa/build_mdpsms_dbg.sh &
cd ${DIR}/10.3 && ~/mariadb-qa/build_mdpsms_dbg.sh &
cd ${DIR}/10.4 && ~/mariadb-qa/build_mdpsms_dbg.sh &
cd ${DIR}/10.5 && ~/mariadb-qa/build_mdpsms_dbg.sh &
cd ${DIR}/10.6 && ~/mariadb-qa/build_mdpsms_dbg.sh &
cd ${DIR}/10.7 && ~/mariadb-qa/build_mdpsms_dbg.sh &
cd ${DIR}/10.8 && ~/mariadb-qa/build_mdpsms_dbg.sh &
cd ${DIR}/10.9 && ~/mariadb-qa/build_mdpsms_dbg.sh &
cd ${DIR}/10.10 && ~/mariadb-qa/build_mdpsms_dbg.sh &
cd ${DIR}/10.11 && ~/mariadb-qa/build_mdpsms_dbg.sh &

echo "All processes started as background threads... Output will commence soon."
