#!/bin/bash
# Created by Roel Van de Paar, MariaDB

if [[ "${1}" == "10."* ]]; then rm -Rf ${1} ${1}_galera; fi
if [[ "${2}" == "ES" ]]; then
  if [[ -z $GIT_ASKPASS ]]; then
    read -p 'Github username: ' GIT_USERNAME
    read -sp 'Github authentication token: ' GIT_TOKEN
    export GIT_ASKPASS=$GIT_TOKEN
  fi
  git clone --depth=1 --recurse-submodules -j8 --branch=$1-enterprise https://$GIT_USERNAME@github.com/mariadb-corporation/MariaDBEnterprise  $1 &
  #clone galera repo
  if [[ ${1} =~ 10.[4-6] ]]; then
    git clone --depth=1 --recurse-submodules -j8 --branch=es-mariadb-4.x https://$GIT_USERNAME@github.com/mariadb-corporation/es-galera.git $1_galera &
  else
    git clone --depth=1 --recurse-submodules -j8 --branch=es-mariadb-3.x https://$GIT_USERNAME@github.com/mariadb-corporation/es-galera.git $1_galera &
  fi
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