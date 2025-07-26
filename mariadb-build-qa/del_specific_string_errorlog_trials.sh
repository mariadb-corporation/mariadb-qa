#!/bin/bash
# This script deletes all trials that have a specific string in their MYBUG file

if [ -z "${1}" ]; then
  echo "Please provide a string to search for in each trial's error logs, for which all matching trials should be deleted."
  echo 'Use with caution; e.g. passing "a" as input would delete all trials for which an "a" is anywhere in their errorlog!'
  echo 'Use with even more caution, knowing that error logs can contain multiple SAN issues for example, while the deletion will be based on only one of them, for example'
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
echo "This script will delete all trials which have '${1}' anywhere in their error log(s). Please confirm trice this is what you want to do. Note that if such trials have other bugs (cores, other *SAN issues, etc.) they will still be deleted. Use with care and use very specific non-broad strings"
read -p "Press enter 3x to confirm... 1x..."
read -p "Press enter 3x to confirm... 2x..."
read -p "Press enter 3x to confirm... 3x..."
./find_uniqueids_or_errorlog "${1}" 'passopt2' | sed 's|/log/[ms][al][sa][tv]e.*||' | sort -u | sed "s|^|cd |;s|/|;~/dt |;s|$| ${2};cd /data|" | tr '\n' '\0' | xargs -0 -I{} bash -c "{}"
