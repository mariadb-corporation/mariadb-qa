#!/bin/bash
# Tip: Paths which do not show any testcases listed under it are empty (no reduced/useful/to-keep testcases)

if [ ! -z "${1}" ]; then  # Specific version can be specified as first option
  ./basedirs.sh | grep "${1}" | awk '{print $2}' | xargs -I{} echo 'cd {}; pwd; find . | grep _out; cd -' | xargs -I{} bash -c "{}" | grep -v "^/data$"
else
  ./basedirs.sh | awk '{print $2}' | xargs -I{} echo 'cd {}; pwd; find . | grep _out; cd -' | xargs -I{} bash -c "{}" | grep -v "^/data$"
fi
