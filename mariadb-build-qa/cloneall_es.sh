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
  echo "Cloning ${1}-es (log: /tmp/cloneall_es_${1}.log)"
  git clone --depth=1 --recurse-submodules -j8 --branch=$1-enterprise https://github.com/mariadb-corporation/MariaDBEnterprise $1-es > /tmp/cloneall_es_${1}.log 2>&1 &
  PIDS="${PIDS} $!:${1}"
}

clone_es_repos(){
  # Current ES versions: https://mariadb.com/downloads/enterprise/enterprise-server/ (login with Google)
  #rm -Rf 10.5-es
  rm -Rf 10.6-es
  rm -Rf 11.4-es
  rm -Rf 11.8-es
  rm -Rf 12.3-es
  #clone_es_repo 10.5
  clone_es_repo 10.6
  clone_es_repo 11.4
  clone_es_repo 11.8
  clone_es_repo 12.3
}

PIDS=""
clone_es_repos
FAILED=0
for PIDVER in ${PIDS}; do
  PID="${PIDVER%%:*}"
  VERSION="${PIDVER##*:}"
  if wait ${PID}; then
    echo "${VERSION}-es: clone OK"
    rm -f /tmp/cloneall_es_${VERSION}.log
  else
    FAILED=1
    rm -Rf ${VERSION}-es
    echo "${VERSION}-es: CLONE FAILED - incomplete ${VERSION}-es directory removed, full log: /tmp/cloneall_es_${VERSION}.log"
    tail -n5 /tmp/cloneall_es_${VERSION}.log
  fi
done
if [ ${FAILED} -eq 1 ]; then
  echo "One or more ES clones failed and their directories were removed. Re-run this script to retry."
  exit 1
fi
echo "All ES clones completed OK"
