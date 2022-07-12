#!/bin/bash

if [ -z "${1}" ]; then
  echo "Please enter the search term to search for in all error logs in all basedirs as listed by ./gendirs.sh"
  exit 1
fi
if [ ! -r ./gendirs.sh ]; then 
  echo "Assert: ./gendirs.sh not present. Try ~/mariadb-qa/linkit"
  exit 1
fi
./gendirs.sh | xargs -I{} grep --binary-files=text -li "${1}" {}/log/master.err
