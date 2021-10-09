#!/bin/bash
# Created by Roel Van de Paar, MariaDB

BUILD_UBASAN=1  # Enable ASAN + UBSAN builds
BUILD_TSAN=1    # Enable TSAN builds
BUILD_10_1=0
BUILD_10_2=1
BUILD_10_3=1
BUILD_10_4=1
BUILD_10_5=1
BUILD_10_6=1
BUILD_10_7=1

if [ ! -r ./terminate_ds_memory.sh ]; then
  echo './terminate_ds_memory.sh missing!'
  exit 1
else
  ./terminate_ds_memory.sh  # Terminate ~/ds and ~/memory if running (with 3 sec delay)
fi

DIR=${PWD}

cleanup_dirs(){
  cd ${DIR}
  if [ -d /data/TARS ]; then mv ${DIR}/*.tar.gz /data/TARS 2>/dev/null; sync; fi
  rm -Rf 10.1_dbg_san 10.2_dbg_san 10.3_dbg_san 10.4_dbg_san 10.5_dbg_san 10.6_dbg_san 10.7_dbg_san \
         10.1_opt_san 10.2_opt_san 10.3_opt_san 10.4_opt_san 10.5_opt_san 10.6_opt_san 10.7_opt_san
}

buildall(){  # Build 2-by-2 in reverse order to optimize initial time-till-ready-for-use
  if [ ${BUILD_10_7} -eq 1 ]; then
    cleanup_dirs; cd ${DIR}/10.7 && ~/mariadb-qa/build_mdpsms_opt_san.sh
    cleanup_dirs; cd ${DIR}/10.7 && ~/mariadb-qa/build_mdpsms_dbg_san.sh
  fi

  if [ ${BUILD_10_6} -eq 1 ]; then
    cleanup_dirs; cd ${DIR}/10.6 && ~/mariadb-qa/build_mdpsms_opt_san.sh
    cleanup_dirs; cd ${DIR}/10.6 && ~/mariadb-qa/build_mdpsms_dbg_san.sh
  fi
  
  if [ ${BUILD_10_5} -eq 1 ]; then
    cleanup_dirs; cd ${DIR}/10.5 && ~/mariadb-qa/build_mdpsms_opt_san.sh
    cleanup_dirs; cd ${DIR}/10.5 && ~/mariadb-qa/build_mdpsms_dbg_san.sh
  fi

  if [ ${BUILD_10_4} -eq 1 ]; then
    cleanup_dirs; cd ${DIR}/10.4 && ~/mariadb-qa/build_mdpsms_opt_san.sh
    cleanup_dirs; cd ${DIR}/10.4 && ~/mariadb-qa/build_mdpsms_dbg_san.sh
  fi

  if [ ${BUILD_10_3} -eq 1 ]; then
    cleanup_dirs; cd ${DIR}/10.3 && ~/mariadb-qa/build_mdpsms_opt_san.sh
    cleanup_dirs; cd ${DIR}/10.3 && ~/mariadb-qa/build_mdpsms_dbg_san.sh
  fi

  if [ ${BUILD_10_2} -eq 1 ]; then
    cleanup_dirs; cd ${DIR}/10.2 && ~/mariadb-qa/build_mdpsms_opt_san.sh
    cleanup_dirs; cd ${DIR}/10.2 && ~/mariadb-qa/build_mdpsms_dbg_san.sh
  fi

  if [ ${BUILD_10_1} -eq 1 ]; then
    cleanup_dirs; cd ${DIR}/10.1 && ~/mariadb-qa/build_mdpsms_opt_san.sh
    cleanup_dirs; cd ${DIR}/10.1 && ~/mariadb-qa/build_mdpsms_dbg_san.sh
  fi
}

sed -i 's|^USE_SAN=[0-1]|USE_SAN=1|' ~/mariadb-qa//build_mdpsms_opt_san.sh
sed -i 's|^USE_SAN=[0-1]|USE_SAN=1|' ~/mariadb-qa//build_mdpsms_dbg_san.sh
sed -i 's|^ASAN_OR_MSAN=[0-1]|ASAN_OR_MSAN=0|' ~/mariadb-qa//build_mdpsms_opt_san.sh
sed -i 's|^ASAN_OR_MSAN=[0-1]|ASAN_OR_MSAN=0|' ~/mariadb-qa//build_mdpsms_dbg_san.sh

if [ ${BUILD_UBASAN} -eq 1 ]; then 
  sed -i 's|^USE_TSAN=[0-1]|USE_TSAN=0|' ~/mariadb-qa//build_mdpsms_opt_san.sh
  sed -i 's|^USE_TSAN=[0-1]|USE_TSAN=0|' ~/mariadb-qa//build_mdpsms_dbg_san.sh
  buildall
fi

if [ ${BUILD_TSAN} -eq 1 ]; then 
  sed -i 's|^USE_TSAN=[0-1]|USE_TSAN=1|' ~/mariadb-qa//build_mdpsms_opt_san.sh
  sed -i 's|^USE_TSAN=[0-1]|USE_TSAN=1|' ~/mariadb-qa//build_mdpsms_dbg_san.sh
  buildall
fi

cleanup_dirs
