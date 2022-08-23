#!/bin/bash

TOTAL="$(grep -oE 'MDEV-[0-9]+|MENT-[0-9]+' known_bugs.strings | sort -u | wc -l)"
MENT="$(grep -oE 'MENT-[0-9]+' known_bugs.strings | sort -u | wc -l)"
MDEV="$(grep -oE 'MDEV-[0-9]+' known_bugs.strings | sort -u | wc -l)"

echo "MDEV: ${MDEV} + MENT: ${MENT} = TOTAL: ${TOTAL}"
