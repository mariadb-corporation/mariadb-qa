#!/bin/bash
# Create a bug ticket on jira.mariadb.org via the REST API.
# Scope: public generic bugs (crash / assert / UB / ASAN), and with
# --security-bug a developer-only ticket whose comments are developer-only too.
# No credentials live in this script or the repo. A Personal Access Token is
# read from $JIRA_PAT, else from a chmod-600 file under ~/.config. On first use
# the script guides token creation and stores it securely.

set -euo pipefail

JIRA_URL="${JIRA_URL:-https://jira.mariadb.org}"
CRED_FILE="${JIRA_PAT_FILE:-$HOME/.config/mariadb-qa/jira.pat}"

PROJECT="MDEV"
ISSUETYPE="Bug"
SUMMARY=""
DESCRIPTION=""
DESC_FILE=""
PRIORITY=""
ENVIRONMENT=""
EXTRA_FILE=""
COMMENT_KEY=""
LINK_KEY=""
EDIT_KEY=""
LINK_TYPE="Relates"
LINK_REVERSE=0
ASSIGNEE=""
DRY_RUN=0
ASSUME_YES=0
MODE="create"
MODE_FLAG=""
LINK_TYPE_SET=0
WHOAMI=""
PAT=""
SEC_BUG=0
DEV_ONLY=0
SEC_LEVEL_ID="${JIRA_SEC_LEVEL_ID:-10400}"
SEC_LEVEL_NAME="${JIRA_SEC_LEVEL_NAME:-Developers}"
SEC_ROLE="${JIRA_SEC_ROLE:-Developers}"

declare -a AFFECTS=() FIXINS=() COMPONENTS=() LABELS=() RELATES=() ESVERS=() SEC_COMMENTS=()

die() { echo "ERROR: $*" >&2; exit 1; }

# Guard a flag that takes a value: need "$@" from inside its case branch.
need() { [ "$#" -ge 2 ] || die "$1 requires a value (see --help)"; }

# Guard against two mode flags in one call.
mode_once() {
  [ -z "$MODE_FLAG" ] || die "one mode at a time: $MODE_FLAG and $1 both given"
  MODE_FLAG="$1"; MODE="$2"
}

usage() {
  cat <<EOF
Usage: log_jira_ticket.sh [MODE] [options]

Modes:
  (default)          Create a ticket (public, generic bug)
  --login            (Re)authenticate and store a Personal Access Token
  --whoami           Print the authenticated Jira account
  --createmeta       List required fields for --project / --type
  --comment KEY      Add a comment to issue KEY (body via -d / --description-file)
                       Add --dev-only to restrict it to the $SEC_ROLE role
  --link KEY         Link KEY to related issues: --link KEY --relates OTHER [--relates ...] [--link-type Relates] [--reverse]
                       Default reads "OTHER <type-inward> KEY" (e.g. PartOf: "OTHER is part of KEY");
                       --reverse flips to "OTHER <type-outward> KEY" (e.g. PartOf: "OTHER includes KEY").
                       Valid --link-type values: Blocks, Duplicate, "Issue split", PartOf,
                       Problem/Incident ("is caused by" / "causes"), Relates. An unknown
                       value is rejected; the list is read back from the server.
  --edit KEY         Add versions and/or labels to an EXISTING issue (additive, never replaces):
                       --edit KEY --affects-version 13.0 [--affects-version 13.1] [--fix-version 13.0] [--es-version 13.0]
                       --edit KEY --label corruption [--label security]
                       --edit KEY --label corruption --affects-version 13.1   (versions + labels combinable)
                     Use mainline X.Y names only (13.0, not 13.0.1).

Create options:
  -p, --project KEY        Project key (default: MDEV; also MENT)
  -t, --type NAME          Issue type (default: Bug)
  -s, --summary TEXT       Issue summary  (required)
  -d, --description TEXT   Description in Jira wiki markup
      --description-file F  Read description from file (e.g. comment_1.txt)
      --affects-version V  Affects Version/s - CS (repeatable)
      --es-version V       Affects ES Version/s - Enterprise (repeatable)
      --fix-version V      Fix Version/s (repeatable)
  -c, --component NAME     Component (repeatable)
  -l, --label NAME         Label (repeatable)
      --priority NAME      Priority name
      --assignee USER      Assignee Jira username (e.g. psergei)
      --environment TEXT   Environment field
      --json-extra FILE    Merge extra "fields" JSON (custom fields)
      --dry-run            Print the payload/preview, do not POST. No auth needed,
                           except --link, which reads the link types from the server.
  -y, --yes                Skip the 3x confirmation (for automation)
  -h, --help               This help

Security bug options:
      --security-bug       File a developer-only security ticket: security level
                           $SEC_LEVEL_NAME (id $SEC_LEVEL_ID), and the description defaults
                           to the summary, so nothing but the title is public.
      --sec-comment FILE   Comment file to post after create, visible to the
                           $SEC_ROLE role only (repeatable, posted in order).
                           Needs --security-bug. Typical order:
                             --sec-comment comment_1.txt
                             --sec-comment comment_2.txt
                             --sec-comment comment_3.txt
                           After posting, the level and every comment's
                           visibility are read back and checked.
      --dev-only           With --comment KEY: restrict that comment to $SEC_ROLE

Auth:
  Token order: \$JIRA_PAT, then $CRED_FILE
  Base URL:    \$JIRA_URL (default $JIRA_URL)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --login|--auth) mode_once "$1" login ;;
    --whoami) mode_once "$1" whoami ;;
    --createmeta) mode_once "$1" createmeta ;;
    --comment) need "$@"; mode_once "$1" comment; COMMENT_KEY="$2"; shift ;;
    --link) need "$@"; mode_once "$1" link; LINK_KEY="$2"; shift ;;
    --edit) need "$@"; mode_once "$1" edit; EDIT_KEY="$2"; shift ;;
    --relates) need "$@"; RELATES+=("$2"); shift ;;
    --link-type) need "$@"; LINK_TYPE="$2"; LINK_TYPE_SET=1; shift ;;
    --reverse) LINK_REVERSE=1 ;;
    -p|--project) need "$@"; PROJECT="$2"; shift ;;
    -t|--type) need "$@"; ISSUETYPE="$2"; shift ;;
    -s|--summary) need "$@"; SUMMARY="$2"; shift ;;
    -d|--description) need "$@"; DESCRIPTION="$2"; shift ;;
    --description-file) need "$@"; DESC_FILE="$2"; shift ;;
    --affects-version) need "$@"; AFFECTS+=("$2"); shift ;;
    --es-version) need "$@"; ESVERS+=("$2"); shift ;;
    --fix-version) need "$@"; FIXINS+=("$2"); shift ;;
    -c|--component) need "$@"; COMPONENTS+=("$2"); shift ;;
    -l|--label) need "$@"; LABELS+=("$2"); shift ;;
    --priority) need "$@"; PRIORITY="$2"; shift ;;
    --assignee) need "$@"; ASSIGNEE="$2"; shift ;;
    --environment) need "$@"; ENVIRONMENT="$2"; shift ;;
    --json-extra) need "$@"; EXTRA_FILE="$2"; shift ;;
    --security-bug) SEC_BUG=1 ;;
    --sec-comment) need "$@"; SEC_COMMENTS+=("$2"); shift ;;
    --dev-only) DEV_ONLY=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -y|--yes) ASSUME_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1 (see --help)" ;;
  esac
  shift
done

# Reject an option that belongs to another mode, rather than ignoring it.
if [ "$MODE" != "link" ]; then
  [ "${#RELATES[@]}" -eq 0 ] || die "--relates is only valid with --link"
  [ "$LINK_REVERSE" = 0 ]    || die "--reverse is only valid with --link"
  [ "$LINK_TYPE_SET" = 0 ]   || die "--link-type is only valid with --link"
fi
if [ "$MODE" != "comment" ]; then
  [ "$DEV_ONLY" = 0 ] || die "--dev-only is only valid with --comment"
fi
if [ "$MODE" != "create" ]; then
  [ "$SEC_BUG" = 0 ]              || die "--security-bug is only valid when creating an issue"
  [ "${#SEC_COMMENTS[@]}" -eq 0 ] || die "--sec-comment is only valid when creating an issue"
fi

command -v jq >/dev/null || die "jq is required"
command -v curl >/dev/null || die "curl is required"

# Authenticated curl: the token is fed via a -K config built by the printf
# builtin, so it never appears in argv / ps.
jira_curl() {
  curl -sS -K <(printf 'header = "Authorization: Bearer %s"\n' "$PAT") "$@"
}

load_pat() {
  if [ -n "${JIRA_PAT:-}" ]; then PAT="$JIRA_PAT"; return 0; fi
  if [ -f "$CRED_FILE" ]; then PAT="$(< "$CRED_FILE")"; [ -n "$PAT" ] && return 0; fi
  return 1
}

whoami_check() {
  local resp code body
  resp="$(jira_curl -H 'Accept: application/json' -w $'\n%{http_code}' "$JIRA_URL/rest/api/2/myself")" || return 1
  code="${resp##*$'\n'}"; body="${resp%$'\n'*}"
  [ "$code" = "200" ] || { echo "Auth check failed (HTTP $code): $body" >&2; return 1; }
  WHOAMI="$(printf '%s' "$body" | jq -r '"\(.displayName) <\(.name)>"')"
  return 0
}

prompt_and_store_pat() {
  { : < /dev/tty; } 2>/dev/null || die "No terminal to read the token. Store it once from a terminal, or set JIRA_PAT_FILE."
  cat >&2 <<EOF

No Jira credentials stored yet.

Create a Personal Access Token (one time, in a browser logged into Jira):
  1. Open  $JIRA_URL/secure/ViewProfile.jspa
  2. Left sidebar -> "Personal Access Tokens"
  3. "Create token" -> name it (e.g. mariadb-qa-cli) -> set/skip expiry
  4. Copy the token (shown once)
EOF
  local token
  read -rsp "Paste PAT (input hidden): " token < /dev/tty; echo >&2
  [ -n "$token" ] || die "Empty token."
  PAT="$token"
  whoami_check || die "Token rejected by $JIRA_URL."
  mkdir -p "$(dirname "$CRED_FILE")"
  chmod 700 "$(dirname "$CRED_FILE")" 2>/dev/null || true
  ( umask 077; printf '%s' "$token" > "$CRED_FILE" )
  chmod 600 "$CRED_FILE"
  echo "Stored credential at $CRED_FILE (chmod 600)." >&2
  echo "Authenticated as: $WHOAMI" >&2
}

require_auth() {
  if [ "$MODE" = "login" ]; then PAT=""; prompt_and_store_pat; return; fi
  if ! load_pat; then prompt_and_store_pat; return; fi
  whoami_check || { echo "Stored token invalid or expired; re-authenticating." >&2; prompt_and_store_pat; }
}

# Post one comment file, visible to the $SEC_ROLE role only.
post_dev_comment() {
  local key="$1" file="$2" payload resp code cbody
  payload="$(jq -n --rawfile b "$file" --arg r "$SEC_ROLE" \
    '{body: $b, visibility: {type: "role", value: $r}}')"
  resp="$(jira_curl -X POST -H 'Content-Type: application/json' -H 'Accept: application/json' \
    --data-binary "$payload" -w $'\n%{http_code}' "$JIRA_URL/rest/api/2/issue/$key/comment")"
  code="${resp##*$'\n'}"; cbody="${resp%$'\n'*}"
  if [ "$code" = "201" ]; then
    echo "Comment added ($SEC_ROLE only): $file"
    return 0
  fi
  echo "Comment failed for $file (HTTP $code):" >&2
  printf '%s' "$cbody" | jq . >&2 2>/dev/null || printf '%s\n' "$cbody" >&2
  return 1
}

# Read back the security level and every comment's visibility.
verify_security() {
  local key="$1" json lvl open bad=0
  json="$(jira_curl -H 'Accept: application/json' \
    "$JIRA_URL/rest/api/2/issue/$key?fields=security,comment")"
  lvl="$(printf '%s' "$json" | jq -r '.fields.security.name // "NONE"')"
  if [ "$lvl" = "$SEC_LEVEL_NAME" ]; then
    echo "Verified: security level $lvl"
  else
    echo "VERIFY FAILED: $key is at level '$lvl', not '$SEC_LEVEL_NAME'. It is public." >&2
    bad=1
  fi
  open="$(printf '%s' "$json" | jq -r --arg r "$SEC_ROLE" \
    '[.fields.comment.comments[]? | select((.visibility.value // "") != $r)] | length')"
  if [ "$open" = "0" ]; then
    echo "Verified: every comment restricted to $SEC_ROLE"
  else
    echo "VERIFY FAILED: $open comment(s) on $key are not restricted to $SEC_ROLE." >&2
    bad=1
  fi
  return $bad
}

# name-array of strings -> JSON [{"name": ...}]
arr_named() {
  local -n _a="$1"
  if [ "${#_a[@]}" -eq 0 ]; then echo '[]'; return; fi
  printf '%s\n' "${_a[@]}" | jq -R '{name: .}' | jq -s '.'
}

# name-array of strings -> JSON ["...", "..."]
arr_plain() {
  local -n _a="$1"
  if [ "${#_a[@]}" -eq 0 ]; then echo '[]'; return; fi
  printf '%s\n' "${_a[@]}" | jq -R '.' | jq -s '.'
}

# name-array -> JSON [{"add":{"name":...}}]  (Jira "update" verb; additive, preserves existing)
arr_addname() {
  local -n _a="$1"
  if [ "${#_a[@]}" -eq 0 ]; then echo '[]'; return; fi
  printf '%s\n' "${_a[@]}" | jq -R '{add:{name:.}}' | jq -s '.'
}

# str-array -> JSON [{"add":...}]  (labels-type custom field; additive)
arr_addstr() {
  local -n _a="$1"
  if [ "${#_a[@]}" -eq 0 ]; then echo '[]'; return; fi
  printf '%s\n' "${_a[@]}" | jq -R '{add:.}' | jq -s '.'
}

case "$MODE" in
  login)   require_auth; echo "Login OK: $WHOAMI"; exit 0 ;;
  whoami)  require_auth; echo "Authenticated as: $WHOAMI"; exit 0 ;;
  createmeta)
    require_auth
    jira_curl -H 'Accept: application/json' --get \
      --data-urlencode "projectKeys=$PROJECT" \
      --data-urlencode "issuetypeNames=$ISSUETYPE" \
      --data-urlencode "expand=projects.issuetypes.fields" \
      "$JIRA_URL/rest/api/2/issue/createmeta" \
      | jq -r --arg proj "$PROJECT" --arg itype "$ISSUETYPE" '
          (.projects // []) as $p
          | [$p[].issuetypes[]?] as $t
          | if ($p|length)==0 then "No project \($proj), or no create permission."
            elif ($t|length)==0 then "No issue type \($itype) in project \($proj)."
            else
              $t[].fields | to_entries[]
              | select(.value.required==true)
              | "required: \(.key)\t(\(.value.name))"
            end'
    exit 0 ;;
  comment)
    [ -n "$COMMENT_KEY" ] || die "--comment requires an issue key (e.g. MDEV-12345)"
    if [ -n "$DESC_FILE" ]; then
      [ -f "$DESC_FILE" ] || die "comment body file not found: $DESC_FILE"
      DESCRIPTION="$(< "$DESC_FILE")"
    fi
    [ -n "$DESCRIPTION" ] || die "comment body required (-d or --description-file)"
    [ "$DRY_RUN" = 1 ] || require_auth
    if [ "$DEV_ONLY" = 1 ]; then
      payload="$(jq -n --arg b "$DESCRIPTION" --arg r "$SEC_ROLE" \
        '{body: $b, visibility: {type: "role", value: $r}}')"
    else
      payload="$(jq -n --arg b "$DESCRIPTION" '{body: $b}')"
    fi
    echo "=== Comment on: $JIRA_URL/browse/$COMMENT_KEY${WHOAMI:+  (as $WHOAMI)} ===" >&2
    if [ "$DEV_ONLY" = 1 ]; then echo "=== Visible to: role $SEC_ROLE ===" >&2; fi
    echo "=== Body ===" >&2
    printf '%s\n' "$DESCRIPTION" >&2
    if [ "$DRY_RUN" = 1 ]; then echo "[dry-run] comment not posted." >&2; exit 0; fi
    if [ "$ASSUME_YES" != 1 ]; then
      echo "Confirm posting this comment to $COMMENT_KEY. Press Enter 3x (Ctrl-C to abort)." >&2
      read -rp "1x... " _ < /dev/tty
      read -rp "2x... " _ < /dev/tty
      read -rp "3x... " _ < /dev/tty
    fi
    resp="$(jira_curl -X POST -H 'Content-Type: application/json' -H 'Accept: application/json' \
      --data-binary "$payload" -w $'\n%{http_code}' "$JIRA_URL/rest/api/2/issue/$COMMENT_KEY/comment")"
    code="${resp##*$'\n'}"; cbody="${resp%$'\n'*}"
    if [ "$code" = "201" ]; then
      echo "Comment added to $COMMENT_KEY"
      echo "URL: $JIRA_URL/browse/$COMMENT_KEY"
    else
      echo "Comment failed (HTTP $code):" >&2
      printf '%s' "$cbody" | jq . >&2 2>/dev/null || printf '%s\n' "$cbody" >&2
      exit 1
    fi
    exit 0 ;;
  link)
    [ -n "$LINK_KEY" ] || die "--link requires a source issue key (e.g. MDEV-12345)"
    [ "${#RELATES[@]}" -gt 0 ] || die "--link needs at least one --relates <KEY>"
    require_auth
    lt_resp="$(jira_curl -H 'Accept: application/json' -w $'\n%{http_code}' "$JIRA_URL/rest/api/2/issueLinkType")" \
      || die "Cannot reach $JIRA_URL to read the issue link types."
    lt_code="${lt_resp##*$'\n'}"; lt_json="${lt_resp%$'\n'*}"
    LT_NAMES="$(printf '%s' "$lt_json" | jq -r '.issueLinkTypes[]?.name' 2>/dev/null || true)"
    [ -n "$LT_NAMES" ] || die "Cannot read the issue link types from $JIRA_URL (HTTP $lt_code)."
    IN_DESC="$(printf '%s' "$lt_json" | jq -r --arg t "$LINK_TYPE" '.issueLinkTypes[]? | select(.name==$t) | .inward')"
    OUT_DESC="$(printf '%s' "$lt_json" | jq -r --arg t "$LINK_TYPE" '.issueLinkTypes[]? | select(.name==$t) | .outward')"
    if [ -z "$IN_DESC" ] || [ -z "$OUT_DESC" ]; then
      die "Unknown --link-type '$LINK_TYPE'. Valid: $(printf '%s' "$LT_NAMES" | paste -sd, - | sed 's/,/, /g')"
    fi
    if [ "$LINK_REVERSE" = 1 ]; then REL_DESC="$OUT_DESC"; else REL_DESC="$IN_DESC"; fi
    echo "=== Link on $JIRA_URL/browse/$LINK_KEY  (type: $LINK_TYPE, as $WHOAMI) ===" >&2
    for r in "${RELATES[@]}"; do echo "  $r $REL_DESC $LINK_KEY" >&2; done
    if [ "$DRY_RUN" = 1 ]; then echo "[dry-run] links not created." >&2; exit 0; fi
    if [ "$ASSUME_YES" != 1 ]; then
      echo "Confirm creating these links. Press Enter 3x (Ctrl-C to abort)." >&2
      read -rp "1x... " _ < /dev/tty
      read -rp "2x... " _ < /dev/tty
      read -rp "3x... " _ < /dev/tty
    fi
    rc=0
    for r in "${RELATES[@]}"; do
      if [ "$LINK_REVERSE" = 1 ]; then
        payload="$(jq -n --arg t "$LINK_TYPE" --arg a "$r" --arg b "$LINK_KEY" '{type:{name:$t},inwardIssue:{key:$a},outwardIssue:{key:$b}}')"
      else
        payload="$(jq -n --arg t "$LINK_TYPE" --arg a "$LINK_KEY" --arg b "$r" '{type:{name:$t},inwardIssue:{key:$a},outwardIssue:{key:$b}}')"
      fi
      resp="$(jira_curl -X POST -H 'Content-Type: application/json' -H 'Accept: application/json' --data-binary "$payload" -w $'\n%{http_code}' "$JIRA_URL/rest/api/2/issueLink")"
      code="${resp##*$'\n'}"; lbody="${resp%$'\n'*}"
      if [ "$code" = "201" ]; then echo "Linked: $r $REL_DESC $LINK_KEY"
      else echo "Link failed ($LINK_KEY -> $r, HTTP $code):" >&2; printf '%s' "$lbody" | jq . >&2 2>/dev/null || printf '%s\n' "$lbody" >&2; rc=1; fi
    done
    exit $rc ;;
  edit)
    [ -n "$EDIT_KEY" ] || die "--edit requires an issue key (e.g. MDEV-12345)"
    av_json="$(arr_addname AFFECTS)"; fv_json="$(arr_addname FIXINS)"; ev_json="$(arr_addstr ESVERS)"; lb_json="$(arr_addstr LABELS)"
    upd="$(jq -n --argjson av "$av_json" --argjson fv "$fv_json" --argjson ev "$ev_json" --argjson lb "$lb_json" \
      '{}
       + (if ($av|length) > 0 then {versions: $av}            else {} end)
       + (if ($fv|length) > 0 then {fixVersions: $fv}         else {} end)
       + (if ($ev|length) > 0 then {customfield_13204: $ev}   else {} end)
       + (if ($lb|length) > 0 then {labels: $lb}              else {} end)')"
    if [ -n "$ASSIGNEE" ]; then fld_json="$(jq -n --arg a "$ASSIGNEE" '{assignee:{name:$a}}')"; else fld_json='{}'; fi
    [ "$(printf '%s' "$upd" | jq 'length')" -gt 0 ] || [ "$(printf '%s' "$fld_json" | jq 'length')" -gt 0 ] || die "--edit needs at least one --affects-version/--fix-version/--es-version/--label/--assignee"
    payload="$(jq -n --argjson u "$upd" --argjson f "$fld_json" \
      '(if ($u|length) > 0 then {update: $u} else {} end)
       + (if ($f|length) > 0 then {fields: $f} else {} end)')"
    echo "=== Edit (additive) : PUT $JIRA_URL/rest/api/2/issue/$EDIT_KEY ===" >&2
    echo "=== Update payload ===" >&2
    printf '%s\n' "$payload" | jq . >&2
    if [ "$DRY_RUN" = 1 ]; then echo "[dry-run] update not applied." >&2; exit 0; fi
    require_auth
    echo "=== As : $WHOAMI ===" >&2
    if [ "$ASSUME_YES" != 1 ]; then
      echo "Confirm adding these versions/labels to $EDIT_KEY. Press Enter 3x (Ctrl-C to abort)." >&2
      read -rp "1x... " _ < /dev/tty
      read -rp "2x... " _ < /dev/tty
      read -rp "3x... " _ < /dev/tty
    fi
    resp="$(jira_curl -X PUT -H 'Content-Type: application/json' -H 'Accept: application/json' \
      --data-binary "$payload" -w $'\n%{http_code}' "$JIRA_URL/rest/api/2/issue/$EDIT_KEY")"
    code="${resp##*$'\n'}"; ebody="${resp%$'\n'*}"
    if [ "$code" = "204" ]; then
      echo "Updated: $EDIT_KEY"
      echo "URL: $JIRA_URL/browse/$EDIT_KEY"
    else
      echo "Edit failed (HTTP $code):" >&2
      printf '%s' "$ebody" | jq . >&2 2>/dev/null || printf '%s\n' "$ebody" >&2
      exit 1
    fi
    exit 0 ;;
esac

# --- create ---
[ -n "$SUMMARY" ] || die "--summary is required"
if [ "${#SEC_COMMENTS[@]}" -gt 0 ] && [ "$SEC_BUG" != 1 ]; then
  die "--sec-comment needs --security-bug"
fi
if [ "${#SEC_COMMENTS[@]}" -gt 0 ]; then
  for f in "${SEC_COMMENTS[@]}"; do
    [ -f "$f" ] || die "sec-comment file not found: $f"
  done
fi
if [ -n "$DESC_FILE" ]; then
  [ -f "$DESC_FILE" ] || die "description file not found: $DESC_FILE"
  DESCRIPTION="$(< "$DESC_FILE")"
fi
if [ -z "$DESCRIPTION" ] && [ "$SEC_BUG" = 1 ]; then DESCRIPTION="$SUMMARY"; fi
[ -n "$DESCRIPTION" ] || die "--description or --description-file is required"

versions_json="$(arr_named AFFECTS)"
fixins_json="$(arr_named FIXINS)"
components_json="$(arr_named COMPONENTS)"
labels_json="$(arr_plain LABELS)"
esvers_json="$(arr_plain ESVERS)"

fields="$(jq -n \
  --arg proj "$PROJECT" --arg type "$ISSUETYPE" \
  --arg summary "$SUMMARY" --arg desc "$DESCRIPTION" \
  --arg prio "$PRIORITY" --arg env "$ENVIRONMENT" --arg assignee "$ASSIGNEE" \
  --argjson versions "$versions_json" \
  --argjson fixins "$fixins_json" \
  --argjson components "$components_json" \
  --argjson labels "$labels_json" \
  --argjson esvers "$esvers_json" \
  '{
     project: {key: $proj},
     issuetype: {name: $type},
     summary: $summary,
     description: $desc
   }
   + (if ($versions|length)   > 0 then {versions: $versions}       else {} end)
   + (if ($fixins|length)     > 0 then {fixVersions: $fixins}      else {} end)
   + (if ($components|length) > 0 then {components: $components}    else {} end)
   + (if ($labels|length)     > 0 then {labels: $labels}           else {} end)
   + (if ($esvers|length)     > 0 then {customfield_13204: $esvers}  else {} end)
   + (if $prio != "" then {priority: {name: $prio}} else {} end)
   + (if $assignee != "" then {assignee: {name: $assignee}} else {} end)
   + (if $env  != "" then {environment: $env}       else {} end)')"

if [ -n "$EXTRA_FILE" ]; then
  [ -f "$EXTRA_FILE" ] || die "json-extra file not found: $EXTRA_FILE"
  fields="$(jq -n --argjson a "$fields" --argjson b "$(cat "$EXTRA_FILE")" '$a + $b')"
fi

if [ "$SEC_BUG" = 1 ]; then
  fields="$(jq -n --argjson a "$fields" --arg id "$SEC_LEVEL_ID" '$a + {security: {id: $id}}')"
fi

payload="$(jq -n --argjson f "$fields" '{fields: $f}')"

echo "=== Target : POST $JIRA_URL/rest/api/2/issue ===" >&2
echo "=== Payload ===" >&2
printf '%s\n' "$payload" | jq . >&2

if [ "$DRY_RUN" = 1 ]; then
  echo "[dry-run] payload not posted." >&2
  if [ "${#SEC_COMMENTS[@]}" -gt 0 ]; then
    echo "[dry-run] would post as $SEC_ROLE-only comments, in order:" >&2
    printf '  %s\n' "${SEC_COMMENTS[@]}" >&2
  fi
  exit 0
fi

require_auth
echo "=== As : $WHOAMI ===" >&2

if [ "$ASSUME_YES" != 1 ]; then
  if [ "$SEC_BUG" = 1 ]; then
    echo "Confirm creation of this $SEC_LEVEL_NAME-only security ticket. Press Enter 3x (Ctrl-C to abort)." >&2
  else
    echo "Confirm creation of this PUBLIC ticket. Press Enter 3x (Ctrl-C to abort)." >&2
  fi
  read -rp "1x... " _ < /dev/tty
  read -rp "2x... " _ < /dev/tty
  read -rp "3x... " _ < /dev/tty
fi

resp="$(jira_curl -X POST \
  -H 'Content-Type: application/json' -H 'Accept: application/json' \
  --data-binary "$payload" -w $'\n%{http_code}' "$JIRA_URL/rest/api/2/issue")"
code="${resp##*$'\n'}"; body="${resp%$'\n'*}"

if [ "$code" = "201" ]; then
  key="$(printf '%s' "$body" | jq -r '.key')"
  echo "Created: $key"
  echo "URL: $JIRA_URL/browse/$key"
else
  echo "Create failed (HTTP $code):" >&2
  printf '%s' "$body" | jq . >&2 2>/dev/null || printf '%s\n' "$body" >&2
  exit 1
fi

if [ "$SEC_BUG" = 1 ]; then
  rc=0
  if [ "${#SEC_COMMENTS[@]}" -gt 0 ]; then
    for f in "${SEC_COMMENTS[@]}"; do
      post_dev_comment "$key" "$f" || rc=1
    done
  fi
  verify_security "$key" || rc=1
  [ "$rc" = 0 ] || die "$key needs attention: see the failures above."
fi
