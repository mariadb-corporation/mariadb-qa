#!/bin/bash
SCRIPT_PWD=$(cd "`dirname $0`" && pwd)  # Script location for pquery-clean-known.sh, which is in the same directory
ls -d --color=never [0-9][0-9][0-9][0-9][0-9][0-9] | xargs -I{} echo "if [ -d ./{} ]; then cd {}; ${SCRIPT_PWD}/pquery-clean-known.sh ${1}; cd - >/dev/null; fi" | xargs -P10 -I{} bash -c "{}"
