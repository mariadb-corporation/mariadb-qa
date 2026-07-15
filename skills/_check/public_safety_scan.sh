#!/bin/bash
# Public-safety scanner for a PUBLIC repo (mariadb-qa).
# Blocks generic secrets (built in) PLUS patterns from an optional local denylist that
# is kept OUTSIDE the repo - so confidential/box-specific patterns are never committed here.
#
# Usage:
#   public_safety_scan.sh [path ...]   scan the given files/dirs
#   public_safety_scan.sh              no args: scan the git-staged file set
#
# Private local denylist (one extended-regex per line; a 'PATH:' prefix matches file paths):
#   $PUBLIC_SAFETY_DENYLIST   or   ~/.config/mariadb-qa/public_safety_denylist
#
# Exit 0 = clean, 1 = one or more violations (printed).
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo .)"
LOCAL_DENYLIST="${PUBLIC_SAFETY_DENYLIST:-$HOME/.config/mariadb-qa/public_safety_denylist}"

# The guards themselves are never scanned.
SELF_EXCLUDE='(^|/)hooks/|(^|/)skills/_check/|(^|/)\.gitignore'

# Generic secret indicators - universal, reveal nothing box-specific, safe to ship publicly.
CONTENT_DENY='begin [a-z ]*private key|-----begin |api[_-]?key[[:space:]]*[=:].{0,3}[a-z0-9/+_.-]{16,}|bearer [a-z0-9._-]{20,}|akia[0-9a-z]{16}|aws_secret_access_key|xox[baprs]-[a-z0-9-]{10,}|ghp_[a-z0-9]{20,}'
PATH_DENY='\.pat$|\.env$|\.env\.|(^|/)id_rsa|(^|/)id_ed25519|(^|/)id_dsa|(^|/)id_ecdsa|(^|/)\.netrc$|(^|/)\.pgpass$|(^|/)\.npmrc$|(^|/)credentials$'
CONTENT_ALLOW='/home/(youruser|user|USER|<user>|\$\{?USER)'

# Merge private, box-specific patterns from the local denylist if present.
if [ -f "$LOCAL_DENYLIST" ]; then
  while IFS= read -r line; do
    case "$line" in
      ''|\#*) continue ;;
      PATH:*) PATH_DENY="$PATH_DENY|${line#PATH:}" ;;
      *)      CONTENT_DENY="$CONTENT_DENY|$line" ;;
    esac
  done < "$LOCAL_DENYLIST"
  # An invalid denylist regex must fail closed, not silently disable the scan
  for PAT in "$CONTENT_DENY" "$PATH_DENY"; do
    echo | grep -qE "$PAT"
    if [ "$?" -ge 2 ]; then
      echo "public_safety_scan: invalid regex in $LOCAL_DENYLIST - fix it (scan fails closed)"
      exit 1
    fi
  done
fi

files=()
if [ "$#" -gt 0 ]; then
  for p in "$@"; do
    if [ -d "$p" ]; then
      while IFS= read -r f; do files+=("$f"); done < <(find "$p" -type f)
    elif [ -f "$p" ]; then
      files+=("$p")
    fi
  done
else
  while IFS= read -r f; do [ -f "$f" ] && files+=("$f"); done \
    < <(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null)
fi

viol=0
for f in "${files[@]:-}"; do
  [ -z "$f" ] && continue
  rel="${f#"$ROOT"/}"
  echo "$rel" | grep -qE "$SELF_EXCLUDE" && continue
  if echo "$rel" | grep -qiE "$PATH_DENY"; then
    echo "BLOCK (path):    $rel"
    viol=1
    continue
  fi
  grep -Iq . "$f" 2>/dev/null || continue   # skip binary / empty
  hits="$(grep -inE "$CONTENT_DENY" "$f" 2>/dev/null | grep -vE "$CONTENT_ALLOW")"
  if [ -n "$hits" ]; then
    echo "BLOCK (content): $rel"
    printf '%s\n' "$hits" | sed 's/^/    /'
    viol=1
  fi
done

if [ "$viol" -ne 0 ]; then
  echo ""
  echo "public_safety_scan: confidential content detected - NOT safe for the public repo."
  echo "Scrub/remove it, or (human, only if truly safe) override with: git commit --no-verify"
  exit 1
fi
echo "public_safety_scan: clean"
exit 0
