#!/bin/bash
# Created by Roel Van de Paar, MariaDB
# This script can likely be sourced (. ./buildall_opt.sh) to be able to use job control ('jobs', 'fg' etc)

# No longer deemed necessary: ref terminate_ds_memory.sh
#if [ ! -r ./terminate_ds_memory.sh ]; then
#  echo './terminate_ds_memory.sh missing!'
#  exit 1
#else
#  ./terminate_ds_memory.sh  # Terminate ~/ds and ~/memory if running (with 3 sec delay)
#fi

# Restart inside a screen if this terminal session isn't one already
if [ "${STY}" == "" ]; then
  echo "Not a screen, restarting myself inside a screen"
  screen -admS "buildall_opt" bash -c "$0;bash"
  sleep 1
  screen -d -r "buildall_opt"
  return 2> /dev/null; exit 0
fi

DIR=${PWD}
rm -Rf 10.5_opt 10.6_opt 10.7_opt 10.8_opt 10.9_opt 10.10_opt 11.0_opt 11.1_opt 11.2_opt 11.3_opt 11.4_opt 11.5_opt
#cd ${DIR}/10.1 && ~/mariadb-qa/build_mdpsms_opt.sh &
#cd ${DIR}/10.2 && ~/mariadb-qa/build_mdpsms_opt.sh &
#cd ${DIR}/10.3 && ~/mariadb-qa/build_mdpsms_opt.sh &
#cd ${DIR}/10.4 && ~/mariadb-qa/build_mdpsms_opt.sh &
cd ${DIR}/10.5 && ~/mariadb-qa/build_mdpsms_opt.sh &
cd ${DIR}/10.6 && ~/mariadb-qa/build_mdpsms_opt.sh &
#cd ${DIR}/10.7 && ~/mariadb-qa/build_mdpsms_opt.sh &
#cd ${DIR}/10.8 && ~/mariadb-qa/build_mdpsms_opt.sh &
#cd ${DIR}/10.9 && ~/mariadb-qa/build_mdpsms_opt.sh &
#cd ${DIR}/10.10 && ~/mariadb-qa/build_mdpsms_opt.sh &
cd ${DIR}/10.11 && ~/mariadb-qa/build_mdpsms_opt.sh &
cd ${DIR}/11.0 && ~/mariadb-qa/build_mdpsms_opt.sh &
cd ${DIR}/11.1 && ~/mariadb-qa/build_mdpsms_opt.sh &
cd ${DIR}/11.2 && ~/mariadb-qa/build_mdpsms_opt.sh &
cd ${DIR}/11.3 && ~/mariadb-qa/build_mdpsms_opt.sh &
cd ${DIR}/11.4 && ~/mariadb-qa/build_mdpsms_opt.sh &
cd ${DIR}/11.5 && ~/mariadb-qa/build_mdpsms_opt.sh &

echo "All processes started as background threads... Output will commence soon."
