#!/bin/bash
set +H

if [ -z "${KNOWN_BUGS}" ]; then
  KNOWN_BUGS="${HOME}/mariadb-qa/known_bugs.strings"
fi
if [ ! -r "${KNOWN_BUGS}" ]; then
  echo "KNOWN_BUGS (${KNOWN_BUGS}) was not readable by this script"
  exit 1
fi

# Delete 0-byte files
find . -size 0 -type f -print0 | xargs -0 -I{} rm '{}'

# Delete known bugs
grep --binary-files=text -vE '^[ \t]*$|^#' ${KNOWN_BUGS} 2>/dev/null | sed 's|[ \t]\+##.*$||' | xargs -I{} grep --binary-files=text -Fi "{}" ${PWD}/*.string 2>/dev/null | sed 's|.string:.*$|.*|' | xargs -I{} echo "rm {}" | xargs -I{} bash -c "{}"
