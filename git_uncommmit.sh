#!/bin/bash

# Uncommits the current, non-pushed commit (i.e. a git uncommit after doing git commit) - ideal when you want to change the commit message, or change the code
git reset HEAD~1

# To do the same, but leave the changes in the staging area (i.e. like a git commit -a ...) ready to push - ideal when you want to change the commit message only
# git reset --soft HEAD~1
