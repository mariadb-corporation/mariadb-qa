#!/bin/bash
# Note that a later full branch, like 11.5, can be used to check all branches in which a patch is present
# ^ Correct or incorrect? i.e. if an upmerge has not happened to for example 11.5, but a patch is in 11.4 would it show in 11.5 as base?
if [ -z "${1}" ]; then echo 'Please pass a commit ID, and make sure you are inside a full (git branch) clone dir'; exit 1; fi
git branch -r --contain "${1}"
