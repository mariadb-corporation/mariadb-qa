#!/bin/bash
# Created by Roel Van de Paar, MariaDB
# Modified by Ramesh Sivaraman, MariaDB

if [[ "${1}" == "10."* ]]; then rm -Rf ${1} ${1}_galera; fi
# shellcheck disable=SC2120
clone_es_mdg_repo(){
  local GIT_USERNAME
  local GIT_ASKPASS
  read -p 'Github username: ' GIT_USERNAME
  read -sp 'Github authentication token: ' GIT_ASKPASS
  git clone --depth=1 --recurse-submodules -j8 --branch=$1-enterprise https://$GIT_USERNAME@github.com/mariadb-corporation/MariaDBEnterprise  $1 &
  #clone galera repo
  if [[ ${1} =~ 10.[4-6] ]]; then
    git clone --depth=1 --recurse-submodules -j8 --branch=es-mariadb-4.x https://$GIT_USERNAME@github.com/mariadb-corporation/es-galera.git $1_galera &
  else
    git clone --depth=1 --recurse-submodules -j8 --branch=es-mariadb-3.x https://$GIT_USERNAME@github.com/mariadb-corporation/es-galera.git $1_galera &
  fi
  unset GIT_USERNAME
  unset GIT_ASKPASS
  GIT_USERNAME=''
  GIT_ASKPASS=''
}
if [[ "${2}" == "ES" ]]; then
  clone_es_mdg_repo
else
  git clone --depth=1 --recurse-submodules -j8 --branch=$1 https://github.com/MariaDB/server.git $1 &
  # For full trees, use:
  #git clone --recurse-submodules -j8 --branch=$1 https://github.com/MariaDB/server.git $1 &
  #clone galera repo
  if [[ ${1} =~ 10.[4-6] ]]; then
    git clone --depth=1 --recurse-submodules -j8 --branch=mariadb-4.x https://github.com/MariaDB/galera $1_galera &
  else
    git clone --depth=1 --recurse-submodules -j8 --branch=mariadb-3.x https://github.com/MariaDB/galera $1_galera &
  fi
fi
