#!/bin/bash
# This script deletes all trials that have a specific string in their MYBUG file

if [ -z "${1}" ]; then
  echo "Please provide a string to search for in each trial's MYBUG file, for which all matching trials should be deleted."
  echo 'Use with caution; e.g. passing "a" as input would delete all trials for which an "a" is anywhere in their MYBUG file!'a
  echo "Note: do NOT use UniqueID's here: the input is regex-aware so | is seen as 'OR'. Searches are case insensitive."
  echo "To pass '1' as an option to dt (i.e. force delete trials), pass '1' as the second option to this script. Use with care."
  exit 1
elif [[ "${1}" == *"'" ]]; then
  echo "Do not use ' within the input string. You can use a dot (.) instead."
  exit 1
elif [ ! -z "${2}" -a "${2}" != "1" ]; then
  echo "Input error: a second option was specified ($2), yet this option is unknown to this script (and to dt)"
  echo "The only valid options for the second option are either no second option at all, or '1' to force trial deletion"
  echo "Run this script without options to learn more on it's usage."
  exit 1
fi
grep --binary-files=text -i "${1}" [0-9]*/[0-9]*/MYBUG | sed 's|/MYBUG.*||' | sed "s|^|cd |;s|/|;~/dt |;s|$| ${2};cd - >/dev/null|" | tr '\n' '\0' | xargs -0 -I{} bash -c "{}"
