#!/bin/bash
# Created by Roel Van de Paar, Percona LLC

# This script deletes all known found bugs from a pquery work directory. Execute from within the pquery workdir.

# Internal variables
SCRIPT_PWD="$(readlink -f "${0}" | sed "s|$(basename "${0}")||;s|/\+$||")"
set +H

# Check if this is a MariaDB Galera Cluster run
MDG=0
if [ "$(grep 'MDG Mode:' ./pquery-run.log 2>/dev/null | sed 's|^.*MDG Mode[: \t]*||' )" == "TRUE" ]; then
  MDG=1
fi

# Check if this is a group replication run
GRP_RPL=0
if [ "$(grep 'Group Replication Mode:' ./pquery-run.log 2>/dev/null | sed 's|^.*Group Replication Mode[: \t]*||')" == "TRUE" ]; then
  GRP_RPL=1
fi

# Check if this is a *SAN (ASAN, UBSAN, TSAN) run
SAN=0
if grep -Eq 'UBASAN_|TSAN_' ./pquery-run.log 2>/dev/null; then
  SAN=1
fi

# Current location checks
if [ `ls ./*/*.sql 2>/dev/null | wc -l` -eq 0 ]; then
  echo "Assert: no pquery trials (with logging - i.e. ./*/*.sql) were found in this directory (${PWD})"
  exit 1
fi

cleanup(){
  if [ -z "${STRINGS_FILE}" ]; then echo "Assert: \$STRINGS_FILE not seti. Verify code of this script as this should not happen"; exit 1; fi
  # Make sure known bug lists file does not contain a merge conflict
  CONFLICT=0
  if grep "^<<<<<<<" ${STRINGS_FILE} >/dev/null 2>&1; then CONFLICT=1; fi
  if grep "^=======" ${STRINGS_FILE} >/dev/null 2>&1; then CONFLICT=1; fi
  if grep "^>>>>>>>" ${STRINGS_FILE} >/dev/null 2>&1; then CONFLICT=1; fi
  if [ ${CONFLICT} -eq 1 ]; then
    echo "Assert: the known bug list filter file (${STRING_FILE}) contains a merge conflict!"
    echo "Not continuing as doing so may incorrectly delete various trials which should not be deleted"
    echo "Please scan the file for '<<<<<<<', '=======', and '>>>>>>>' strings"
    exit 1
  fi

  while read line; do
    STRING="$(echo "$line" | sed 's|[ \t]*##.*$||' |  sed 's|"|\\\"|g')"  # For more information on the " to \" sed, ref pquery-prep-red.sh (search for:  The sed transforms "  ), and pquery-results.sh (search for:  sed reverts the insertion of  ). Note there is one backslash less in this one
    if [ -z "${STRING}" ]; then continue; fi
    # echo "${STRING}..."  # For debugging
    # sleep 1  # For debugging
    if [ ! -z "$(echo "$STRING" | sed 's|^[ \t]*$||' | grep -v '^[ \t]*#')" ]; then
      if [ $(ls reducer[0-9]* 2>/dev/null | wc -l) -gt 0 ]; then
        # echo $STRING  # For debugging
        # sleep 1  # For debugging
        if [[ ${MDG} -eq 1 || ${GRP_RPL} -eq 1 ]]; then
  	      # grep -Fli "${STRING}" reducer[0-9]*  # For debugging (use script utility, then search for the reducer<nr>.sh in the typescript)
          if [ "${1}" == "1" ]; then
            grep -Fli --binary-files=text "${STRING}" reducer[0-9]* | awk -F'.'  '{print substr($1,8)}' | xargs -I{} $SCRIPT_PWD/pquery-del-trial.sh {} 1
          else
            grep -Fli --binary-files=text "${STRING}" reducer[0-9]* | awk -F'.'  '{print substr($1,8)}' | xargs -I{} $SCRIPT_PWD/pquery-del-trial.sh {}
          fi
        else
  	      # grep -Fli "${STRING}" reducer[0-9]*  # For debugging (use script utility, then search for the reducer<nr>.sh in the typescript)
          if [ "${1}" == "1" ]; then  # Also wipe trials which pquery-del-trial.sh would normal prevent from being deleted by the fact that they have error messages within them. This is used for when clean_all calls pquery-clean-all.sh which in turn calls this script. The "1" is passed in all cases, and here set to be the second option to pquery-del-trial thereby enabling pquery-del-trial to delete all trials. Note this does not delete all trials which have error log items in it, it only enables deleting trials which would normally be deleted by ./clean_all (i.e. they have a matched crash UniqueID in known_bugs.strings) and happen to have an error log string as well.
            grep -Fli --binary-files=text "${STRING}" reducer[0-9]* | sed 's/[^0-9]//g' | xargs -I{} ${SCRIPT_PWD}/pquery-del-trial.sh {} 1
          else
            grep -Fli --binary-files=text "${STRING}" reducer[0-9]* | sed 's/[^0-9]//g' | xargs -I{} ${SCRIPT_PWD}/pquery-del-trial.sh {}
          fi
        fi
      fi
    fi
    #sync; sleep 0.02  # Making sure that next line in file does not trigger same deletions
  done < ${STRINGS_FILE}
}

STRINGS_FILE=${SCRIPT_PWD}/known_bugs.strings  # All normal bugs (CS/ES/MDG). This will always run (i.e. even for *SAN runs)
cleanup
if [ "${SAN}" -eq 1 ]; then
  STRINGS_FILE=${SCRIPT_PWD}/known_bugs.strings.SAN  # All *SAN bugs(ASAN/TSAN/UBSAN) (CS/ES/MDG)
  cleanup
fi

# Other cleanups
if [ ${MDG} -ne 1 ]; then
  grep "CT NAME_CONST('a', -(1 [ANDOR]\+ 2)) [ANDOR]\+ 1" */log/master.err 2>/dev/null | sed 's|/.*||' | xargs -I{} ~/mariadb-qa/pquery-del-trial.sh {}  #http://bugs.mysql.com/bug.php?id=81407
fi

# Delete trials which have a corrupted index (error 126) as main outcome/uniqueID, almost surely caused by enabling aria_encrypt_tables without correct setup
${HOME}/pr | grep -m1 'GOT_ERROR|Got error 126|Index is corrupted' | grep -o 'times: reducers.*' | tr ',' '\n' | grep -o '[0-9]\+' | xargs -I{} grep --binary-files=text -iEl 'aria_encrypt_tables[ \t]*=[ \t]*1|aria_encrypt_tables[ \t]*=[ \t]*ON' {}/default.node.tld_thread-0.sql | grep -o '^[0-9]\+' | xargs -I{} ${HOME}/dt {} 1

# Check if this an automated (pquery-reach.sh or /data/clean_all) run, which should have no output
if [ "${1}" != "reach" ]; then
  if [ -d ./bundles ]; then
    echo "Done! Any trials in ./bundles were not touched. Any Valgrind trials were not touched."
  else
    echo "Done!"
  fi
fi
