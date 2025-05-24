#!/bin/bash
# Created by Roel Van de Paar, MariaDB

rm -Rf 1[0-2].[0-9]
rm -Rf 10.1[0-1]

#./clone.sh 10.1 &
#./clone.sh 10.2 &
#./clone.sh 10.3 &
#./clone.sh 10.4 & 
./clone.sh 10.5 &
./clone.sh 10.6 &
#./clone.sh 10.7 &
#./clone.sh 10.8 &
#./clone.sh 10.9 &
#./clone.sh 10.10 &
./clone.sh 10.11 &
#./clone.sh 11.0 &
#./clone.sh 11.1 &
#./clone.sh 11.2 &
#./clone.sh 11.3 &
./clone.sh 11.4 &
#./clone.sh 11.5 &
#/clone.sh 11.6 &
#./clone.sh 11.7 &
./clone.sh 11.8 &
./clone.sh 12.0 &
# When updating the next line, i.e. when trunk has changed to a new major version, remember to make a similar fix in clone.sh
git clone --depth=1 --recurse-submodules -j8 https://github.com/MariaDB/server.git 12.1 &  # Trunk is currently the only 12.1 branch
