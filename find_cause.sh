#!/bin/bash

# Note: do not add end of line filtering of ";# ..." as that may often contain clues about lines just before/after which caused the issue

if [ -z "${1}" ]; then
  echo "This script finds likely causes in the provided SQL input file for user drops, access denied, etc."
  echo "Please specify an SQL input file"
  exit 1
elif [ ! -r "${1}" ]; then
  echo "The input file provided '${1}' cannot be read by this script"
  exit 1
fi

echo '====== All possibilties'
grep --binary-files=text -n -iE 'RELEASE|KILL|USER|REVOKE|ROOT|SHUTDOWN|PRIVILEGES|_PRIV|DROP.*host|DROP.*user|PASSWORD' "${1}"

echo '====== Most likely possibilties (check lines just before these manually in "All possibilties" output above)'
grep --binary-files=text -n -iE ' RELEASE|KILL |USER.*ROOT|REVOKE.*ROOT|SHUTDOWN|DROP.*mysql.*host|DROP.*mysql.*user|PASSWORD.*root|root.*PASSWORD|SET.*PASSWORD' "${1}"

echo '====== See "All possibilties" and "Most likely possibilties" above. If all else fails, SOURCE the sql file at the command line and observe which line things start failing at'
