#!/bin/bash
# This script delets all trials in /data for which the UniqueID starts with 'FALLBACK'

grep --binary-files=text '^FALLBACK|' /data/[0-9][0-9][0-9][0-9][0-9][0-9]/[0-9]*/MYBUG | sed 's|^/data/||;s|/MYBUG.*||' | sed 's|/|; ${HOME}/dt |;s|$|; cd /data|;s|^|cd /data/|' | tr '\n' '\0' | xargs -0 -I{} bash -c "{}"
