#!/bin/bash
SCRIPT_PWD=$(dirname $(readlink -f "${0}"))
# Note: the -P20 renders the '{}' subdirs (numbers) output hard to read (as they are output first by this script before starting pquery-clean-known.sh for each of those subdirs, but it is much faster. If/when debugging is needed, just set it to -P1 then revert to -Px afterwards.
ls -d --color=never [0-9][0-9][0-9][0-9][0-9][0-9] | xargs -I{} echo "if [ -d ./{} ]; then cd {}; echo -n '{}: '; ${SCRIPT_PWD}/pquery-clean-known.sh ${1}; cd - >/dev/null; else echo '{}: Failed?'; fi" | xargs -P20 -I{} bash -c "{}"
