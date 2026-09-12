#!/bin/bash
# Fetch the writing setup kit from GitHub without a clone: list the kit files through
# the GitHub tree API, download each one by its raw URL, and place the set under
# ~/.claude/writing-kit (or WRITING_KIT_DIR). Re-running replaces the kit with the
# current version. Needs curl or wget, and python3.
set -euo pipefail

REPO="${WRITING_KIT_REPO:-mariadb-corporation/mariadb-qa}"
REF="${WRITING_KIT_REF:-master}"
KIT_PATH="${WRITING_KIT_PATH:-claude/writing}"
DEST="${WRITING_KIT_DIR:-$HOME/.claude/writing-kit}"
RAW="https://raw.githubusercontent.com/$REPO/$REF"
API="https://api.github.com/repos/$REPO/git/trees/$REF?recursive=1"

fetch() {
  if command -v curl >/dev/null; then
    curl -fsSL "$1" -o "$2"
  elif command -v wget >/dev/null; then
    wget -q "$1" -O "$2"
  else
    echo "curl or wget is required" >&2; exit 2
  fi
}
command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo 'Fetching files (~2 minutes)...'

fetch "$API" "$TMP/tree.json"
python3 - "$TMP/tree.json" "$KIT_PATH" > "$TMP/files" <<'PY'
import json, sys
tree = json.load(open(sys.argv[1]))
prefix = sys.argv[2].rstrip("/") + "/"
for entry in tree["tree"]:
  if entry["type"] == "blob" and entry["path"].startswith(prefix):
    print(entry["path"][len(prefix):])
PY
[ -s "$TMP/files" ] || { echo "no files found under $KIT_PATH in $REPO@$REF" >&2; exit 1; }

count=0
while IFS= read -r rel; do
  mkdir -p "$TMP/kit/$(dirname "$rel")"
  fetch "$RAW/$KIT_PATH/$rel" "$TMP/kit/$rel"
  case "$rel" in *.sh|*.py) chmod 0755 "$TMP/kit/$rel" ;; esac
  count=$((count + 1))
done < "$TMP/files"

mkdir -p "$(dirname "$DEST")"
rm -rf "$DEST"
mv "$TMP/kit" "$DEST"

cat <<NEXT
$count files placed in $DEST

Next: start Claude Code in your home directory and paste this line:

  Read $DEST/SETUP.md and follow it.
NEXT
