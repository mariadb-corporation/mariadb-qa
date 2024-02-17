#!/bin/bash
# This script deletes all /dev/shm/1[7-9]* directories which have 
# 1) Completed reducer.sh ('[DONE]')
# 2) Have reducer.sh which have not found any reduction yet and have seen recent resource issues ('[]...WARNING...detected')
cd /dev/shm
tail -n1 1[7-9]*/reducer.log 2>/dev/null | grep -EB1 '\[DONE\]|\[\].*WARNING.*detected' | grep '==>' | grep -o '1[7-9][0-9][0-9][0-9][0-9]\+' | sed 's|^|/dev/shm/|' | xargs -I{} echo "if [ -d '{}' ]; then rm -Rf '{}'; fi" | tr '\n' '\0' | xargs -I{} -0 bash -c "{}"
