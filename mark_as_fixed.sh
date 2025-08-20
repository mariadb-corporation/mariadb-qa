#!/bin/bash
KB_FILE=$1
  if [ -r $KB_FILE ]; then
else
  echo "$KB_FILE not found"
  exit 1
fi

TMPRUN="$(mktemp)"
if [ -r mark_as_fixed.list ]; then
  grep 'Fixed' mark_as_fixed.list | grep -oE 'MENT-[0-9]+|MDEV-[0-9]+' > ${TMPRUN}
  while read BUG; do
    CURLINES="$(mktemp)"
    grep "${BUG}" $KB_FILE | grep -v '## Fixed' > ${CURLINES}
    while read LINE; do
      LINEMOD="$(echo "${LINE}" | sed 's{         ## MDEV{## MDEV{;s{## MDEV{## Fixed ## MDEV{' | sed 's{^{# {')"  # { is not a symbol used in known bugs
      echo "${LINEMOD}" >> $KB_FILE # Add line to end as ## Fixed
      ESCAPED_LINE="${LINE//|/\\|}"
      sed -i "\|${ESCAPED_LINE}|d" $KB_FILE # Remove the original line
      LINE=; LINEMOD=
    done < ${CURLINES}
    if [ ! -z "${CURLINES}" -a -r "${CURLINES}" ]; then rm -f ${CURLINES}; fi
    BUG=
  done < ${TMPRUN}
  if [ ! -z "${TMPRUN}" -a -r "${TMPRUN}" ]; then rm -f ${TMPRUN}; fi
  exit 0
else
  echo 'mark_as_fixed.list not found'
  exit 1
fi
