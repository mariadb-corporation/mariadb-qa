#!/bin/bash

SCRIPT_PWD=$(dirname $(readlink -f "${0}"))

mkdir -p known mysql_bugs debug_dbug NOCORE

# Move MySQL bugs to a seperate directory
grep --binary-files=text -A2 -i "Bug confirmed present in" *.report 2>/dev/null | grep --binary-files=text -i 'MySQL' | sed 's|\..*||' | sort -u | xargs -I{} mv "{}.sql" "{}.sql.report" "{}.sql.report.NOCORE" mysql_bugs 2>/dev/null

# Move bugs which were already found to be dups (and are not fixed yet) by mass_bug_report.sh
grep --binary-files=text -oi "FOUND: This is an already known bug, and not fixed yet" *.report 2>/dev/null | sed 's|\..*||' | sort -u | xargs -I{} mv "{}.sql" "{}.sql.report" "{}.sql.report.NOCORE" known 2>/dev/null

# Move testcases which have debug_dbug into debug_dbug directory for later research
grep --binary-files=text -oi "debug_dbug" *.report 2>/dev/null | sed 's|\..*||' | sort -u | xargs -I{} mv "{}.sql" "{}.sql.report" "{}.sql.report.NOCORE" debug_dbug 2>/dev/null

# Move testcases which did not produce a core on ANY basedir
grep --binary-files=text -oi "^TOTAL CORES SEEN ACCROSS ALL VERSIONS: 0$" *.report 2>/dev/null | sed 's|\..*||' | sort -u | xargs -I{} mv "{}.sql" "{}.sql.report" "{}.sql.report.NOCORE" NOCORE 2>/dev/null

# Move bugs which have since been logged and/or are dups
grep --binary-files=text -A1 -i "Add bug to known.strings" *.sql.report 2>/dev/null | grep --binary-files=text -v "\-\-" | grep --binary-files=text -vEi "Add bug to known.strings|Check for duplicates before logging bug" > /tmp/tmpdups.list 2>/dev/null
COUNT=$(wc -l /tmp/tmpdups.list 2>/dev/null | sed 's| .*||')

if [ ${COUNT} -gt 0 ]; then
  LINE=0
  while :; do
    LINE=$[ ${LINE} + 1 ]
    if [ ${LINE} -gt ${COUNT} ]; then break; fi
    SCAN="$(head -n${LINE} /tmp/tmpdups.list | tail -n1)"
    FILE="$(echo "${SCAN}" | sed 's|sql\.report-.*|sql.report|')"
    TEXT="$(echo "${SCAN}" | sed 's|.*sql\.report-||')"
    set +H  # Disables history substitution and avoids  -bash: !: event not found  like errors
    FINDBUG="$(set +H; grep -Fi --binary-files=text "${TEXT}" ${SCRIPT_PWD}/known_bugs.strings)"
    if [ "${1}" == "" ]; then  # Allows one to quickly cleanup all fixed bugs also - handy when dealing with many testcases and a good number of recent bugfixes. Not perfect, so optional.
      if [ "$(echo "${FINDBUG}" | sed 's|[ \t]*\(.\).*|\1|')" == "#" ]; then FINDBUG=""; fi  # Bugs marked as fixed need to be excluded. This cannot be done by using "^${TEXT}" as the grep is not regex aware, nor can it be, due to the many special (regex-like) characters in the unique bug strings
    fi
    if [ ! -z "${FINDBUG}" ]; then
      NR="$(echo "${FILE}" | sed 's|\.sql\.report||')"
      if [ -r ${NR}.sql.report.NOCORE ]; then
        mv "${NR}.sql" "${NR}.sql.report" "${NR}.sql.report.NOCORE" known
      else
        mv "${NR}.sql" "${NR}.sql.report" known
      fi
    fi
    FINDBUG=
  done
fi
