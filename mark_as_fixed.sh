#!/bin/bash

TMPRUN="$(mktemp)"
if [ -r mark_as_fixed.list ]; then
  grep 'Fixed' mark_as_fixed.list | grep -oE 'MENT-[0-9]+|MDEV-[0-9]+' > ${TMPRUN}
  while read BUG; do
    CURLINES="$(mktemp)"
    grep "${BUG}" known_bugs.strings | grep -v '## Fixed' > ${CURLINES}
    while read LINE; do
      LINEMOD="$(echo "${LINE}" | sed 's{         ## MDEV{## MDEV{;s{## MDEV{## Fixed MDEV{' | sed 's{^{# {')"  # { is not a symbol used in known bugs
      echo "${LINEMOD}" >> known_bugs.strings  # Add line to end as ## Fixed
      sed -i "{${LINE}{d" known_bugs.strings  # Remove the original line
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
