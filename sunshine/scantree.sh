#!/bin/bash
# Created by Roel Van de Paar, MariaDB

if [ -z "${1}" ]; then echo "Pass start like 'select' as first option to this script!"; exit 1; fi

# TODO: If we find more then one occurence, what to do? e.g. there are 2x '^select:'
LINE="$(grep -m1 "^${1}:" grammar.txt | sed "s|^${1}:[ ]*||")"
if [[ "${LINE}" == "%empty" ]]; then exit 0; fi
if [[ "${LINE}" =~ ^[[:upper:]] ]]; then
  echo "Keyword: $(echo "${LINE}" | sed 's| .*||')"
fi
echo "${LINE}"
echo "${LINE}" | tr ' ' '\n' | xargs -I{} ./scantree.sh '{}'
