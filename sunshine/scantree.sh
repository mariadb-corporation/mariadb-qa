#!/bin/bash
# Created by Roel Van de Paar, MariaDB

# TODO Next
# - Read into array or multi-line string for faster memory-based parsing
# - Implement looping in script rather than script-recalling (a function may work best?)
# - Handle multi-way tree splits
# - Handle more then one occurence, e.g. there are 2x '^select:' etc.

if [ -z "${1}" ]; then echo "Pass start like 'select' as first option to this script!"; exit 1; fi

LINE="$(grep -m1 "^${1}:" grammar.txt | sed "s|^${1}:[ ]*||")"
if [[ "${LINE}" == "%empty" ]]; then exit 0; fi
if [[ "${LINE}" =~ ^[[:upper:]] ]]; then
  echo "Keyword: $(echo "${LINE}" | sed 's| .*||')"
fi
echo "${LINE}"
echo "${LINE}" | tr ' ' '\n' | xargs -I{} ./scantree.sh '{}'
