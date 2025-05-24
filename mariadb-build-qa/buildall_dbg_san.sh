#!/bin/bash
# Created by Roel Van de Paar, MariaDB
# This script can likely be sourced (. ./buildall_dbg.sh) to be able to use job control ('jobs', 'fg' etc)

# A note on memory consumption: buildall_dbg_san.sh consumes about 35-40G on an otherwise idle server, when MAKE_THREADS=30 in ~/mariadb-qa/build_mdpsms_dbg_san.sh - if this is too much, use /test/buildall_san_slow.sh instead. This script will also create a significant I/O load. It is best to run this on an otherwise idle server with at least 120GB memory.

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
rm -Rf 1[0-2].[0-9]_dbg_san
rm -Rf 10.1[0-1]_dbg_san
#cd ${DIR}/10.1 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/10.2 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/10.3 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/10.4 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/10.5 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
cd ${DIR}/10.6 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
sleep 10
#cd ${DIR}/10.7 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/10.8 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/10.9 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/10.10 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
cd ${DIR}/10.11 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
sleep 10
#cd ${DIR}/11.0 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/11.1 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/11.2 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/11.3 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
cd ${DIR}/11.4 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
sleep 10
#cd ${DIR}/11.5 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/11.6 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/11.7 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
cd ${DIR}/11.8 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
sleep 10
cd ${DIR}/12.0 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
sleep 10
cd ${DIR}/12.1 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
if [ -d ${DIR}/10.5-es ]; then sleep 10; cd ${DIR}/10.5-es && ~/mariadb-qa/build_mdpsms_dbg_san.sh & fi
if [ -d ${DIR}/10.6-es ]; then sleep 10; cd ${DIR}/10.6-es && ~/mariadb-qa/build_mdpsms_dbg_san.sh & fi
if [ -d ${DIR}/11.4-es ]; then sleep 10; cd ${DIR}/11.4-es && ~/mariadb-qa/build_mdpsms_dbg_san.sh & fi

echo "All processes started as background threads... Output will commence soon."
