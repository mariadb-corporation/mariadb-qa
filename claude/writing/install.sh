#!/bin/bash
# Install the writing setup into a Claude Code home: the rules file, the seed
# memories, the output style, one import line in CLAUDE.md, and the outputStyle
# setting. A file that already exists is never overwritten unless --force is
# given, and then the previous file is kept beside it with a .bak suffix.
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: install.sh --role tester|developer|support|other [--no-ai-line] [--force] [--home DIR]

  --role         picks the role section appended to the writing rules
  --no-ai-line   leave out the rule that says in passing when AI helped
  --force        replace rules.md and brief.md when they differ (keeps a .bak)
  --home DIR     install under DIR instead of $HOME (for a test run)
USAGE
}

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROLE=""
AI_LINE=1
FORCE=0
HOME_DIR="$HOME"
while [ $# -gt 0 ]; do
  case "$1" in
    --role) ROLE="${2:-}"; shift 2 ;;
    --no-ai-line) AI_LINE=0; shift ;;
    --force) FORCE=1; shift ;;
    --home) HOME_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done
case "$ROLE" in
  tester|developer|support|other) ;;
  *) echo "--role is required: tester, developer, support or other" >&2; usage >&2; exit 2 ;;
esac
[ -d "$HOME_DIR" ] || { echo "no such directory: $HOME_DIR" >&2; exit 2; }

CLAUDE_DIR="$HOME_DIR/.claude"
WRITING="$CLAUDE_DIR/writing"
MEMDIR="$WRITING/memory"
STYLES="$CLAUDE_DIR/output-styles"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"
SETTINGS="$CLAUDE_DIR/settings.json"
IMPORT_LINE="@writing/rules.md"

mkdir -p "$MEMDIR" "$STYLES"

# place SRC at DST: install when absent, skip when identical, replace on --force
place() {
  local src="$1" dst="$2"
  if [ ! -e "$dst" ]; then
    cp "$src" "$dst"
    chmod 0644 "$dst"
    echo "installed  $dst"
  elif cmp -s "$src" "$dst"; then
    echo "unchanged  $dst"
  elif [ "$FORCE" = 1 ]; then
    cp "$dst" "$dst.bak"
    cp "$src" "$dst"
    chmod 0644 "$dst"
    echo "replaced   $dst (previous kept as $dst.bak)"
  else
    echo "kept       $dst (differs from the kit; --force replaces it)"
  fi
}

# the rules file: common part, role part, AI line, then the memory index import
RULES_TMP="$(mktemp)"
trap 'rm -f "$RULES_TMP"' EXIT
cat "$KIT/rules/common.md" > "$RULES_TMP"
[ "$ROLE" = other ] || cat "$KIT/rules/role-$ROLE.md" >> "$RULES_TMP"
[ "$AI_LINE" = 0 ] || cat "$KIT/rules/ai-line.md" >> "$RULES_TMP"
printf '\n@memory/MEMORY.md\n' >> "$RULES_TMP"
place "$RULES_TMP" "$WRITING/rules.md"

# seed memories: add what is missing, never touch an existing file
added=0
for src in "$KIT"/memory/*.md; do
  name="$(basename "$src")"
  [ "$name" = MEMORY.md ] && continue
  if [ ! -e "$MEMDIR/$name" ]; then
    cp "$src" "$MEMDIR/$name"
    added=$((added + 1))
  fi
done
echo "memories   $MEMDIR ($added added)"

# the index: create it, or append the lines whose file it does not list yet
if [ ! -e "$MEMDIR/MEMORY.md" ]; then
  cp "$KIT/memory/MEMORY.md" "$MEMDIR/MEMORY.md"
  echo "installed  $MEMDIR/MEMORY.md"
else
  lines=0
  while IFS= read -r line; do
    case "$line" in
      "- ["*) ;;
      *) continue ;;
    esac
    file="${line#*](}"
    file="${file%%)*}"
    if ! grep -qF "($file)" "$MEMDIR/MEMORY.md"; then
      printf '%s\n' "$line" >> "$MEMDIR/MEMORY.md"
      lines=$((lines + 1))
    fi
  done < "$KIT/memory/MEMORY.md"
  echo "index      $MEMDIR/MEMORY.md ($lines lines added)"
fi

place "$KIT/output-styles/brief.md" "$STYLES/brief.md"

# CLAUDE.md: one import line, appended once
if [ ! -e "$CLAUDE_MD" ]; then
  printf '%s\n' "$IMPORT_LINE" > "$CLAUDE_MD"
  echo "created    $CLAUDE_MD (with the import line)"
elif grep -qxF "$IMPORT_LINE" "$CLAUDE_MD"; then
  echo "unchanged  $CLAUDE_MD (import line present)"
else
  printf '\n%s\n' "$IMPORT_LINE" >> "$CLAUDE_MD"
  echo "appended   $CLAUDE_MD (import line)"
fi

# settings.json: set outputStyle when none is set
if [ ! -e "$SETTINGS" ]; then
  printf '{\n  "outputStyle": "brief"\n}\n' > "$SETTINGS"
  echo "created    $SETTINGS (outputStyle brief)"
else
  python3 - "$SETTINGS" <<'PY'
import json, sys
path = sys.argv[1]
try:
  with open(path, encoding="utf-8") as fh:
    data = json.load(fh)
except ValueError:
  print("kept       %s (not valid JSON; set \"outputStyle\": \"brief\" by hand)" % path)
  sys.exit(0)
current = data.get("outputStyle")
if current == "brief":
  print("unchanged  %s (outputStyle brief)" % path)
elif current:
  print("kept       %s (outputStyle is %r; set it to brief to use the style)" % (path, current))
else:
  data["outputStyle"] = "brief"
  with open(path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
  print("updated    %s (outputStyle brief)" % path)
PY
fi

cat <<NEXT

Next: restart Claude Code and run /context. $CLAUDE_MD is listed under Memory
files, and the rules and the memory index load through its import line. To
confirm, ask Claude for the first heading of its writing rules.
NEXT
