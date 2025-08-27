#!/bin/bash
# Created by Roel Van de Paar, MariaDB
# This script can likely be sourced (. ./buildall_dbg.sh) to be able to use job control ('jobs', 'fg' etc)

# This script creates MSAN builds. Please note you need MSAN-instrumented libraries, ref mariadb-qa/build_mdpsms_dbg_san.sh and mariadb-qa/msan.instrumentedlibs_ubuntu2404.sh

# A note on memory consumption: buildall_dbg_msan.sh consumes about 35-40G on an otherwise idle server, when MAKE_THREADS=30 in ~/mariadb-qa/build_mdpsms_dbg_san.sh - if this is too much, use /test/buildall_san_slow.sh instead. This script will also create a significant I/O load. It is best to run this on an otherwise idle server with at least 120GB memory.
# TODO: currently, this script, building towards MSAN builds cannot be started at the same time as buildall_opt_san.sh building towards UBASAN builds, as the copied in-source build dir names used are _san. To fix this, mariadb-qa/build_mdpsms_dbg_san.sh (and opt) can be improved to use a directory like _msan. Then update the rm's below to remove *_msan etc.

# Restart inside a screen if this terminal session isn't one already
if [ "${STY}" == "" ]; then
  echo "Not a screen, restarting myself inside a screen"
  screen -admS "buildall_dbg_san" bash -c "$0;bash"
  sleep 1
  screen -d -r "buildall_dbg_san"
  return 2> /dev/null; exit 0
fi

sed -i 's|^ASAN_OR_MSAN=0|ASAN_OR_MSAN=1|' ~/mariadb-qa/build_mdpsms_dbg_san.sh  # Set to MSAN

DIR=${PWD}
rm -Rf 1[0-2].[0-9]_dbg_san
rm -Rf 10.1[0-1]_dbg_san
#cd ${DIR}/10.1 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/10.2 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/10.3 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/10.4 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/10.5 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
cd ${DIR}/10.6 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/10.7 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/10.8 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/10.9 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/10.10 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
cd ${DIR}/10.11 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/11.0 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/11.1 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/11.2 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/11.3 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
cd ${DIR}/11.4 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/11.5 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/11.6 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/11.7 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
cd ${DIR}/11.8 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/12.0 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
cd ${DIR}/12.1 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
cd ${DIR}/12.2 && ~/mariadb-qa/build_mdpsms_dbg_san.sh &
if [ -d ${DIR}/10.5-es ]; then cd ${DIR}/10.5-es && ~/mariadb-qa/build_mdpsms_dbg_san.sh & fi
if [ -d ${DIR}/10.6-es ]; then cd ${DIR}/10.6-es && ~/mariadb-qa/build_mdpsms_dbg_san.sh & fi
if [ -d ${DIR}/11.4-es ]; then cd ${DIR}/11.4-es && ~/mariadb-qa/build_mdpsms_dbg_san.sh & fi
if [ -d ${DIR}/11.8-es ]; then cd ${DIR}/11.8-es && ~/mariadb-qa/build_mdpsms_dbg_san.sh & fi

echo "All processes started as background threads... Output will commence soon."

sleep 60; sync
sed -i 's|^ASAN_OR_MSAN=1|ASAN_OR_MSAN=0|' ~/mariadb-qa/build_mdpsms_dbg_san.sh  # Revert to the more commonly used ASAN
