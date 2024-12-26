#!/bin/bash

# Read the version from the VERSION file
VERSION_FILE="VERSION"
if [[ ! -f $VERSION_FILE ]]; then
  echo "Error: $VERSION_FILE not found!"
  exit 1
fi

# Extract major and minor versions from the VERSION file
MAJOR_VERSION=$(grep "MYSQL_VERSION_MAJOR" $VERSION_FILE | cut -d= -f2)
MINOR_VERSION=$(grep "MYSQL_VERSION_MINOR" $VERSION_FILE | cut -d= -f2)

# Handle the case for 11.0
if [[ $MAJOR_VERSION -eq 11 && $MINOR_VERSION -eq 0 ]]; then
  BASE_BRANCH="origin/10.11"
else
  # Calculate the base branch (e.g., 11.7 -> 11.6, 10.6 -> 10.5)
  if [[ $MINOR_VERSION -gt 0 ]]; then
    BASE_MINOR_VERSION=$((MINOR_VERSION - 1))
    BASE_BRANCH="origin/$MAJOR_VERSION.$BASE_MINOR_VERSION"
  else
    # If minor version is 0, decrement the major version (e.g., 11.0 -> 10.11)
    BASE_MAJOR_VERSION=$((MAJOR_VERSION - 1))
    BASE_BRANCH="origin/$BASE_MAJOR_VERSION.11"
  fi
fi

# Branches to exclude (e.g., upmerged branches)
# EXCLUDE_BRANCHES=("origin/10.5" "origin/10.11" "origin/11.4")

# Show commits that are in the current branch but not in the base branch or excluded branches
#echo "Comparing $MAJOR_VERSION.$MINOR_VERSION with base branch $BASE_BRANCH and excluding ${EXCLUDE_BRANCHES[@]}"
#git log $BASE_BRANCH..origin/$MAJOR_VERSION.$MINOR_VERSION --not "${EXCLUDE_BRANCHES[@]}" --oneline

# Show commits that are in the current branch but not in the base branch
git log $BASE_BRANCH..origin/$MAJOR_VERSION.$MINOR_VERSION --oneline
