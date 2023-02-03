#!/bin/bash

TMP="$(mktemp)"
cd /data
ls -d --color=never [0-9][0-9][0-9][0-9][0-9][0-9] | xargs -I{} echo 'cd {}; grep --binary-files=text -m1 "debug_dbug" [0-9]*/default.node.tld_thread-0.sql 2>/dev/null | grep -o "^[0-9]\+" | xargs -IDUMMY ${HOME}/dt DUMMY 1; cd /data' | sed 's|DUMMY|{}|g' > $TMP
chmod +x $TMP
$TMP
