#!/bin/bash
# Note that a later full branch, like 11.5, can be used to check all branches in which a patch is present
if [ -z "${1}" ]; then echo 'Please pass a commit ID, and make sure you are inside a full (git branch) clone dir'; exit 1; fi
git branch -r --contain "${1}"
