#!/bin/bash
# Created by Roel Van de Paar, MariaDB

# User variables
MAX_REPEATS=3  # The max number of times a given tree branch can be repeated (can be keyword/idiom/header...). For example 'SELECT_SYM %empty select_item_list ',' select_item ',' select_item' is possible with MAX_RECURSION=3 for 3x 'select_item'

# Program variables
RANDOM=`date +%s%N | cut -b13-19`  # Random entropy pool init

if [ -z "${1}" ]; then
  echo "Pass start like 'select' as first option to this script!"
  exit 1
else
  LINE="${1}"  # Set first idiom to scan for
fi

# Read grammar into memory array for faster processing
mapfile -t grammar < grammar.txt; GRAMMAR=${#grammar[*]}; 

scan_grammar(){
  # Scan the grammar for all occurrences of either the header (^${1}:) or the variations thereof (idem as header; additional occurrences thereof), or the variations (^| immediately after any found header). We always have to scan the whole array as variations of the header and/or variations can happen from the first till the last element/line thereof. In essence, a header, a variation of the header and a variations are all equal in value: they all provide different expressions of possible idioms contained therein. There are likely multiple header variations (rather than variations) to cater for different possible query expressions, though it is somwehat unclear why these were not written as variations rather than header variations. TODO: this may be a possible mysqld grammar optimization?
  local occurrences=()
  local FLAG_COMMENCED=0
  for ((i=0;i<${GRAMMAR};i++)); do
    if [[ "${grammar[${i}]}" == "${1}:"* ]]; then
      occurrences[${#occurrences[@]}]=${grammar[${i}]}
      FLAG_COMMENCED=1
      continue
    elif [ "${FLAG_COMMENCED}" -eq 1 ]; then
      if [[ "${grammar[${i}]}" == "|"* ]]; then
        occurrences[${#occurrences[@]}]=${grammar[${i}]}
        continue
      else
        FLAG_COMMENCED=0
        continue
      fi
    fi
  done
  # Now that we captured all possible variations, select a random one if there is more than one
  #echo "${#occurrences[*]}"
  local SELECTED_OCCURRENCE=
  if [ ${#occurrences[*]} -gt 1 ]; then
    SELECTED_OCCURRENCE=${occurrences[$[$RANDOM % ${#occurrences[*]}]]}
    while true; do
      if [ "$(echo "${LINE}" | grep -o "${SELECTED_OCCURRENCE}" | wc -l)" -gt ${MAX_REPEATS} ]; then
        SELECTED_OCCURRENCE=${occurrences[$[$RANDOM % ${#occurrences[*]}]]}
        continue
      else
        break
      fi
    done
  else
    SELECTED_OCCURRENCE=${occurrences[0]}
    if [ "$(echo "${LINE}" | grep -o "${SELECTED_OCCURRENCE}" | wc -l)" -gt ${MAX_REPEATS} ]; then
      SELECTED_OCCURRENCE=''
      occurrences=
    fi
  fi


      #if [ "$(grep "^${idioms[${j}]}$" ${RANDOMF} | wc -l)" -gt ${MAX_REPEATS} ]; then continue; fi

  # When ${#occurrences[*]} is 0, it means we have reached the end element of a tree; an actual query item
  if [ ${#occurrences[*]} -ne 0 ]; then
    # Cleanup SELECTED_OCCURRENCE variations by changing the leading '| ' (indicating a variation) to the input header (and thus also the format the LINE= code a bit lower expects). Note this will only change variations as headers (which in/by themselves are also variations) already have the input header and no '| '. The header then needs to be removed as it was re-inserted as part of the SELECTED_OCCURRENCE string (only when a '^${1}: ' was present/used).
    SELECTED_OCCURRENCE="$(echo "${SELECTED_OCCURRENCE}" | sed "s|^[ ]\+||;s/^| /${1} /;s|^${1}: | |")"
    # Now swap the header (or variation thereof) in the line to the randomly select occurrence
    LINE="$(echo "${LINE}" | sed "s|^${1}[: ]\+|${SELECTED_OCCURRENCE} |")"
    if [ "${LINE}" == "${LASTLINE}" ]; then LINE="$(echo "${LINE}" | sed "s| ${1}[: ]\+|${SELECTED_OCCURRENCE} |")"; fi
    if [ "${LINE}" == "${LASTLINE}" ]; then LINE="$(echo "${LINE}" | sed "s|^[ ]*${1}[ ]*$|${SELECTED_OCCURRENCE} |")"; fi  # start
    if [ "${LINE}" != "${LASTLINE}" ]; then
      # echo "LINE: |${LINE}| LASTLINE: |${LASTLINE}|"  # Debug
      echo "LINE: ${LINE}"  # Debug
      LASTLINE="${LINE}"
    fi
  fi
}

recurse_scan_grammar(){
  # Recursively repeat the same for each idiom (i.e. each header/variation) not complete yet
  local ACTIONED=1  # Dummy startup value
  while [ "${ACTIONED}" -eq 1 ]; do
    ACTIONED=0
    local idioms=(${LINE})
    for ((j=0;j<${#idioms[*]};j++)); do
      if [[ "${idioms[${j}]}" == "%empty" ]]; then continue; fi  # Skip already fully resolved '%empty'
      if [[ "${idioms[${j}]}" =~ ^_.* ]]; then continue; fi  # Skip already fully resolved leading '_' keywords
      if [[ "${idioms[${j}]}" =~ ^[[:upper:]] ]]; then continue; fi  # Skip already fully resolved keywords
      if [[ "${idioms[${j}]}" == "(" || "${idioms[${j}]}" == ")" || "${idioms[${j}]}" == "." || "${idioms[${j}]}" == "," || "${idioms[${j}]}" == "+" || "${idioms[${j}]}" == "-" || "${idioms[${j}]}" == "/" || "${idioms[${j}]}" == "%" || "${idioms[${j}]}" == "!" || "${idioms[${j}]}" == "<" || "${idioms[${j}]}" == ">" || "${idioms[${j}]}" == "{" || "${idioms[${j}]}" == "}" || "${idioms[${j}]}" == "~" || "${idioms[${j}]}" == "@" || "${idioms[${j}]}" == "=" || "${idioms[${j}]}" == "^" || "${idioms[${j}]}" == "|" || "${idioms[${j}]}" == "&" || "${idioms[${j}]}" == ":" || "${idioms[${j}]}" == ";" || "${idioms[${j}]}" == "ASTERIX" ]]; then continue; fi  # Skip resolved chars
      echo "${idioms[${j}]}"
      ACTIONED=1
      scan_grammar "${idioms[${j}]}"
    done
  done
}  

generate_statement(){
  #RANDOMF="/tmp/$(echo $RANDOM$RANDOM$RANDOM | sed 's/..\(.......\).*/\1/').stmt"
  #rm ${RANDOMF}
  LINE="${1}"
  echo "${LINE}"
  LASTLINE="${LINE}"
  recurse_scan_grammar "${LINE}"
  LINE="$(echo "${LINE}" | sed 's|ASTERIX|*|g')"  # Change ASTERIX back to *, ref gengrammar.sh
}

#while true; do
  generate_statement "${LINE}"
  echo "${LINE}" | sed 's|ASTERIX|*|g'
#done
