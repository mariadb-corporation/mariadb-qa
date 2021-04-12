#!/bin/bash
# Created by Roel Van de Paar, Percona LLC
# Updated by Roel Van de Paar, MariaDB
# Note that running this script does not execute pquery-clean-known.sh - run that script seperately as well, before or after this one

SCRIPT_PWD=$(cd "`dirname $0`" && pwd)
echo "Extra cleaning up of known issues++ (expert mode)..."

# Delete all known bugs which do not correctly produce unique bug ID's due to stack smashing etc
grep 'Assertion .state_ == s_exec || state_ == s_quitting. failed.' */log/master.err 2>/dev/null | sed 's|^\([0-9]\+\)/.*|\1|' | grep -o '[0-9]\+' | xargs -I{} ${SCRIPT_PWD}/pquery-del-trial.sh {}  # MDEV-22148
grep 'Assertion .thd->transaction->stmt.is_empty() || thd->in_sub_stmt. failed.' */log/master.err 2>/dev/null | sed 's|^\([0-9]\+\)/.*|\1|' | grep -o '[0-9]\+' | xargs -I{} ${SCRIPT_PWD}/pquery-del-trial.sh {}  # MDEV-22726

# Delete all likely out of disk space trials
${SCRIPT_PWD}/pquery-results.sh | grep -A1 "Likely out of disk space trials" | \
 tail -n1 | tr ' ' '\n' | grep -v "^[ \t]*$" | xargs -I{} ${SCRIPT_PWD}/pquery-del-trial.sh {}

# Delete all likely 'Server has gone away' 200x due to 'RELEASE' sql trials
# 25/01/2021 Temporarily disabled to see current results/status
# 02/04/2021 Found that regularly there are crashes w/o coredumps, so implemented falllback_text_string.sh call in
#            new_text_string.sh (where falllback_text_string.sh is the old text string script) for when there are
#            no coredumps but an error log is available. Evaluate performance over time, but this should be better.
#            Note that previously, for issues without coredump, but with 'signal' present in the error log, they
#            were marked as the '200x' and would result in 'Assert: no core...' by new_text_string.sh, and then
#            would be subsequently deleted by this script. Likely the following line cannot be re-enabled either (TBD)
#${SCRIPT_PWD}/pquery-results.sh | grep -A1 "Likely 'Server has gone away' 200x due to 'RELEASE' sql" | tail -n1 | tr ' ' '\n' | grep -v "^[ \t]*$" | xargs -I{} ${SCRIPT_PWD}/pquery-del-trial.sh {}

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
