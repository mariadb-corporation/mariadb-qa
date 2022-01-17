#!/bin/bash
# Quickly shows which CLI's may be hanging (handy when running ~/b and it is stuck)
# The 'prompt' exclusion ensures no interactive CLI's are included
ps -ef | grep 'bin/mysql ' | grep '/test' | grep 'force' | grep -v 'prompt' | grep -o '/test/.*' | sort -u
