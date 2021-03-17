#!/bin/bash
# Created by Roel Van de Paar, MariaDB

if [[ "${1}" == "10."* ]]; then rm -Rf ${1}; fi
./clone_galera.sh "${1}" "ES"
