#!/bin/bash
# Created by Roel Van de Paar, MariaDB
# Modified by Ramesh Sivaraman, MariaDB

MD_REPO=${1}

clone_repos(){
  if [[ "$MD_REPO" == "ES" ]]; then
    git clone --depth=1 --recurse-submodules -j8 --branch=$1-enterprise https://$GIT_USERNAME@github.com/mariadb-corporation/MariaDBEnterprise  $1 &
    #clone galera repo
    if [[ ${1} =~ 10.[4-9] || ${1} =~ 10.10 ]]; then
      git clone --depth=1 --recurse-submodules -j8 --branch=es-mariadb-4.x https://$GIT_USERNAME@github.com/mariadb-corporation/es-galera.git $1_galera &
    else
      git clone --depth=1 --recurse-submodules -j8 --branch=es-mariadb-3.x https://$GIT_USERNAME@github.com/mariadb-corporation/es-galera.git $1_galera &
    fi
    while ! grep -q "xpand" ${1}/.gitmodules 2&> /dev/null ; do
      sleep 2
      sed -i "s|url = git@github.com:mariadb-corporation/xpand.git|url = https://github.com/mariadb-corporation/xpand.git|" ${1}/.gitmodules 2&> /dev/null
      if grep -q "$GIT_USERNAME" ${1}/.gitmodules 2&> /dev/null ; then
        cd ${1}
        git submodule update --init --recursive
        cd ..
      fi
    done
  else
    git clone --depth=1 --recurse-submodules -j8 --branch=$1 https://github.com/MariaDB/server.git $1 &
    # For full trees, use:
    #git clone --recurse-submodules -j8 --branch=$1 https://github.com/MariaDB/server.git $1 &
    #clone galera repo
    if [[ ${1} =~ 10.[4-8] ]]; then
      git clone --depth=1 --recurse-submodules -j8 --branch=mariadb-4.x https://github.com/MariaDB/galera $1_galera &
    else
      git clone --depth=1 --recurse-submodules -j8 --branch=mariadb-3.x https://github.com/MariaDB/galera $1_galera &
    fi
  fi
}

clone_multi_repos(){
  sleep 0.1
  rm -Rf 10.2 10.2_galera
  rm -Rf 10.3 10.3_galera
  rm -Rf 10.4 10.4_galera
  rm -Rf 10.5 10.5_galera
  rm -Rf 10.6 10.6_galera
  rm -Rf 10.7 10.7_galera
  rm -Rf 10.8 10.8_galera
  rm -Rf 10.9 10.9_galera
  rm -Rf 10.10 10.10_galera
  sleep 0.1
  local GIT_USERNAME
  local GIT_ASKPASS
  echo ""
  if [[ $MD_REPO == "ES" ]]; then
    read -p 'Github username (not email): ' GIT_USERNAME
    read -sp 'Github authentication token: ' GIT_ASKPASS
  fi
  clone_repos 10.2 &
  clone_repos 10.3 &
  clone_repos 10.4 &
  clone_repos 10.5 &
  clone_repos 10.6 &
  clone_repos 10.7 &
  clone_repos 10.8 &
  #clone_repos 10.9 &
  #clone_repos 10.10 &
  unset GIT_USERNAME
  unset GIT_ASKPASS
  GIT_USERNAME=''
  GIT_ASKPASS=''
}

clone_multi_repos
