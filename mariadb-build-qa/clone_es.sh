#!/bin/bash
# Created by Roel Van de Paar, MariaDB

if [ -z "${1}" ]; then
  echo "Please specify the version of ES to clone as the first option to this script, for example 11.4"
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

git clone --depth=1 --recurse-submodules -j8 --branch=$1-enterprise https://github.com/mariadb-corporation/MariaDBEnterprise $1-es &
