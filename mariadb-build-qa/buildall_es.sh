#!/bin/bash

# Restart inside a screen if this terminal session isn't one already
if [ "${STY}" == "" ]; then
  echo "Not a screen, restarting myself inside a screen"
  screen -admS "buildall_es" bash -c "$0;bash"
  sleep 1
  screen -d -r "buildall_es"
  return 2> /dev/null; exit 0
fi

rm -Rf 10.[56]-es_dbg 10.[56]-es_opt
rm -Rf 11.[48]-es_dbg 11.[48]-es_opt

#if [ -d ${PWD}/10.5-es ]; then cd ${PWD}/10.5-es && ~/mariadb-qa/build_mdpsms_opt.sh & fi
if [ -d ${PWD}/10.6-es ]; then cd ${PWD}/10.6-es && ~/mariadb-qa/build_mdpsms_opt.sh & fi
if [ -d ${PWD}/11.4-es ]; then cd ${PWD}/11.4-es && ~/mariadb-qa/build_mdpsms_opt.sh & fi
if [ -d ${PWD}/11.8-es ]; then cd ${PWD}/11.8-es && ~/mariadb-qa/build_mdpsms_opt.sh & fi

#if [ -d ${PWD}/10.5-es ]; then cd ${PWD}/10.5-es && ~/mariadb-qa/build_mdpsms_dbg.sh & fi
if [ -d ${PWD}/10.6-es ]; then cd ${PWD}/10.6-es && ~/mariadb-qa/build_mdpsms_dbg.sh & fi
if [ -d ${PWD}/11.4-es ]; then cd ${PWD}/11.4-es && ~/mariadb-qa/build_mdpsms_dbg.sh & fi
if [ -d ${PWD}/11.8-es ]; then cd ${PWD}/11.8-es && ~/mariadb-qa/build_mdpsms_dbg.sh & fi
