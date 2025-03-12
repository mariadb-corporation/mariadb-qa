#!/bin/bash
# Created by Roel Van de Paar, MariaDB
# Modified by Ramesh Sivaraman, MariaDB

# shellcheck disable=SC2120

# Call the credentials check helper script to check ~/.git-credentials provisioning
SCRIPT_PWD=$(dirname $(readlink -f "${0}"))
if [ -r "${SCRIPT_PWD}/credentials_helper.source" ]; then
  source "${SCRIPT_PWD}/credentials_helper.source"
else
  echo "Assert: credentials_helper.sh not found/readable by this script ($0)"
  exit 1
fi

if [[ "${1}" == "10."* ]]; then rm -Rf ${1}; fi
if [[ "${1}" == "11."* ]]; then rm -Rf ${1}; fi

clone_cs_mdg_repo(){
  git clone --depth=1 --recurse-submodules -j8 --branch=${1} https://github.com/MariaDB/server.git ${1} &
  #clone galera repo
  if [ "${2}" != "automation" ]; then  # Automation helper for cloneall_galera.sh
    if [[ ${1} =~ 10.[2-3] ]]; then
      rm -Rf galera_3x
      git clone --depth=1 --recurse-submodules -j8 --branch=mariadb-3.x https://github.com/MariaDB/galera galera_3x &
    else
      rm -Rf galera_4x
      git clone --depth=1 --recurse-submodules -j8 --branch=mariadb-4.x https://github.com/MariaDB/galera galera_4x &
    fi
  fi
}

clone_cs_mdg_repo ${1} ${2}
