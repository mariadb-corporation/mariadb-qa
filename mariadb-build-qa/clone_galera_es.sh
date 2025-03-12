#!/bin/bash
# Created by Roel Van de Paar, MariaDB
# Modified by Ramesh Sivaraman, MariaDB

# shellcheck disable=SC2120

if [ -z "${1}" ]; then
  echo "Please specify the version of ES to clone as the first option to this script, for example 11.4"
  echo "The corresponding ES Galera branch will also be retrieved (into directory 'galera_3x-es' or 'galera_4x-es')"
  exit 1
fi

# Call the credentials check helper script to check ~/.git-credentials provisioning
SCRIPT_PWD=$(dirname $(readlink -f "${0}"))
if [ -r "${SCRIPT_PWD}/credentials_helper.source" ]; then
  source "${SCRIPT_PWD}/credentials_helper.source"
else
  echo "Assert: credentials_helper.sh not found/readable by this script ($0)"
  exit 1
fi

if [[ "${1}" == "10."* ]]; then rm -Rf ${1}-es; fi
if [[ "${1}" == "11."* ]]; then rm -Rf ${1}-es; fi

clone_es_mdg_repo(){
  git clone --depth=1 --recurse-submodules -j8 --branch=${1}-enterprise https://github.com/mariadb-corporation/MariaDBEnterprise.git ${1}-es &
  #clone galera repo
  if [ "${2}" != "automation" ]; then  # Automation helper for cloneall_galera_es.sh
    if [[ ${1} =~ 10.[2-3] ]]; then
      rm -Rf galera_3x
      git clone --depth=1 --recurse-submodules -j8 --branch=es-mariadb-3.x https://github.com/mariadb-corporation/es-galera.git galera_3x-es &
    else
      rm -Rf galera_4x
      git clone --depth=1 --recurse-submodules -j8 --branch=es-mariadb-4.x https://github.com/mariadb-corporation/es-galera.git galera_4x-es &
    fi
  fi
}

clone_es_mdg_repo ${1}
