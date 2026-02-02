#!/bin/bash

echo 'Use of this script is reserved to MariaDB employees!'
echo 'Press enter 3x to confirm you are an authorized MariaDB employee...'
read -p '1x...'
read -p '2x...'
read -p '3x...'

# Note that lines starting with '#' are not filtered, as regularly bug filters are disabled to avoid missing other bugs
# Instead, only 'fixed' (and empty lines) in the known bugs list are filtered, as the former are bugs which are truly fixed
# This may sometimes also scan a bug number which is mentioned in a ##### header, but his is quite fine and can be informative
# The script also checks the web version for both 'Fixed' and 'Duplicate' resolutions, though the latter may sometimes mean
# that the duplicated/original/main bug was not fixed yet. Do *not* mark those as '## Fixed' please
grep --binary-files=text -vEi '^[ \t]*$|fixed|no parsable frames' ${HOME}/mariadb-qa/known_bugs.strings ${HOME}/mariadb-qa/known_bugs.strings.SAN ${HOME}/mariadb-qa/REGEX_ERRORS_FILTER.info ${HOME}/mariadb-qa/UBSAN.filter ${HOME}/mariadb-qa/ASAN.filter ${HOME}/mariadb-qa/filter.sql.info | grep --binary-files=text -Eo 'MDEV-[0-9]+|MENT-[0-9]+' | sort -u | wc -l | sed 's|^|Scanning |;s|$| bugs...|'
echo "Only bugs which are fixed will be listed below, so they can be updated (add leading '# ' and '## Fixed' before MDEV number) in ${HOME}/mariadb-qa/known_bugs.strings and/or ${HOME}/mariadb-qa/known_bugs.strings.SAN and/or ${HOME}/mariadb-qa/REGEX_ERRORS_FILTER.info:"
grep --binary-files=text -vEi '^[ \t]*$|fixed|no parsable frames' ${HOME}/mariadb-qa/known_bugs.strings ${HOME}/mariadb-qa/known_bugs.strings.SAN ${HOME}/mariadb-qa/REGEX_ERRORS_FILTER.info ${HOME}/mariadb-qa/UBSAN.filter ${HOME}/mariadb-qa/ASAN.filter ${HOME}/mariadb-qa/filter.sql.info | grep --binary-files=text -Eo 'MDEV-[0-9]+|MENT-[0-9]+' | sort -u | xargs -I{} echo "lynx -accept_all_cookies -dump -nobold -nobrowse -nolist -nolog -nomargins -nomore -nopause -noprint -nostatus https://jira.mariadb.org/browse/{} | grep -o 'Resolution: .*' | sed 's|Resolution:[ \\t]\\+||;s|^|{}: |' | grep  --binary-files=text -Ei 'Fixed|Duplicate'; sleep 1" > /tmp/check_bug_status.tsh
chmod +x /tmp/check_bug_status.tsh
/tmp/check_bug_status.tsh
rm -f /tmp/check_bug_status.tsh
