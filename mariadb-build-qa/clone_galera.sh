#!/bin/bash
# Created by Roel Van de Paar, MariaDB
# Modified by Ramesh Sivaraman, MariaDB

if [[ "${1}" == "10."* ]]; then rm -Rf ${1} ${1}_galera; fi

# shellcheck disable=SC2120
clone_es_mdg_repo(){
  local GIT_USERNAME
  local GIT_ASKPASS
  read -p 'Github username (not email): ' GIT_USERNAME
  read -sp 'Github authentication token: ' GIT_ASKPASS
  echo ''
  git clone --depth=1 -j8 --branch=$1-enterprise https://$GIT_USERNAME@github.com/mariadb-corporation/MariaDBEnterprise  $1
  #clone galera repo
  if [[ ${1} =~ 10.[4-9] || ${1} =~ 10.10 ]]; then
    git clone --depth=1 --recurse-submodules -j8 --branch=es-mariadb-4.x https://$GIT_USERNAME@github.com/mariadb-corporation/es-galera.git $1_galera
  else
    git clone --depth=1 --recurse-submodules -j8 --branch=es-mariadb-3.x https://$GIT_USERNAME@github.com/mariadb-corporation/es-galera.git $1_galera
  fi
  sed -i "s|url = git@github.com:mariadb-corporation/xpand.git|url = https://$GIT_USERNAME@github.com/mariadb-corporation/xpand.git|" ${1}/.gitmodules 2&> /dev/null
  if grep -q "$GIT_USERNAME" ${1}/.gitmodules 2&> /dev/null ; then
    cd ${1}
    git submodule update --init --recursive
    cd ..
  fi
  unset GIT_USERNAME
  unset GIT_ASKPASS
  GIT_USERNAME=''
  GIT_ASKPASS=''
}

if [[ "${2}" == "ES" ]]; then
  clone_es_mdg_repo $1
else
  git clone --depth=1 --recurse-submodules -j8 --branch=$1 https://github.com/MariaDB/server.git $1 &
  # For full trees, use:
  #git clone --recurse-submodules -j8 --branch=$1 https://github.com/MariaDB/server.git $1 &
  #clone galera repo
  if [[ ${1} =~ 10.[4-9] ]]; then
    git clone --depth=1 --recurse-submodules -j8 --branch=mariadb-4.x https://github.com/MariaDB/galera $1_galera &
  else
    git clone --depth=1 --recurse-submodules -j8 --branch=mariadb-3.x https://github.com/MariaDB/galera $1_galera &
  fi
fi
