#!/bin/bash

# Transforms MTR .test files into plain SQL. Pass one or more .test files, or directories to search
# them in. The files are converted at the same time, -j sets how many at once, one per core default.

THREADS="$(nproc)"
TESTS=()
FILES=()
RES=()
PIDS=()

while [ "${#}" -gt 0 ]; do
  case "${1}" in
    -j) THREADS="${2}"; shift; shift;;
    -j*) THREADS="${1#-j}"; shift;;
    *) TESTS+=("${1}"); shift;;
  esac
done

if [ "${#TESTS[@]}" -eq 0 ]; then echo 'Please pass which .test file you would like transform from MTR to SQL'; exit 1; fi
if ! [[ "${THREADS}" =~ ^[0-9]+$ ]] || [ "${THREADS}" -eq 0 ]; then echo "The thread count passed (-j ${THREADS}) is not a number of 1 or higher"; exit 1; fi
if [ ! -x "${HOME}/tcp" ]; then echo "${HOME}/tcp does not exist (run ~/mariadb-qa/linkit to create it)"; exit 1; fi

for TEST in "${TESTS[@]}"; do
  if [ -d "${TEST}" ]; then
    while IFS= read -r FILE; do FILES+=("${FILE}"); done < <(find "${TEST}" -type f -name '*.test')
  elif [ -r "${TEST}" ]; then
    FILES+=("${TEST}")
  elif [ -r "${TEST}.test" ]; then
    FILES+=("${TEST}.test")
  else
    echo "The test file you passed (${TEST}) does not exist"; exit 1
  fi
done

convert(){  # $1=the .test file to read, $2=the SQL file to write
  ${HOME}/tcp "${1}" | grep --binary-files=text -vE '^[ \t]*$|^#|^\-|^{|^}|^eval|^let|^conn|^disc|^echo|^while|^skip' | tr '\n' ' ' | sed 's|;|;\n|g' | sed 's|^[ \t]*||g;s|[ \t]\+| |g;s|^eval[p]* ||;s|\$[a-zA-Z0-9]+|1|g' | grep --binary-files=text -vE '^[a-z]' > "${2}"
  sed -i ':a;s|^IF([\!]*$[^)]\+)[ \t]*||;ta' "${2}"  # Removes leading IF statements, repeated until a line has none left
}

report(){  # $1=the conversion to wait for. Only this shell prints, so the two lines of one file stay together
  wait "${PIDS[${1}]}"
  printf 'Input: %s (%s lines)\nOutput: %s (%s lines)\n' "${FILES[${1}]}" "$(wc -l < "${FILES[${1}]}")" "${RES[${1}]}" "$(wc -l < "${RES[${1}]}")"
}

# One conversion is reported as soon as it is done, and the oldest one is waited for before the next
# one starts, which keeps THREADS conversions running and reports the files in the order passed in
for i in "${!FILES[@]}"; do
  [ "${i}" -ge "${THREADS}" ] && report $(( i - THREADS ))
  RES[${i}]="$(mktemp)"
  convert "${FILES[${i}]}" "${RES[${i}]}" &
  PIDS[${i}]="${!}"
done
DRAIN=$(( ${#FILES[@]} - THREADS )); [ "${DRAIN}" -lt 0 ] && DRAIN=0
for ((i=DRAIN;i<${#FILES[@]};i++)){
  report "${i}"
}
