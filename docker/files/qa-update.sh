#!/bin/bash
# Update the framework in the box: pull mariadb-qa and run linkit. The C++ tools
# are rebuilt when the pull touched their source. Nothing outside the box is
# touched, so /test and /data keep their content.
# For a new compiler or new MSAN libraries, use qa-upgrade.

set -u
QA_DIR="${HOME}/mariadb-qa"
BEFORE="$(git -C "${QA_DIR}" rev-parse HEAD)"

echo "[qa-update] pulling mariadb-qa"
if ! git -C "${QA_DIR}" pull --autostash --ff-only; then
  echo "[qa-update] the pull did not complete. Local changes or a rewritten"
  echo "[qa-update] history can cause this. Check: git -C ${QA_DIR} status"
  exit 1
fi
AFTER="$(git -C "${QA_DIR}" rev-parse HEAD)"
git -C "${QA_DIR}" log -1 --format='[qa-update] now at %h %cd %s' --date=short

echo "[qa-update] running linkit"
"${QA_DIR}/linkit" > /tmp/linkit.log 2>&1 \
  || { echo "[qa-update] linkit failed, see /tmp/linkit.log"; exit 1; }

if [ "${BEFORE}" != "${AFTER}" ] \
   && git -C "${QA_DIR}" diff --name-only "${BEFORE}" "${AFTER}" \
      | grep -qE '^(reducercpp|revgen|generatorcpp)/'; then
  echo "[qa-update] tool source changed, rebuilding"
  qa-tools
else
  echo "[qa-update] tool source unchanged, no rebuild needed"
fi

if command -v claude > /dev/null 2>&1; then
  echo "[qa-update] updating Claude Code"
  sudo apt-get update -qq \
    && sudo apt-get install -y --only-upgrade claude-code \
    && claude --version
fi

echo "[qa-update] done. Run qa-check to check the box."
