#!/bin/bash
# This script deletes most issues that have partial traces ('Backtrace stopped' in UniqueID) as these are often duplicates of already logged issues and/or show as full stacks in alterantive trials
ls -1d [0-9][0-9][0-9][0-9][0-9][0-9] | xargs -I{} echo "cd {}; ~/pr | grep 'Backtrace stopped' | sed 's|.*reducers ||;s|)||' | tr ',' '\n' | xargs -I{} ~/dt {}; cd - >/dev/null" | tr '\n' '\0' | xargs -0 -I{} bash -c "{}"
