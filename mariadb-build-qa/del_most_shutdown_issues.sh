#!/bin/bash
# This script deletes most shutdown timeout issue trials in all workdirs, except those with trial number 1 to 39 (i.e. leaving some). If there are many issues, clearly more will left. This script can be used when /data space is low
ls [0-9]*/[0-9]*/SHUTDOWN_TIMEOUT_ISSUE | sed 's|/SHUTDOWN_TIMEOUT_ISSUE||' | sed 's|^|cd |;s|/|;~/dt |;s|$|;cd - >/dev/null|' | grep -vE 'dt [0];|dt [0-3][0-9];' | grep -vE '^[ \t]*$' | tr '\n' '\0' | xargs -0 -I{} bash -c "{}"

# If not feature testing, and no important save workdirs exist, you can delete ALL shutdown timeout issues using:
# ls [0-9]*/[0-9]*/SHUTDOWN_TIMEOUT_ISSUE | sed 's|/SHUTDOWN_TIMEOUT_ISSUE||' | sed 's|^|cd |;s|/|;~/dt |;s|$|;cd - >/dev/null|' | tr '\n' '\0' | xargs -0 -I{} bash -c "{}"
