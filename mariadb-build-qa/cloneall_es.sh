#!/bin/bash
# Created by Roel Van de Paar, MariaDB

# Call the credentials check helper script to check ~/.git-credentials provisioning
SCRIPT_PWD=$(dirname $(readlink -f "${0}"))
if [ -r "${SCRIPT_PWD}/credentials_helper.source" ]; then
  source "${SCRIPT_PWD}/credentials_helper.source"
else
  echo "Assert: credentials_helper.sh not found/readable by this script ($0)"
  exit 1
fi

clone_es_repo(){
  git clone --depth=1 --recurse-submodules -j8 --branch=$1-enterprise https://github.com/mariadb-corporation/MariaDBEnterprise $1-es &
}

clone_es_repos(){
  # Current ES versions: https://mariadb.com/downloads/enterprise/enterprise-server/ (login with Google)
  rm -Rf 10.5-es
  rm -Rf 10.6-es
  rm -Rf 11.4-es
  clone_es_repo 10.5 &
  clone_es_repo 10.6 &
  clone_es_repo 11.4 &
}

clone_es_repos
