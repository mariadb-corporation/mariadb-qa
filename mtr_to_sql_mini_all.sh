#!/bin/bash
SCRIPT_PWD=$(dirname $(readlink -f "${0}"))
SQLFILE="$(mktemp).sql"
echo "--- Writing SQL to $SQLFILE"

${SCRIPT_PWD}/mtr_to_sql_mini.sh "${dir:-.}" | while read -r what file rest; do
  case "${what}" in
    Input:) echo "Processing ${file}";;
    Output:) cat $file >> $SQLFILE;;
  esac
done

echo "--- Output SQL file is $SQLFILE"
