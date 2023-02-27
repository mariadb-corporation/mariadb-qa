#!/bin/bash 
# Note: this takes up quite a bit of space, these are complete trees

rm -Rf 10.3; git clone --recurse-submodules -j8 --branch=10.3 https://github.com/MariaDB/server.git 10.3 &
rm -Rf 10.4; git clone --recurse-submodules -j8 --branch=10.4 https://github.com/MariaDB/server.git 10.4 &
rm -Rf 10.5; git clone --recurse-submodules -j8 --branch=10.5 https://github.com/MariaDB/server.git 10.5 &
rm -Rf 10.6; git clone --recurse-submodules -j8 --branch=10.6 https://github.com/MariaDB/server.git 10.6 &
rm -Rf 10.7; git clone --recurse-submodules -j8 --branch=10.7 https://github.com/MariaDB/server.git 10.7 &
rm -Rf 10.8; git clone --recurse-submodules -j8 --branch=10.8 https://github.com/MariaDB/server.git 10.8 &
rm -Rf 10.9; git clone --recurse-submodules -j8 --branch=10.9 https://github.com/MariaDB/server.git 10.9 &
rm -Rf 10.10; git clone --recurse-submodules -j8 --branch=10.10 https://github.com/MariaDB/server.git 10.10 &
rm -Rf 10.11; git clone --recurse-submodules -j8 --branch=10.11 https://github.com/MariaDB/server.git 10.11 &
#rm -Rf 10.12; git clone --recurse-submodules -j8 --branch=10.12 https://github.com/MariaDB/server.git 10.12 &
