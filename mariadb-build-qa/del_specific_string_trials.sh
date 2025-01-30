#!/bin/bash
# This script deletes all trials that have a specific string in their MYBUG file

if [ -z "${1}" ]; then
  echo "Please provide a string to search for in each trial's MYBUG file, for which all matching trials should be deleted."
  echo 'Use with caution; e.g. passing "a" as input would delete all trials for which an "a" is anywhere in their MYBUG file!'
  echo "Note: do NOT use UniqueID's here: the input is regex-aware so | is seen as 'OR'"
  exit 1
elif [[ "${1}" == *"'" ]]; then
  echo "Do not use ' within the input string. You can use a dot (.) instead."
  exit 1
fi
grep "${1}" [0-9]*/[0-9]*/MYBUG | sed 's|/MYBUG.*||' | sed 's|^|cd |;s|/|;~/dt |;s|$|;cd - >/dev/null|' | tr '\n' '\0' | xargs -0 -I{} bash -c "{}"
