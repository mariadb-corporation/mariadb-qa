#!/bin/bash
SCRIPT_PWD=$(dirname $(readlink -f "${0}"))
SQLFILE="$(mktemp).sql"
echo "--- Writing SQL to $SQLFILE"

for tc in $(find $dir -type f -name "*.test"); do
  echo "Processing ${tc}"
  res="$(${SCRIPT_PWD}/mini_mtr_to_sql.sh $tc)"
  tc_sql_file=$(echo $res | grep -oP '(?<=Output: ).*(?= \()')
  cat $tc_sql_file >> $SQLFILE
done

echo "--- Output SQL file is $SQLFILE"
