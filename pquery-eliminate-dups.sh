#!/bin/bash
# Created by Roel Van de Paar, Percona LLC

# This script eliminates duplicate trials where at least x trials are present for a given issue, and x trials are kept for each such issue where duplicates are eliminated. Execute from within the pquery workdir. x is defined by the number of [0-9]\+, entries

# User variables
#TRIALS_TO_KEEP=2  # Set high (for example: 10) when there are few bugs seen in each new round. Set low (for example: 2) when handling many new bugs/when many bugs are seen in the runs
# Tip: if you need a quick cleanup with TRIALS_TO_KEEP=2 of all /data/... workdirs, do:
# cd /data && ls -d [0-9][0-9]* | xargs -I{} echo "cd /data/{}; ~/mariadb-qa/pquery-eliminate-dups.sh" | tr '\n' '\0' | xargs -0 -I{} -P40 bash -c "{}"  # Note the high-load 40 threads
TRIALS_TO_KEEP=3  # Set high (for example: 10) when there are few bugs seen in each new round. Set low (for example: 2) when handling many new bugs/when many bugs are seen in the runs

# Internal variables
SCRIPT_PWD=$(dirname $(readlink -f "${0}"))

# Checks
if [ ! -r pquery-run.log -o ! -d mysqld ]; then
  echo 'This directory is not a pquery run directory it seems! Terminating'
  exit 1
fi
if [ -z "${TRIALS_TO_KEEP}" ]; then
  echo 'Assert: TRIALS_TO_KEEP is empty. Terminating'
  exit 1
elif [ "$(echo "${TRIALS_TO_KEEP}" | grep -o '[0-9]\+')" != "${TRIALS_TO_KEEP}" ]; then
  echo "Assert: TRIALS_TO_KEEP (${TRIALS_TO_KEEP}) is not numerical. Terminating"
  exit 1
elif [ "${TRIALS_TO_KEEP}" -lt 2 ]; then
  echo "Assert: TRIALS_TO_KEEP (${TRIALS_TO_KEEP}) is less then 2. Minimum: TRIALS_TO_KEEP=2. Please fix setup. Terminating"
  exit 1
fi

# Keep x trials
SED_STRING='[-0-9]\+,'
for cnt in $(seq 2 ${TRIALS_TO_KEEP}); do  # 2: we already have one element in SED_STRING
  SED_STRING="${SED_STRING}"'[-0-9]\+,'  # Prepare a replace string which equals TRIALS_TO_KEEP trials
done
SEARCH_STRING="${SED_STRING}"'.*'  # Find reducers with at least TRIALS_TO_KEEP+1 trials. The '+1', whilst likely not strictly necessary, is an extra safety measure and is guaranteed by the ',' added at the end of SED_STRING as created above. After SEARCH_STRING is created, we remove the comma as the SED_STRING should only match the exact number of trials as set by TRIALS_TO_KEEP
SED_STRING="$(echo "${SED_STRING}" | sed 's|,$||')"  # Remove the last comma for the SED_STRING only

# The 'grep -v reducer' in the next line is an extraneous check for safety
#${SCRIPT_PWD}/pquery-results.sh 2>/dev/null | grep --binary-files=text -v 'TRIALS TO CHECK MANUALLY' | sed 's|_val||g' | grep --binary-files=text -oE "Seen[ \t]+[0-9][0-9]+ times.*,.*|Seen[ \t]+[2-9] times.*,.*" | grep --binary-files=text -o "reducers [ ]*${SEARCH_STRING}" | sed "s|reducers [ ]*${SED_STRING}||" | sed 's|)||;s|,|\n|g' | grep --binary-files=text -v 'reducer' | grep --binary-files=text -v '^[ \t]*$' | xargs -I{} ${SCRIPT_PWD}/pquery-del-trial.sh {}
# Discussed RS/RV 19-02-2021
# Whereas the command above ^ is the most accurate (and should be maintained alike to the line below!), the
# line below adds an additional drop of the specific node selector `-1,-2,-3` in order - FOR THE MOMENT (TODO) -
# to delete the entire trial. Once we commence pquery multinode runs, we should start using the line above instead,
# Or make the line optional or selectable somehow. Perhaps we can have another homedir script which selects either
# line etc. One more questionable item is the '*' in the 's|\-[1-3]*$||' sed (it's too broad, there for -23 TODO)
# Can it be removed later on without limiting cleanup functionality? TEST.
${SCRIPT_PWD}/pquery-results.sh 2>/dev/null | grep --binary-files=text -vE 'TRIALS TO CHECK MANUALLY' | sed 's|_val||g' | grep --binary-files=text -oE "Seen[ \t]+[0-9][0-9]+ times.*,.*|Seen[ \t]+[2-9] times.*,.*" | grep --binary-files=text -o "reducers [ ]*${SEARCH_STRING}" | sed "s|reducers [ ]*${SED_STRING}||" | sed 's|)||;s|,|\n|g' | grep --binary-files=text -v 'reducer' | grep --binary-files=text -v '^[ \t]*$' | sed 's|\-[1-3]*$||' | xargs -I{} ${SCRIPT_PWD}/pquery-del-trial.sh {} 1
