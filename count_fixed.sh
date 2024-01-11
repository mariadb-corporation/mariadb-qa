grep 'Fixed' known_bugs.strings.SAN known_bugs.strings  | grep -oE 'MDEV-[0-9]+|MENT-[0-9]+' | sort -u | wc -l
