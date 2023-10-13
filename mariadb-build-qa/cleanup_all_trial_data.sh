#!/bin/bash
# This script cleans up all likely-unecessary files in all trial's data dirs. It leaves cores
# This can be very handy when space is running low on the instance

cd /data
if [ "${PWD}" == "/test" ]; then
  echo 'Assert: PWD is /test, you will likely want to use ./del_all_data instead'
  exit 1
elif [ "${PWD}" != "/data" ]; then
  echo "Not in /data? (${PWD})"
  exit 1
fi

find /data/[0-9][0-9][0-9][0-9][0-9][0-9]/[0-9]*/data/ -type f -not -name '*core*' -print0 | xargs -0 -I {} rm -f {} 2>/dev/null  # The stderr redirect is for files which have been cleanup while this script was running (like pquery-del-trial.sh which is called by various scripts)

rmdir /data/[0-9][0-9][0-9][0-9][0-9][0-9]/[0-9]*/data/* 2>/dev/null  # Cleanup empty directories
