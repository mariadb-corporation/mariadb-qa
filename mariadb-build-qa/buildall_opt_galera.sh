#!/bin/bash
# Created by Roel Van de Paar, MariaDB
# Modified by Ramesh Sivaraman, MariaDB

# This script can likely be sourced (. ./buildall_opt.sh) to be able to use job control ('jobs', 'fg' etc)

# No longer needed
#if [ ! -r ./terminate_ds_memory.sh ]; then
#  echo './terminate_ds_memory.sh missing!'
#  exit 1
#else
#  ./terminate_ds_memory.sh  # Terminate ~/ds and ~/memory if running (with 3 sec delay)
#fi

# Restart inside a screen if this terminal session isn't one already
if [ "${STY}" == "" ]; then
  echo "Not a screen, restarting myself inside a screen"
  screen -admS "buildall_opt_gal" bash -c "$0;bash"
  sleep 1
  screen -d -r "buildall_opt_gal"
  return 2> /dev/null; exit 0
fi

DIR=${PWD}
rm -Rf 10.3_opt 10.4_opt 10.5_opt 10.6_opt 10.7_opt 10.8_opt 10.9_opt 10.10_opt galera_3x_opt galera_4x_opt
#Build Galera library
cp -r ${DIR}/galera_3x ${DIR}/galera_3x_opt
cd ${DIR}/galera_3x_opt && cmake . | tee /tmp/psms_opt_galera3x_build_${RANDOMD} && make | tee -a /tmp/psms_opt_galera3x_build_${RANDOMD} &
cp -r ${DIR}/galera_4x ${DIR}/galera_4x_opt
cd ${DIR}/galera_4x_opt && cmake . | tee /tmp/psms_opt_galera4x_build_${RANDOMD} && make | tee -a /tmp/psms_opt_galera4x_build_${RANDOMD} &

sleep 10
#cd ${DIR}/10.1 && ~/mariadb-qa/build_mdpsms_opt_galera.sh &
#cd ${DIR}/10.2 && ~/mariadb-qa/build_mdpsms_opt_galera.sh &
cd ${DIR}/10.3 && ~/mariadb-qa/build_mdpsms_opt_galera.sh &
cd ${DIR}/10.4 && ~/mariadb-qa/build_mdpsms_opt_galera.sh &
cd ${DIR}/10.5 && ~/mariadb-qa/build_mdpsms_opt_galera.sh &
cd ${DIR}/10.6 && ~/mariadb-qa/build_mdpsms_opt_galera.sh &
#cd ${DIR}/10.7 && ~/mariadb-qa/build_mdpsms_opt_galera.sh &
#cd ${DIR}/10.8 && ~/mariadb-qa/build_mdpsms_opt_galera.sh &
#cd ${DIR}/10.9 && ~/mariadb-qa/build_mdpsms_opt_galera.sh &
#cd ${DIR}/10.10 && ~/mariadb-qa/build_mdpsms_opt_galera.sh &
cd ${DIR}/10.11 && ~/mariadb-qa/build_mdpsms_opt_galera.sh &
cd ${DIR}/11.0 && ~/mariadb-qa/build_mdpsms_opt_galera.sh &
cd ${DIR}/11.1 && ~/mariadb-qa/build_mdpsms_opt_galera.sh &
#cd ${DIR}/11.2 && ~/mariadb-qa/build_mdpsms_opt_galera.sh &
