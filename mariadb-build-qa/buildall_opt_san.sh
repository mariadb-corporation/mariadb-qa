#!/bin/bash
# Created by Roel Van de Paar, MariaDB

if [ ! -r ./terminate_ds_memory.sh ]; then
  echo './terminate_ds_memory.sh missing!'
  exit 1
else
  ./terminate_ds_memory.sh  # Terminate ~/ds and ~/memory if running (with 3 sec delay)
fi

if [ ! -r ~/mariadb-qa/build_mdpsms_opt_san.sh ]; then
  echo "~/mariadb-qa/build_mdpsms_opt_san.sh missing!"
  exit 1
fi

# Setup compile environment
sed -i 's|USE_SAN=[01]|USE_SAN=1|' ~/mariadb-qa/build_mdpsms_opt_san.sh
sed -i 's|USE_TSAN=[01|USE_TSAN=0|' ~/mariadb-qa/build_mdpsms_opt_san.sh
sed -i 's|ASAN_OR_MSAN=[01]|ASAN_OR_MSAN=0|' ~/mariadb-qa/build_mdpsms_opt_san.sh
sed -i 's|USE_CLANG=[01|USE_CLANG=0|' ~/mariadb-qa/build_mdpsms_opt_san.sh
sed -i 's|USE_AFL=[01|USE_AFL=0|' ~/mariadb-qa/build_mdpsms_opt_san.sh

DIR=${PWD}
rm -Rf 10.1_opt_asan 10.2_opt_asan 10.3_opt_asan 10.4_opt_asan 10.5_opt_asan 10.6_opt_asan
#cd ${DIR}/10.1 && ~/mariadb-qa/build_mdpsms_opt_san.sh &
cd ${DIR}/10.2 && ~/mariadb-qa/build_mdpsms_opt_san.sh &
cd ${DIR}/10.3 && ~/mariadb-qa/build_mdpsms_opt_san.sh &
cd ${DIR}/10.4 && ~/mariadb-qa/build_mdpsms_opt_san.sh &
cd ${DIR}/10.5 && ~/mariadb-qa/build_mdpsms_opt_san.sh &
cd ${DIR}/10.6 && ~/mariadb-qa/build_mdpsms_opt_san.sh &
