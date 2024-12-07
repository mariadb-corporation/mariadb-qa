#!/bin/bash
# Created by Roel Van de Paar, MariaDB

# This script drops the first (and possibly subsequent; read below) *SAN bug(s)/issue(s) from the error log, provided it is a/are known issue(s), thereby enabling subsequent (and potentially as yet unknown) *SAN bugs/issues to be handled
# This greatly improves pquery-run.sh runs, for example, enabling known bugs/issues to be all removed from logs. Note that if MYBUG is present, it is also auto-updated to reflect the new top-level issue in the error log
# If the first issue was known, the script also loops until a non-known (or no) issue/bug was found
# One major benefit of this approach/script is that it is impervious to:
# 1) Issues filtered through *SAN filters, for example mariadb-qa/UBSAN.filter, but still present in the error log. For example due to an optimized build being used and a function not being correctly filtered by UBSAN suppression filtering (which is limited/has shortcomings), versus
# 2) Issues customarily filtered through mariadb-qa/new_text_string.sh, as these issues (read: 'such trials') would be eliminated/deleted due to the issue being recognized as a known one
# If an issue shows (i.e. it is not suppressed by #1 above), and it is a known issue (as reported by #2 above), it will be removed, leaving the next issue available for analysis, if any
# Optionally/alternatively passing any value as the first option will delete the first *SAN occurence even if not recognized as a known bug. Additionally, passing any value as the secont option will use the slave error log instead

SCRIPT_PWD=$(dirname $(readlink -f "${0}"))
START_STRING='=ERROR:\|runtime error:\|AddressSanitizer:\|ThreadSanitizer:\|LeakSanitizer:\|MemorySanitizer:'
START_STRING_GREP="$(echo "${START_STRING}" | sed 's|\\||g')"
END_STRING='^SUMMARY:'

del_first_san_issue(){
  if [ -r "${1}" ]; then
    sed -i -e "0,/$END_STRING/{/$START_STRING/,/$END_STRING/d}" "${1}"  # In between ({...}) the first line (0,) and the first END_STRING, delete the START_STRING...END_STRING block (d). This ensures only the first *SAN block is deleted inline (-i) using exected regex (-e) given the multi-start strings in START_STRING (neeed to be separated by '\|')
    if [ -r ./MYBUG -o -r ./pquery.log -o -r ./MYEXTRA -o -r ./MYEXTRA -o -r ./ERROR_LOG_SCAN_ISSUE ]; then  # If present, update MYBUG to match the new top issue. If not present, and this is a pquery trial (as validated by any of the other checks), add it
      rm -f ./MYBUG
      ${SCRIPT_PWD}/new_text_string.sh > ./MYBUG
      if [ "${2}" == "${AKB}" ]; then
        touch ./TOP_SAN_ISSUES_REMOVED
      fi
    fi
  fi
}

del_known_san_issues(){
  if [ -r "${1}" ]; then
    if grep --binary-files=text -qiE "${START_STRING_GREP}" "${1}"; then  # Avoid much work if no *SAN issue is present
      # Loop till a new/unknown (or no) issue/bug is found
      while [ "$(${SCRIPT_PWD}/homedir_scripts/tt | grep -o '^ALREADY KNOWN BUG' | head -n1)" == "ALREADY KNOWN BUG" ]; do
        if [ ! -r "${1}.pre_known_san_removal" ]; then
          cp "${1}" "${1}.pre_known_san_removal"
        fi
        del_first_san_issue "${1}" "AKB"
      done
    fi
  fi
}

if [ ! -z "${1}" ]; then
  del_first_san_issue "./log/master.err"
  if [ ! -z "${2}" ]; then
    del_first_san_issue "./log/slave.err"
  fi
else
  del_known_san_issues "./log/master.err"
  del_known_san_issues "./log/slave.err"
fi
