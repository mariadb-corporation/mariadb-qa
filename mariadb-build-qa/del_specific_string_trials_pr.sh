#!/bin/bash
STRING="${1}"
if [ -z "${STRING}" ]; then
  echo "Assert: please pass the string you would like to search for in ${HOME}/pr output. All trials (as listed by pr i.e. pquery-results.sh) listed for this string will be deleted. The string can contain regex."
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
elif [ ! -r ${HOME}/pr ]; then
  echo "Assert: ${HOME}/pr not found, consider running ${HOME}/mariadb-qa/linkit to create it"
  exit 1
elif [ ! -r ${HOME}/dt ]; then
  echo "Assert: ${HOME}/dt not found, consider running ${HOME}/mariadb-qa/linkit to create it"
  exit 1
fi
echo "Processing. This may take some time..."
rm -f tmpd1
ls -d [0-9]* | xargs -I{} echo "cd {}; ${HOME}/pr | grep --binary-files=text -Ei '${STRING}' | grep --binary-files=text -o 'reducers [0-9].*' | grep --binary-files=text -o '[0-9,]\+' | tr ',' '\\n' | sed \"s|^|${HOME}/dt |;s|$| ${2};cd /data >/dev/null|\" | tr '\n' '\0' | xargs -0 -I_ bash -c \"_\"" | tr '\n' '\0' | xargs -0 -I{} bash -c "{}"
