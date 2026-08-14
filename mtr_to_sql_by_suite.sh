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
    ${SCRIPT_PWD}/mtr_to_sql_mini.sh "$dir" | while read -r what file rest; do
      case "${what}" in
        Output:) cat $file >> $SQLFILE;;
      esac
    done
  fi
done
echo "Output SQL file is $SQLFILE"
