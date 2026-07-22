#!/bin/bash
# Created by Roel Van de Paar, MariaDB
# This script can likely be sourced (. ./buildall_dbg_tsan.sh) to be able to use job control ('jobs', 'fg' etc)

# This script creates TSAN builds via the shared build_mdpsms_dbg_san.sh with the USE_TSAN=1 env override (ref the 'bat' alias). No script edits are made, so concurrent ASAN+UBSAN use of the same script elsewhere is unaffected.
# The build scratch dir is <ver>_dbg_tsan (distinct from UBASAN's <ver>_dbg_san), so this script can run concurrently with buildall_dbg_san.sh; buildall_tsan_slow.sh uses its own private source workspace and does not conflict either.

# A note on memory consumption: buildall_dbg_tsan.sh consumes about 35-40G on an otherwise idle server, when MAKE_THREADS=30 in ~/mariadb-qa/build_mdpsms_dbg_san.sh - if this is too much, use /test/buildall_tsan_slow.sh instead. This script will also create a significant I/O load. It is best to run this on an otherwise idle server with at least 120GB memory.

# Restart inside a screen if this terminal session isn't one already
if [ "${STY}" == "" ]; then
  echo "Not a screen, restarting myself inside a screen"
  screen -admS "buildall_dbg_tsan" bash -c "$0;bash"
  sleep 1
  screen -d -r "buildall_dbg_tsan"
  return 2> /dev/null; exit 0
fi

DIR=${PWD}
rm -Rf 1[0-3].[0-9]_dbg_tsan
rm -Rf 10.1[0-1]_dbg_tsan
#cd ${DIR}/10.1 && USE_TSAN=1 ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/10.2 && USE_TSAN=1 ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/10.3 && USE_TSAN=1 ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/10.4 && USE_TSAN=1 ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/10.5 && USE_TSAN=1 ~/mariadb-qa/build_mdpsms_dbg_san.sh &
cd ${DIR}/10.6 && USE_TSAN=1 ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/10.7 && USE_TSAN=1 ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/10.8 && USE_TSAN=1 ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/10.9 && USE_TSAN=1 ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/10.10 && USE_TSAN=1 ~/mariadb-qa/build_mdpsms_dbg_san.sh &
cd ${DIR}/10.11 && USE_TSAN=1 ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/11.0 && USE_TSAN=1 ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/11.1 && USE_TSAN=1 ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/11.2 && USE_TSAN=1 ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/11.3 && USE_TSAN=1 ~/mariadb-qa/build_mdpsms_dbg_san.sh &
cd ${DIR}/11.4 && USE_TSAN=1 ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/11.5 && USE_TSAN=1 ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/11.6 && USE_TSAN=1 ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/11.7 && USE_TSAN=1 ~/mariadb-qa/build_mdpsms_dbg_san.sh &
cd ${DIR}/11.8 && USE_TSAN=1 ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/12.0 && USE_TSAN=1 ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/12.1 && USE_TSAN=1 ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#cd ${DIR}/12.2 && USE_TSAN=1 ~/mariadb-qa/build_mdpsms_dbg_san.sh &
cd ${DIR}/12.3 && USE_TSAN=1 ~/mariadb-qa/build_mdpsms_dbg_san.sh &
cd ${DIR}/13.0 && USE_TSAN=1 ~/mariadb-qa/build_mdpsms_dbg_san.sh &
cd ${DIR}/13.1 && USE_TSAN=1 ~/mariadb-qa/build_mdpsms_dbg_san.sh &
#if [ -d ${DIR}/10.5-es ]; then cd ${DIR}/10.5-es && USE_TSAN=1 ~/mariadb-qa/build_mdpsms_dbg_san.sh & fi
if [ -d ${DIR}/10.6-es ]; then cd ${DIR}/10.6-es && USE_TSAN=1 ~/mariadb-qa/build_mdpsms_dbg_san.sh & fi
if [ -d ${DIR}/11.4-es ]; then cd ${DIR}/11.4-es && USE_TSAN=1 ~/mariadb-qa/build_mdpsms_dbg_san.sh & fi
if [ -d ${DIR}/11.8-es ]; then cd ${DIR}/11.8-es && USE_TSAN=1 ~/mariadb-qa/build_mdpsms_dbg_san.sh & fi
if [ -d ${DIR}/12.3-es ]; then cd ${DIR}/12.3-es && USE_TSAN=1 ~/mariadb-qa/build_mdpsms_dbg_san.sh & fi

echo "All processes started as background threads... Output will commence soon."
