#!/bin/bash
# Created by Roel Van de Paar, Percona LLC

# This script deletes all known found bugs from a pquery work directory. Execute from within the pquery workdir.

# Internal variables
SCRIPT_PWD=$(dirname $(readlink -f "${0}"))
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

# Check if this is a *SAN (ASAN, UBSAN, TSAN, MSAN) run
SAN=0
if grep -Eq 'UBASAN_|TSAN_|MSAN_' ./pquery-run.log 2>/dev/null; then
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
    echo "Please search the file for '<<<<<<<', '=======', and '>>>>>>>' strings"
    exit 1
  fi

  # Nothing to match against, so nothing to delete
  if [ $(ls reducer[0-9]* 2>/dev/null | wc -l) -eq 0 ]; then return; fi

  # The bug list is turned into a plain list of search strings once, then handed to a
  # single grep. A pass per string costs about a dozen processes each, and at ~1500
  # strings in every workdir that was the bulk of what this script took. The leading
  # and trailing whitespace strip matches what "read" did per line. For more
  # information on the " to \" sed, ref pquery-prep-red.sh (search for:  The sed
  # transforms "  ), and pquery-results.sh (search for:  sed reverts the insertion of
  # ). Note there is one backslash less in this one
  STRINGS_CLEAN="$(mktemp)" || return
  sed 's|^[ \t]*||;s|[ \t]*$||' ${STRINGS_FILE} | sed 's|[ \t]*##.*$||' | sed 's|"|\\\"|g' | grep -v '^#' | grep -v '^$' > "${STRINGS_CLEAN}"
  if [ -s "${STRINGS_CLEAN}" ]; then
    # -f reads every string at once and names the reducers any of them matched, which
    # is the same set of trials the per-string passes deleted, each named once
    if [[ ${MDG} -eq 1 || ${GRP_RPL} -eq 1 ]]; then
      TRIALS_MATCHED="$(grep -Flif "${STRINGS_CLEAN}" --binary-files=text reducer[0-9]* 2>/dev/null | awk -F'.' '{print substr($1,8)}' | sort -un)"
    else
      TRIALS_MATCHED="$(grep -Flif "${STRINGS_CLEAN}" --binary-files=text reducer[0-9]* 2>/dev/null | sed 's/[^0-9]//g' | sort -un)"
    fi
    if [ "${1}" == "1" ]; then  # Also wipe trials which pquery-del-trial.sh would normally prevent from being deleted by the fact that they have error messages within them. This is used for when clean_all calls pquery-clean-all.sh which in turn calls this script. The "1" is passed in all cases, and here set to be the second option to pquery-del-trial thereby enabling pquery-del-trial to delete all trials. Note this does not delete all trials which have error log items in it, it only enables deleting trials which would normally be deleted by ./clean_all (i.e. they have a matched crash UniqueID in known_bugs.strings) and happen to have an error log string as well.
      printf '%s\n' "${TRIALS_MATCHED}" | grep -v '^$' | xargs -I{} ${SCRIPT_PWD}/pquery-del-trial.sh {} 1
    else
      printf '%s\n' "${TRIALS_MATCHED}" | grep -v '^$' | xargs -I{} ${SCRIPT_PWD}/pquery-del-trial.sh {}
    fi
    TRIALS_MATCHED=
  fi
  rm -f "${STRINGS_CLEAN}"
  STRINGS_CLEAN=
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

# Check if this is a ca (/data/clean_all) run, which should include the path
CA_PREFIX=
if [ "${CA_ACTIVE}" == "1" ]; then
  CA_PREFIX="   ...$(echo "${PWD}" | sed 's|.*/||'): "
fi
# Check if this an automated (pquery-reach.sh or /data/clean_all) run, which should have no output
if [ "${1}" != "reach" ]; then
  if [ -d ./bundles ]; then
    echo "${CA_PREFIX}Done! Any trials in ./bundles were not touched. Any Valgrind trials were not touched."
  else
    echo "${CA_PREFIX}Done!"
  fi
fi
