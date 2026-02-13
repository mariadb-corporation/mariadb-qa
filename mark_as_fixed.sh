#!/bin/bash

# Filter files and corresponding keys
FILES=(
  "$HOME/mariadb-qa/ASAN.filter"
  "$HOME/mariadb-qa/UBSAN.filter"
  "$HOME/mariadb-qa/filter.sql.info"
  "$HOME/mariadb-qa/REGEX_ERRORS_FILTER.info"
)
FILE_KEYS=(
  "CHECK_ASAN_FILTER_FILE"
  "CHECK_UBSAN_FILTER_FILE"
  "CHECK_FILTER_INFO_FILE"
  "CHECK_REGEX_FILTER_INFO_FILE"
)

# Array to hold matched bugs
MATCHED_BUGS=("" "" "" "")

# Temporary file to hold fixed bugs
TMPRUN=$(mktemp)

if [[ ! -r "mark_as_fixed.list" ]]; then
  echo "Error: mark_as_fixed.list not found"
  exit 1
fi

# Extract fixed bug IDs
grep 'Fixed' mark_as_fixed.list | grep -oE 'MENT-[0-9]+|MDEV-[0-9]+' > "$TMPRUN"

while read -r BUG; do
  # Temporary files for current bug lines
  KB_CURLINES=$(mktemp)
  KBS_CURLINES=$(mktemp)

  grep "$BUG" known_bugs.strings | grep -v '## Fixed' > "$KB_CURLINES"
  grep "$BUG" known_bugs.strings.SAN | grep -v '## Fixed' > "$KBS_CURLINES"

  update_fixed_bugs(){
    local tmp_file=$1
    local kb_file=$2
    while read -r LINE; do
      # Modify line to mark it as fixed
      if [[ "$BUG" =~ MDEV ]]; then
        LINEMOD=$(echo "$LINE" | sed 's{           ## MDEV{## MDEV{;s{## MDEV{## Fixed ## MDEV{' | sed 's{^{# {')
      else
        LINEMOD=$(echo "$LINE" | sed 's{           ## MENT{## MENT{;s{## MENT{## Fixed ## MENT{' | sed 's{^{# {')
      fi
      
      # Add modified line to KB_FILE
      echo "$LINEMOD" >> "$kb_file"

      # Remove original line safely
      ESCAPED_LINE="${LINE//|/\\|}"
      sed -i "\|$ESCAPED_LINE|d" "$kb_file"
    done < "$tmp_file"  
  }
  
  # Update fixed bugs in kb/kbs
  update_fixed_bugs "$KB_CURLINES" known_bugs.strings
  update_fixed_bugs "$KBS_CURLINES" known_bugs.strings.SAN

  # Cleanup temp files
  rm -f "$KB_CURLINES" "$KBS_CURLINES"

  # Check which filter files contain this bug
  for i in "${!FILES[@]}"; do
    if grep -qi "$BUG" "${FILES[$i]}"; then
      MATCHED_BUGS[$i]="${MATCHED_BUGS[$i]}$BUG "
    fi
  done
done < "$TMPRUN"

rm -f "$TMPRUN"

# Print all matched bugs per file
for i in "${!FILES[@]}"; do
  bugs=$(echo "${MATCHED_BUGS[$i]}" | xargs)  # remove extra spaces
  [[ -z "$bugs" ]] && continue

  if [[ "${FILE_KEYS[$i]}" == "CHECK_FILTER_INFO_FILE" ]]; then
    echo "Note: Fixed BUG/BUGS $bugs also found in ${FILES[$i]} – please update that file, as well as $HOME/mariadb-qa/filter.sql, manually."
  else
    echo "Note: Fixed BUG/BUGS $bugs also found in ${FILES[$i]} – please update that file manually."
  fi
done
