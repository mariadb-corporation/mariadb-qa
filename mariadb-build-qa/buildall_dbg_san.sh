#!/bin/bash
# Created by Roel Van de Paar, MariaDB
# This script can likely be sourced (. ./buildall_dbg.sh) to be able to use job control ('jobs', 'fg' etc)

# A note on memory consumption: buildall_dbg_san.sh consumes about 75-90G on an otherwise idle server, when MAKE_THREADS=16 in ~/mariadb-qa/build_mdpsms_dbg_san.sh - if this is too much, use buildall_san_slow.sh instead. This script will also create a significant I/O load. It is best to run this on an otherwise idle server with at least 120GB memory. Using MAKE_THREADS=30 will consume >150G (at around 95-100% into the compilations). Swap will be used when there is not sufficient physical memory, and if it is available, but it will be slower

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
  screen -admS "buildall_dbg_san" bash -c "$0;bash"
  sleep 1
  screen -d -r "buildall_dbg_san"
  return 2> /dev/null; exit 0
fi

DIR=${PWD}
rm -Rf 10.4_dbg 10.5_dbg 10.6_dbg 10.7_dbg 10.8_dbg 10.9_dbg 10.10_dbg 11.0_dbg 11.1_dbg 11.2_dbg
#cd ${DIR}/10.1 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/10.2 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
cd ${DIR}/10.3 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
sleep 1
cd ${DIR}/10.4 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
sleep 2
cd ${DIR}/10.5 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
sleep 3
cd ${DIR}/10.6 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
sleep 4
cd ${DIR}/10.7 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
sleep 5
cd ${DIR}/10.8 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
sleep 6
cd ${DIR}/10.9 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
sleep 7
cd ${DIR}/10.10 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
sleep 8
cd ${DIR}/10.11 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
sleep 9
cd ${DIR}/11.0 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
sleep 10
cd ${DIR}/11.1 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
sleep 11
cd ${DIR}/11.2 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &

echo "All processes started as background threads... Output will commence soon."