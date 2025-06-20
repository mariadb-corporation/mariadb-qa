#!/bin/bash
if [ "${PWD}" != "/data" ]; then
  echo "Assert: you will want to run this from /data"
  exit 1
fi
grep --binary-files=text '\[ERROR\]' [0-9]*/[0-9]*/log/master.err | sed 's|^.*ERROR. ||' | sort | uniq -c | sort -n | tac | more
