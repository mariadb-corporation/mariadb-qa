#! /bin/bash
# Cleanup 'no core file found' trials manually (if script is not enabled), inc ~/dt cleanup of such trials (mainly to remove their respective reducers)
if [ -d /data ]; then
  echo "*** Before:"
  df -h | grep -E 'data|Avail'
  cd /data
  grep -l 'no core file found' [0-9]*/[0-9]*/MYBUG | sed 's|/MYBUG||' | xargs -I{} echo 'if [ -d {} ]; then rm -Rf {} ; fi' | tr '\n' '\0' | xargs -0 -I{} bash -c "{}"
  ls --color=never [0-9]*/reducer[0-9]*.sh | sed 's|^|cd /data/|;s|reducer\([0-9]\+\)|; if [ ! -d ./\1 ]; then ~/dt \1; fi|;s|\.sh$||' | tr '\n' '\0' | xargs -0 -I{} bash -c "{}" 2>/dev/null 1>&2
  echo "*** After: "
  df -h | grep -E 'data|Avail'
fi
