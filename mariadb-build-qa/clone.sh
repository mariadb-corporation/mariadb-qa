#!/bin/bash
# Created by Roel Van de Paar, MariaDB

if [ -z "${1}" ]; then echo "Assert: please specify a version, like 11.2"; exit 1; fi
if [[ "${1}" == "10."* || "${1}" == "11."* || "${1}" == "12."* ]]; then rm -Rf ${1}; fi

if [ "${1}" == "12.3" ]; then
  git clone --depth=1 --recurse-submodules -j8 https://github.com/MariaDB/server.git $1 &  # Trunk == 12.3
else
  git clone --depth=1 --recurse-submodules -j8 --branch=$1 https://github.com/MariaDB/server.git $1 &
fi

# For full trees, use:
#git clone --recurse-submodules -j8 --branch=$1 https://github.com/MariaDB/server.git $1 &
