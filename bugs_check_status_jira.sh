#!/bin/bash

echo 'Use of this script is reserved to MariaDB employees!'
echo 'Press enter 3x to confirm you are an authorized MariaDB employee...'
read -p '1x...'
read -p '2x...'
read -p '3x...'

grep --binary-files=text -vE '^#|^[ \t]*$|Fixed' ~/mariadb-qa/known_bugs.strings | grep --binary-files=text -Eo 'MDEV-[0-9]+|MENT-[0-9]+' | sort -u | wc -l | sed 's|^|Scanning |;s|$| bugs...|'
echo "Only bugs which are fixed will be listed below, so they can be removed from known_bugs.strings:"
grep --binary-files=text -vE '^#|^[ \t]*$|Fixed' ~/mariadb-qa/known_bugs.strings | grep --binary-files=text -Eo 'MDEV-[0-9]+|MENT-[0-9]+' | sort -u | xargs -I{} echo "lynx -accept_all_cookies -dump -nobold -nobrowse -nolist -nolog -nomargins -nomore -nopause -noprint -nostatus https://jira.mariadb.org/browse/{} | grep -o 'Resolution: .*' | sed 's|Resolution:[ \\t]\\+||;s|^|{}: |' | grep 'Fixed'; sleep 1" > /tmp/check_bug_status.tsh
chmod +x /tmp/check_bug_status.tsh
/tmp/check_bug_status.tsh
rm -f /tmp/check_bug_status.tsh
