#!/bin/bash
# Created by Roel Van de Paar, Percona LLC

if [ "${STY}" == "" ]; then
  echo "NO"
else
  echo "YES: ${STY} window ${WINDOW:-0} on $(ps -o tty= -p $$ | tr -d ' ')"
fi
