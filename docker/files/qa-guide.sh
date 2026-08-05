#!/bin/bash
# Open a guide.
#   qa-guide            The usage guide
#   qa-guide setup      The setup guide
#   qa-guide readme     What the box is
#   qa-guide cheatsheet The framework cheatsheet

set -u
DOCS="/usr/local/share/mariadb-qa-container"
case "${1:-usage}" in
  usage)      FILE="${DOCS}/USAGE.md" ;;
  setup)      FILE="${DOCS}/SETUP.md" ;;
  readme)     FILE="${DOCS}/README.md" ;;
  cheatsheet) FILE="${HOME}/mariadb-qa/cheatsheet.md" ;;
  *) echo "usage: qa-guide [usage|setup|readme|cheatsheet]"; exit 2 ;;
esac

if [ ! -r "${FILE}" ]; then
  echo "${FILE} is not there"
  exit 1
fi
if [ -t 1 ]; then
  less "${FILE}"
else
  cat "${FILE}"
fi
