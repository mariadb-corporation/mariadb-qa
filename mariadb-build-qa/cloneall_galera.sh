#!/bin/bash
# Created by Roel Van de Paar, MariaDB
# Modified by Ramesh Sivaraman, MariaDB

# Call the credentials check helper script to check ~/.git-credentials provisioning
SCRIPT_PWD=$(dirname $(readlink -f "${0}"))
if [ -r "${SCRIPT_PWD}/credentials_helper.source" ]; then
  source "${SCRIPT_PWD}/credentials_helper.source"
else
  echo "Assert: credentials_helper.sh not found/readable by this script ($0)"
  exit 1
fi

if [ ! -r ./clone_galera.sh ]; then
  echo 'Assert: ./clone_galera.sh not found or readable by this script'
  exit 1
fi

clone_multi_repos(){
  rm -Rf galera_3x
  rm -Rf galera_4x
  rm -Rf 10.5 
  rm -Rf 10.6 
  rm -Rf 11.4
  ./clone_galera.sh 10.5 &
  ./clone_galera.sh 10.6 automation &
  ./clone_galera.sh 11.4 automation &
}

clone_multi_repos
