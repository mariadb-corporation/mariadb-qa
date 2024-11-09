#!/bin/bash
# Quickly shows which CLI's may be hanging (handy when running ~/b and it is stuck)
# The 'prompt' exclusion ensures no interactive CLI's are included
ps -ef | grep -E 'bin/mysql |bin/mariadb ' | grep '/test' | grep 'force' | grep -v 'prompt' | grep -o '/test/.*' | grep -v 'reducer' | sort -u
