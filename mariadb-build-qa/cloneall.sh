#!/bin/bash
# Created by Roel Van de Paar, MariaDB

echo ""
sleep 0.1
#rm -Rf 10.1
#rm -Rf 10.2
#rm -Rf 10.3
rm -Rf 10.4
rm -Rf 10.5
rm -Rf 10.6
rm -Rf 10.7
rm -Rf 10.8
rm -Rf 10.9
rm -Rf 10.10
rm -Rf 10.11
rm -Rf 11.0
rm -Rf 11.1
rm -Rf 11.2
echo ""
sleep 0.1
#./clone.sh 10.1 &
#./clone.sh 10.2 &
#./clone.sh 10.3 &
./clone.sh 10.4 & 
./clone.sh 10.5 &
./clone.sh 10.6 &
./clone.sh 10.7 &
./clone.sh 10.8 &
./clone.sh 10.9 &
./clone.sh 10.10 &
./clone.sh 10.11 &
./clone.sh 11.0 &
./clone.sh 11.1 &
#./clone.sh 11.2 &
