#!/bin/bash
# Created by Roel Van de Paar, MariaDB

# TODO: parallel builds

rm -f afl-fuzz
make clean
for ((i=0;i<=9;i++)){
  sed -i "s|/test/afl[0-9]_socket.sock|/test/afl${i}_socket.sock|g" afl-fuzz.c
  make -j10
  mv afl-fuzz afl${i}-fuzz
}
sed -i "s|/test/afl[0-9]_socket.sock|/test/afl0_socket.sock|g" afl-fuzz.c
echo 'Done! Now do:'
echo 'rm -f ${HOME}/mariadb-qa/fuzzer/afl?-fuzz'
echo "mv afl?-fuzz  ${HOME}/mariadb-qa/fuzzer/"
