#!/bin/bash
BASEDIR=/test/MD310522-mariadb-10.10.0-linux-x86_64-dbg
HOME=/home/$(whoami)

if [ ! -r ./list_unique_bugs -o ! -r ${BASEDIR}/bin/mysqld -o ! -r ${HOME}/t -o ! -r /test/gendirs.sh ]; then
  echo 'Check setup!'
  exit 1
fi

BUGS=$(./list_unique_bugs)
COUNT="$(printf "%s\n" "${BUGS}" | wc -l)"

echo "Processing ${COUNT} bugs..."
#for ((i=1;i<=${COUNT};i++)); do
for ((i=1;i<=1;i++)); do
  BUG="$(printf "%s\n" "${BUGS}" | head -n${i} | tail -n1)"
  echo "BUG ${i}/${COUNT}: ${BUG}"
done
