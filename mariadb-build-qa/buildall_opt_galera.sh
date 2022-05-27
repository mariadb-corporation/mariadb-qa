#!/bin/bash
# Created by Roel Van de Paar, MariaDB
# Modified by Ramesh Sivaraman, MariaDB

# This script can likely be sourced (. ./buildall_opt.sh) to be able to use job control ('jobs', 'fg' etc)

if [ ! -r ./terminate_ds_memory.sh ]; then
  echo './terminate_ds_memory.sh missing!'
  exit 1
else
  ./terminate_ds_memory.sh  # Terminate ~/ds and ~/memory if running (with 3 sec delay)
fi

DIR=${PWD}
rm -Rf 10.1_opt 10.2_opt 10.3_opt 10.4_opt 10.5_opt 10.6_opt 10.7_opt 10.8_opt 10.9_opt 10.10_opt
#cd ${DIR}/10.1 && ~/mariadb-qa/build_mdpsms_opt_galera.sh &
cd ${DIR}/10.2 && ~/mariadb-qa/build_mdpsms_opt_galera.sh &
cd ${DIR}/10.3 && ~/mariadb-qa/build_mdpsms_opt_galera.sh &
cd ${DIR}/10.4 && ~/mariadb-qa/build_mdpsms_opt_galera.sh &
cd ${DIR}/10.5 && ~/mariadb-qa/build_mdpsms_opt_galera.sh &
cd ${DIR}/10.6 && ~/mariadb-qa/build_mdpsms_opt_galera.sh &
cd ${DIR}/10.7 && ~/mariadb-qa/build_mdpsms_opt_galera.sh &
cd ${DIR}/10.8 && ~/mariadb-qa/build_mdpsms_opt_galera.sh &
cd ${DIR}/10.9 && ~/mariadb-qa/build_mdpsms_opt_galera.sh &
cd ${DIR}/10.10 && ~/mariadb-qa/build_mdpsms_opt_galera.sh &
