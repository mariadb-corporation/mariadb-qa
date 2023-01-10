#!/bin/bash
# Created by Roel Van de Paar, Percona LLC
# Updated by Roel Van de Paar, MariaDB
# Note that running this script does not execute pquery-clean-known.sh - run that script seperately as well, before or after this one (though in modern-day use of the framework this is all automated; run linkit then see ~/gomd to start runs, which includes all these already)

echo "Extra cleaning up of known issues++ (expert mode)..."

# Script variables
SCRIPT_PWD=$(cd "`dirname $0`" && pwd)
RANDOM=$(date +%s%N | cut -b10-19 | sed 's|^0+||')  # Random entropy init
RND=$(echo $RANDOM$RANDOM$RANDOM | sed 's/..\(......\).*/\1/')
TMP_FILE_1="/tmp/results_list++_${RND}.tmp"
TMP_FILE_2="/tmp/temp_pck++.sh_${RND}.tmp"

# Delete all known bugs which do not correctly produce unique bug ID's due to stack smashing etc.
# grep 'Assertion .state_ == s_exec || state_ == s_quitting. failed.' */log/master.err 2>/dev/null | sed 's|^\([0-9]\+\)/.*|\1|' | grep -o '[0-9]\+' | xargs -I{} ${SCRIPT_PWD}/pquery-del-trial.sh {}  # MDEV-22148 # Fixed
# grep 'Assertion .thd->transaction->stmt.is_empty() || thd->in_sub_stmt. failed.' */log/master.err 2>/dev/null | sed 's|^\([0-9]\+\)/.*|\1|' | grep -o '[0-9]\+' | xargs -I{} ${SCRIPT_PWD}/pquery-del-trial.sh {}  # MDEV-22726 # Fixed

# Delete all likely out of disk space trials
${SCRIPT_PWD}/pquery-results.sh | grep -A1 "Likely out of disk space trials" | \
 tail -n1 | tr ' ' '\n' | grep -v "^[ \t]*$" | xargs -I{} ${SCRIPT_PWD}/pquery-del-trial.sh {} 'NO_WARNINGS'

# Delete all trials in /data/ workdirs which ran into either of the following to-be-expected issues:
# 2022-03-12 16:14:19 4 [ERROR] Got error 126 when reading table './test/t'
# 2022-03-12 16:14:19 4 [ERROR] mysqld: Index for table 't' is corrupt; try to repair it
# As a direct result of:
# 2022-03-12 16:14:19 4 [ERROR] mysqld: Unknown key id 1. Can't continue!
# Which comes as a result of using 'SET GLOBAL aria_encrypt_tables=1;' without proper configuration
# See also https://jira.mariadb.org/browse/MDEV-26258
# The reason a thousands-line-before (-B1000) error log grep for these occurences is safe is that:
# 1) The one-liner script below first confirms there are no cores for the given trial
# 2) The one-liner script also confirms 'Unknown key id' is present for the given trial
# 3) (minor) The 'Unknown key id' has to come before (-B) these errors to be considered
if [ -d "/data" ]; then
  cd /data
  grep --binary-files=text -E -B1000 "Got error 126 when reading table|Index for table.*is corrupt; try to repair it" [0-9]*/[0-9]*/log/master.err | grep --binary-files=text "Unknown key id" | sed 's|/log/.*||' | sort -u | sed "s|^|cd |;s|/\([0-9]\+\)|; if grep -qi 'no core' ./\1/MYBUG; then ${SCRIPT_PWD}/pquery-del-trial.sh \1 1; fi; cd - >/dev/null 2>\&1|" | tr '\n' '\0' | xargs -0 -I{} bash -c "{}"
  cd - >/dev/null 2>&1
fi

# Delete all trials which have "Access denied for user 'root'@'localhost'" on the last few lines of the error log and that have no core file
if [ -r ${HOME}/pr ]; then
  # English
  rm -f ${TMP_FILE_2}
  ${HOME}/pr | grep "no core file found" | grep -o "reducers [0-9].*)" | sed 's|[^0-9]| |g;s|^ \+||;s| \+$||;s| |\n|g' | xargs -I{} echo "if [[ \"\$(tail -n3 {}/log/master.err | grep -o \"Access denied for user 'root'@'localhost'\")\" == \"Access denied for user 'root'@'localhost'\" ]]; then ${SCRIPT_PWD}/pquery-del-trial.sh {}; fi" > ${TMP_FILE_2} && chmod +x ${TMP_FILE_2} && ${TMP_FILE_2}
  # Russian
  rm -f ${TMP_FILE_2}
  ${HOME}/pr | grep "no core file found" | grep -o "reducers [0-9].*)" | sed 's|[^0-9]| |g;s|^ \+||;s| \+$||;s| |\n|g' | xargs -I{} echo "if [[ \"\$(tail -n3 {}/log/master.err | grep -o \"Доступ закрыт для пользователя 'root'@'localhost'\")\" == \"Доступ закрыт для пользователя 'root'@'localhost'\" ]]; then ${SCRIPT_PWD}/pquery-del-trial.sh {}; fi" > ${TMP_FILE_2} && chmod +x ${TMP_FILE_2} && ${TMP_FILE_2}
  # Cleanup
  rm -f ${TMP_FILE_2}
else
  echo "Warning: ${HOME}/pr not found, run ~/mariadb-qa/linkit please. This may have resulted in a small drop in functionality of this script (less than 10%)."
fi

# Delete all likely 'Server has gone away' 250x due to 'RELEASE' sql trials
# 25/01/2021 Temporarily disabled to see current results/status
# 02/04/2021 Found that regularly there are crashes w/o coredumps, so implemented fallback_text_string.sh call in
#            new_text_string.sh (where fallback_text_string.sh is the old text string script) for when there are
#            no coredumps but an error log is available. Evaluate performance over time, but this should be better.
#            Note that previously, for issues without coredump, but with 'signal' present in the error log, they
#            were marked as the '250x' and would result in 'Assert: no core...' by new_text_string.sh, and then
#            would be subsequently deleted by this script. Likely the following line cannot be re-enabled either (TBD)
# 20/12/2021 Note: see the new "Delete all trials which have "Access denied for user 'root'@'localhost'" on the last few lines of the error log" code above, which may in part cover the previous trials seen here
# 21/02/2022 Re-implemented deletion of 'Server has gone away' 250x due to 'RELEASE' sql trials after implementing a better/more reliable algo for disovering 'Server has gone away' trials (the 'MySQL server has gone away' has to come within 2 lines of an actual 'RELEASE' AND the pquery.log is checked for 'Last [0-9]\+ consecutive queries all failed'
${SCRIPT_PWD}/pquery-results.sh | grep -A1 "'Server has gone away' 250x" | tail -n1 | grep -o '[0-9, ]*' | tr -d ' ' | tr ',' '\n' | xargs -I{} ${SCRIPT_PWD}/pquery-del-trial.sh {}

# Delete all Handlerton. error == 0 trials  # Temp re-enabled in MariaDB to test (12/9/20)
# ${SCRIPT_PWD}/pquery-results.sh | grep "Handlerton. error == 0" | grep -o "reducers.*[^)]" | sed 's|reducers ||;s|,|\n|g' | xargs -I{} ${SCRIPT_PWD}/pquery-del-trial.sh {}

# Delete all trials which have a mysqld that terminated normally. As it uses 'tail -n2' from the outset, this will avoid trials with multiple startups (if any in the future, i.e. the initial init startup should already be seperate) from incorrectly being deleted. Updated 29/08/22 to ensure that trials which do have a core dump in spite of a seemingly normal shutdown are not deleted.
# 29/08/2021 Is this cleanup a bit too wide? - Even if core containing trials are excluded (as well as 'not freed' trials as they have 'not freed' in the last two lines rathar than 'Shutdown complete'), there are still other possible errors for example 'mysqld got error...' etc. Disabled FTM.
# tail -n2 */log/master.err | grep -B1 'Shutdown complete' | grep -o '==> [0-9]\+' | sed 's|.* ||' | xargs -I{} echo 'if [ "$(ls {}/data/core* 2>/dev/null | wc -l)" -eq 0 ]; then ${SCRIPT_PWD}/pquery-del-trial.sh {}; fi' | xargs -I{} bash -c "{}"

# Delete all 'TRIALS TO CHECK MANUALLY' trials which do not have an associated core file in their data directories
# Temporarily disabled this too (ref 02/04/2021 comment above)
# Re-enabled 27/8/22 - tempory test
rm -f ${TMP_FILE_1}
${SCRIPT_PWD}/pquery-results.sh | grep "TRIALS.*MANUALLY" | grep -o "reducers.*[^)]" | sed 's|reducers ||;s|,|\n|g' > ${TMP_FILE_1}
COUNT=$(wc -l ${TMP_FILE_1} 2>/dev/null | sed 's| .*||')
for RESULT in $(seq 1 ${COUNT}); do
  TRIAL="$(cat ${TMP_FILE_1} | head -n${RESULT} | tail -n1)"
  if [ $(ls ${RESULT}/data/*core* 2>/dev/null | wc -l) -lt 1 ]; then
    ${SCRIPT_PWD}/pquery-del-trial.sh ${TRIAL}
  fi
done
rm -f ${TMP_FILE_1}

echo "Done!"
