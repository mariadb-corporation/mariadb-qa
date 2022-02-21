#!/bin/bash
# Created by Roel Van de Paar, Percona LLC
# Updated by Roel Van de Paar, MariaDB
# Note that running this script does not execute pquery-clean-known.sh - run that script seperately as well, before or after this one

SCRIPT_PWD=$(cd "`dirname $0`" && pwd)
echo "Extra cleaning up of known issues++ (expert mode)..."

# Delete all known bugs which do not correctly produce unique bug ID's due to stack smashing etc.
# grep 'Assertion .state_ == s_exec || state_ == s_quitting. failed.' */log/master.err 2>/dev/null | sed 's|^\([0-9]\+\)/.*|\1|' | grep -o '[0-9]\+' | xargs -I{} ${SCRIPT_PWD}/pquery-del-trial.sh {}  # MDEV-22148 # Fixed
# grep 'Assertion .thd->transaction->stmt.is_empty() || thd->in_sub_stmt. failed.' */log/master.err 2>/dev/null | sed 's|^\([0-9]\+\)/.*|\1|' | grep -o '[0-9]\+' | xargs -I{} ${SCRIPT_PWD}/pquery-del-trial.sh {}  # MDEV-22726 # Fixed

# Delete all likely out of disk space trials
${SCRIPT_PWD}/pquery-results.sh | grep -A1 "Likely out of disk space trials" | \
 tail -n1 | tr ' ' '\n' | grep -v "^[ \t]*$" | xargs -I{} ${SCRIPT_PWD}/pquery-del-trial.sh {}

# Delete all trials which have "Access denied for user 'root'@'localhost'" on the last few lines of the error log and that have no core file
if [ -r /home/$(whoami)/pr ]; then
  rm -f ./temp_pck++.sh
  /home/$(whoami)/pr | grep "no core file found" | grep -o "reducers [0-9].*)" | sed 's|[^0-9]| |g;s|^ \+||;s| \+$||;s| |\n|g' | xargs -I{} echo "if [[ \"\$(tail -n3 {}/log/master.err | grep -o \"Access denied for user 'root'@'localhost'\")\" == \"Access denied for user 'root'@'localhost'\" ]]; then ~/dt {}; fi" > ./temp_pck++.sh && chmod +x ./temp_pck++.sh && ./temp_pck++.sh
  rm -f ./temp_pck++.sh
else
  echo "Warning: /home/$(whoami)/pr not found, run ~/mariadb-qa/linkit please. This may have resulted in a small drop in functionality of this script (less than 10%)."
fi

# Delete all likely 'Server has gone away' 250x due to 'RELEASE' sql trials
# 25/01/2021 Temporarily disabled to see current results/status
# 02/04/2021 Found that regularly there are crashes w/o coredumps, so implemented falllback_text_string.sh call in
#            new_text_string.sh (where falllback_text_string.sh is the old text string script) for when there are
#            no coredumps but an error log is available. Evaluate performance over time, but this should be better.
#            Note that previously, for issues without coredump, but with 'signal' present in the error log, they
#            were marked as the '250x' and would result in 'Assert: no core...' by new_text_string.sh, and then
#            would be subsequently deleted by this script. Likely the following line cannot be re-enabled either (TBD)
# 20/12/2021 Note: see the new "Delete all trials which have "Access denied for user 'root'@'localhost'" on the last few lines of the error log" code above, which may in part cover the previous trials seen here
# 21/02/2022 Re-implemented deletion of 'Server has gone away' 250x due to 'RELEASE' sql trials after implementing a better/more reliable algo for disovering 'Server has gone away' trials (the 'MySQL server has gone away' has to come within 2 lines of an actual 'RELEASE' AND the pquery.log is checked for 'Last [0-9]\+ consecutive queries all failed'
${SCRIPT_PWD}/pquery-results.sh | grep -A1 "'Server has gone away' 250x" | tail -n1 | grep -o '[0-9, ]*' | tr -d ' ' | tr ',' '\n' | xargs -I{} ${SCRIPT_PWD}/pquery-del-trial.sh {}

# Delete all Handlerton. error == 0 trials  # Temp re-enabled in MariaDB to test (12/9/20)
# ${SCRIPT_PWD}/pquery-results.sh | grep "Handlerton. error == 0" | grep -o "reducers.*[^)]" | sed 's|reducers ||;s|,|\n|g' | xargs -I{} ${SCRIPT_PWD}/pquery-del-trial.sh {}

# Delete all trials which have a mysqld that terminated normally. As it uses 'tail -n2' from the outset, this will avoid trials with multiple startups (if any in the future, i.e. the initial init startup should already be seperate) from incorrectly being deleted.
tail -n2 */log/master.err | grep -B1 'Shutdown complete' | grep -o '==> [0-9]\+' | sed 's|.* ||' | xargs -I{} ${SCRIPT_PWD}/pquery-del-trial.sh {}

# Delete all 'TRIALS TO CHECK MANUALLY' trials which do not have an associated core file in their data directories
# Temporarily disabled this too (ref 02/04/2021 comment above)
#rm -f ~/results_list++.tmp
#${SCRIPT_PWD}/pquery-results.sh | grep "TRIALS.*MANUALLY" | grep -o "reducers.*[^)]" | sed 's|reducers ||;s|,|\n|g' > ~/results_list++.tmp
#COUNT=$(wc -l ~/results_list++.tmp 2>/dev/null | sed 's| .*||')
#for RESULT in $(seq 1 ${COUNT}); do
#  if [ $(ls ${RESULT}/data/*core* 2>/dev/null | wc -l) -lt 1 ]; then
#    ${SCRIPT_PWD}/pquery-del-trial.sh ${RESULT}
#  fi
#done
#rm -f ~/results_list++.tmp

echo "Done!"
