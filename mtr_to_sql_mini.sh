#!/bin/bash

if [ -z "${1}" ]; then echo 'Please pass which .test file you would like transform from MTR to SQL'; exit 1; fi
if [ ! -r "${1}" ]; then 
  if [ ! -r "${1}.test" ]; then 
    echo "The test file you passed (${1}) does not exist"; exit 1;
  else
    TEST="${1}.test"
  fi
else
  TEST="${1}"
fi
if [ ! -x "${HOME}/tcp" ]; then echo "${HOME}/tcp does not exist (run ~/mariadb-qa/linkit to create it)"; exit 1; fi

RES="$(mktemp)"
${HOME}/tcp "${TEST}" | grep --binary-files=text -vE '^[ \t]*$|^#|^\-|^{|^}|^eval|^let|^conn|^disc|^echo|^while|^skip' | tr '\n' ' ' | sed 's|;|;\n|g' | sed 's|^[ \t]*||g;s|[ \t]\+| |g;s|^eval[p]* ||;s|\$[a-zA-Z0-9]+|1|g' | grep --binary-files=text -vE '^[a-z]' > ${RES}

# Remove leading IF statements
for ((i=0;i<20;i++)){
  sed -i 's|^IF([\!]*$[^)]\+)[ \t]*||' ${RES}
}

echo "Input: ${TEST} ($(wc -l "${TEST}" | awk '{print $1}') lines)"
echo "Output: ${RES} ($(wc -l "${RES}" | awk '{print $1}') lines)"
