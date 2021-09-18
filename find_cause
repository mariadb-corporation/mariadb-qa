#!/bin/bash

if [ -z "${1}" ]; then
  echo "This script finds likely causes in the provided SQL input file for user drops, access denied, etc."
  echo "Please specify an SQL input file"
  exit 1
fi

grep --binary-files=text -n -iE 'RELEASE|KILL|USER|ROOT|SHUTDOWN|PRIVILEGES|_PRIV' "${1}"
