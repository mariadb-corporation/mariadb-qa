#!/bin/bash

if [ -z "${1}" ]; then
  echo 'Please specify what BASE workdirs the pquery results in this workdir should be filtered against, as follows:'
  echo './defilter_from_base.sh "BASEDIR1|BASEDIR2|BASEDIR3|etc."'
  echo 'For example, ./defilter_from_base.sh "123456|001122|998877"'
  echo "pquery-results will then show only UniqueID's which were seen in this workdir but not in any BASE workdirs"
  exit 1
fi

REFILTER=0
if [ -f "${1}" -a -r "${1}" ]; then
  echo "Re-using filter file ${1}"
  REFILTER=1
fi

PR="${HOME}/pr"
if [ ! -r "${PR}" ]; then
  PR="${HOME}/mariadb-qa/pquery-results.sh"
  if [ ! -r "${PR}" ]; then
    echo "Neither ${HOME}/pr nor ${HOME}/mariadb-qa/pquery-results.sh was found, cannot proceed, please git clone mariadb-qa into your homedir"
    exit 1
  fi
fi

if [ "${REFILTER}" -eq 0 ]; then
  # Change the IFS to split the input string by '|' into a dirs array
  IFS='|' read -r -a DIRS <<< "${1}"
  # Now check each dir
  for DIR in "${DIRS[@]}"; do
    if [[ ! -d "/data/$DIR" ]]; then
      echo "pquery workdir /data/$DIR does not exist, please fix the input provided"
      exit 1
    fi
  done
  # Now run pquery-results for each workdir passed
  FILTER="$(mktemp)"
  for DIR in "${DIRS[@]}"; do
    echo "Processing ${DIR}"
    cd /data/$DIR
    if [ "${PWD}" != "/data/$DIR" ]; then
      echo "Assert: PWD!=workdir: ${PWD} != /data/$DIR"
      exit 1
    fi
    # Store all seen UniqueID's in a temporary filter file
    ${PR} | grep 'Seen' | sed 's|[ ]*(Seen .*||' >> ${FILTER}
    cd - >/dev/null
  done
else
  FILTER="${1}"  # Re-use the given filter file
fi

# Dedup, if any, duplicate UniqueID's
sort -u -o ${FILTER} ${FILTER}

# Now run actual (i.e. current workdir) pr and filter out lines
PR_OUTPUT="$(mktemp)"
${PR} > ${PR_OUTPUT}
# Actual filter using fixed strings (-F) and filter based on all lines in the filter file (-f and -v)
grep -F -v -f ${FILTER} ${PR_OUTPUT}
rm -f ${PR_OUTPUT}
if [ "${REFILTER}" -eq 0 ]; then
  echo 'The generated filter file was also saved, so you can re-do this run (and others like it) quicker with this command:'
  echo "./defilter_from_base ${FILTER}"
else
  echo 'The filter file was also preserved, so you can again re-do this run (and others like it) quickly with this command:'
  echo "./defilter_from_base ${FILTER}"
fi
