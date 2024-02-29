#!/bin/bash
# Created by Roel Van de Paar, MariaDB

if [ -z "${1}" ]; then
  echo "Please include the ES version to clone, for example"
  echo "./clone_enterprise.sh 10.9"
  exit 1
fi

./clone_galera.sh "${1}" "ES"
