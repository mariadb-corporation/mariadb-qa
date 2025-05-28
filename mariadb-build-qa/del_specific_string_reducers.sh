#!/bin/bash
STRING="${1}"
if [ -z "${STRING}" ]; then
  echo "Assert: please pass the string you would like to search for in ${HOME}/pr output. All reducers (as listed by pr i.e. pquery-results.sh) listed for this string will be deleted. The string can contain regex. Note that as soon as the string is detected pr output will stop, so if multiple strings are specified using the '|' seperator, only the first matching in any workdir's pr output will be used. Searches are case insensitive"
  exit 1
elif [ ! -r ${HOME}/pr ]; then
  echo "Assert: ${HOME}/pr not found, consider running ${HOME}/mariadb-qa/linkit"
  exit 1 
fi
echo "Processing. This may take some time..."
rm -f tmpd1
ls -d [0-9]* |  xargs -I{} echo "cd {}; ${HOME}/pr | grep -Eim1 '${STRING}' | grep -o 'reducers [0-9].*' | grep -o '[0-9,]\+' | tr ',' '\\n' | xargs -I_ rm reducer_.sh; cd - >/dev/null" >> tmpd1 && chmod +x tmpd1 && ./tmpd1; rm -f tmpd1
