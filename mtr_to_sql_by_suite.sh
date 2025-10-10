#!/bin/bash
####################################################################################
# Usage: mysql-test$ mtr_to_sql_by_suite.sh suite/rpl suite/binlog                 #
####################################################################################
SCRIPT_PWD=$(dirname $(readlink -f "${0}"))

if [ "$#" -eq 0 ]; then
  echo "Please supply suite path(s) which contains *.test files."
  exit 1
fi

SQLFILE=$(mktemp)

for arg in "${@}"; do
  dir=$(realpath $arg)
  if [ ! -d "$dir" ]; then
    echo "$dir does not exist, so skipping it."
  else
    for tc in $(find $dir -type f -name "*.test"); do
      res="$(${SCRIPT_PWD}/mtr_to_sql_mini.sh $tc)"
      tc_sql_file=$(echo $res | grep -oP '(?<=Output: ).*(?= \()')
      cat $tc_sql_file >> $SQLFILE
    done
  fi
done
echo "Output SQL file is $SQLFILE"
