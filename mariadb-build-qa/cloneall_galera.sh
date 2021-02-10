#!/bin/bash
# Created by Roel Van de Paar, MariaDB
MD_REPO=${1}
if [[ $MD_REPO == "ES" ]]; then
  read -p 'Github username: ' GIT_USERNAME
  read -sp 'Github authentication token: ' GIT_TOKEN
  export GIT_ASKPASS=$GIT_TOKEN
fi
echo ""
sleep 0.1
#rm -Rf 10.1 10.1_galera
rm -Rf 10.2 10.2_galera
rm -Rf 10.3 10.3_galera
rm -Rf 10.4 10.4_galera
rm -Rf 10.5 10.5_galera
rm -Rf 10.6 10.6_galera
echo ""
sleep 0.1
#./clone_galera.sh 10.1 $MD_REPO &
./clone_galera.sh 10.2 $MD_REPO &
./clone_galera.sh 10.3 $MD_REPO &
./clone_galera.sh 10.4 $MD_REPO &
./clone_galera.sh 10.5 $MD_REPO &
./clone_galera.sh 10.6 $MD_REPO &