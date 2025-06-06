#!/bin/bash

# Restart inside a screen if this terminal session isn't one already
if [ "${STY}" == "" ]; then
  echo "Not a screen, restarting myself inside a screen"
  screen -admS "buildall_es_san" bash -c "$0;bash"
  sleep 1
  screen -d -r "buildall_es_san"
  return 2> /dev/null; exit 0
fi

rm -Rf 10.[5-6]-es_dbg 10.[5-6]-es_opt
rm -Rf 11.4-es_dbg 11.4-es_opt

if [ -d ${PWD}/10.5-es ]; then cd ${PWD}/10.5-es && ~/mariadb-qa/build_mdpsms_opt_san.sh & fi
if [ -d ${PWD}/10.6-es ]; then cd ${PWD}/10.6-es && ~/mariadb-qa/build_mdpsms_opt_san.sh & fi
if [ -d ${PWD}/11.4-es ]; then cd ${PWD}/11.4-es && ~/mariadb-qa/build_mdpsms_opt_san.sh & fi

if [ -d ${PWD}/10.5-es ]; then cd ${PWD}/10.5-es && ~/mariadb-qa/build_mdpsms_dbg_san.sh & fi
if [ -d ${PWD}/10.6-es ]; then cd ${PWD}/10.6-es && ~/mariadb-qa/build_mdpsms_dbg_san.sh & fi
if [ -d ${PWD}/11.4-es ]; then cd ${PWD}/11.4-es && ~/mariadb-qa/build_mdpsms_dbg_san.sh & fi
