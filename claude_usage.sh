#!/bin/bash
# claude_usage.sh - live meter of Claude subscription usage (5h + weekly windows)
# Reads the OAuth token from ~/.claude/.credentials.json and makes one minimal Haiku
# /v1/messages call (no system prompt, max_tokens 1, ~8 input + 1 output tokens). Its
# anthropic-ratelimit-unified-* response headers carry the same data the CLI's /usage
# command shows, always fresh. The result is cached and only refetched every REFRESH
# seconds, so the fast on-screen age counter costs nothing extra.
set -u

CRED="${HOME}/.claude/.credentials.json"
CACHE="/tmp/.claude_usage.$(id -u).cache"
TZONE="Australia/Sydney"   # UTC+10 == AEST year-round (no DST shift)
REFRESH=90                   # seconds between API calls
REDRAW=10                    # seconds between screen redraws
ONCE=0
REFRESH_SET=0

for a in "$@"; do
  case "$a" in
    -h|--help)
      cat <<EOF
claude_usage.sh - live Claude usage meter (5h + weekly windows)
Usage: u [REFRESH_SECS] [REDRAW_SECS]   defaults: 90 / 10   (also: usage)
       u --once    render a single frame and exit
EOF
      exit 0;;
    -1|--once|once) ONCE=1;;
    *) if [[ "$a" =~ ^[0-9]+$ ]]; then
         if [ "$REFRESH_SET" = 0 ]; then REFRESH="$a"; REFRESH_SET=1; else REDRAW="$a"; fi
       fi;;
  esac
done
[ "$REFRESH" -lt 5 ] && REFRESH=5
[ "$REDRAW" -lt 1 ] && REDRAW=1

if [ -n "${NO_COLOR:-}" ] || [ ! -t 1 ]; then
  BLD=''; DIM=''; RST=''; RED=''; YEL=''; GRN=''
else
  BLD=$'\e[1m'; DIM=$'\e[2m'; RST=$'\e[0m'; RED=$'\e[31m'; YEL=$'\e[33m'; GRN=$'\e[32m'
fi

REQ='{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"Hi"}]}'

FETCH_OK=0; FETCH_ERR=""; STALE=0
C_EPOCH=""; H5U=""; H5R=""; D7U=""; D7R=""
HDR=""; L1=""; L2=""

hv(){ grep -i "^$2:" "$1" 2>/dev/null | tail -1 | tr -d '\r' | sed -E 's/^[^:]*:[[:space:]]*//'; }

fetch(){
  FETCH_OK=0; FETCH_ERR=""
  local tok hdrs body code m
  tok="$(jq -r '.claudeAiOauth.accessToken // empty' "$CRED" 2>/dev/null)"
  if [ -z "$tok" ]; then FETCH_ERR="no token in $CRED"; return; fi
  hdrs="$(mktemp)"; body="$(mktemp)"
  code="$(curl -sS --max-time 15 -D "$hdrs" -o "$body" -w '%{http_code}' \
    https://api.anthropic.com/v1/messages \
    -H "authorization: Bearer $tok" \
    -H "anthropic-version: 2023-06-01" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "content-type: application/json" \
    -d "$REQ" 2>/dev/null)"
  if [ "$code" != "200" ]; then
    FETCH_ERR="HTTP ${code:-?}"
    m="$(jq -r '.error.message // empty' "$body" 2>/dev/null)"
    [ -n "$m" ] && FETCH_ERR="$FETCH_ERR: ${m:0:60}"
    rm -f "$hdrs" "$body"; return
  fi
  local h5u h5r d7u d7r
  h5u="$(hv "$hdrs" 'anthropic-ratelimit-unified-5h-utilization')"
  h5r="$(hv "$hdrs" 'anthropic-ratelimit-unified-5h-reset')"
  d7u="$(hv "$hdrs" 'anthropic-ratelimit-unified-7d-utilization')"
  d7r="$(hv "$hdrs" 'anthropic-ratelimit-unified-7d-reset')"
  rm -f "$hdrs" "$body"
  if [ -z "$h5u" ] && [ -z "$d7u" ]; then FETCH_ERR="no rate-limit headers"; return; fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$(date +%s)" "$h5u" "$h5r" "$d7u" "$d7r" > "$CACHE"
  FETCH_OK=1
}

read_cache(){
  C_EPOCH=""; H5U=""; H5R=""; D7U=""; D7R=""
  [ -r "$CACHE" ] || return 1
  IFS=$'\t' read -r C_EPOCH H5U H5R D7U D7R < "$CACHE"
  [ -n "$C_EPOCH" ]
}

seg(){  # $1 label  $2 utilization  $3 reset-epoch  -> formatted line, no trailing newline
  local label="$1" util="$2" reset="$3" pct filled col f e pctd rfmt lab
  lab="$(printf '%-17s' "$label")"
  if [ -z "$util" ]; then
    filled=0; col="$DIM"; pctd=" --%"
  else
    pct="$(awk -v u="$util" 'BEGIN{printf "%.0f",(u+0)*100}')"
    filled=$(( (pct*20 + 50)/100 ))
    [ "$filled" -lt 0 ] && filled=0
    [ "$filled" -gt 20 ] && filled=20
    if   [ "$pct" -ge 90 ]; then col="$RED"
    elif [ "$pct" -ge 70 ]; then col="$YEL"
    else                         col="$GRN"; fi
    pctd="$(printf '%3s%%' "$pct")"
  fi
  f="$(printf '%*s' "$filled" '' | tr ' ' '|')"
  e="$(printf '%*s' "$((20-filled))" '' | tr ' ' '_')"
  if [ -n "$reset" ]; then
    rfmt="resets $(TZ="$TZONE" date -d "@$reset" '+%a %H:%M AEST' 2>/dev/null)"
  else
    rfmt=""
  fi
  printf '%s' "${BLD}${lab}${RST}${col}${f}${RST}${DIM}${e}${RST}  ${col}${pctd}${RST}  ${DIM}${rfmt}${RST}"
}

header(){
  local now age upd h
  now="$(date +%s)"
  if [ -n "$C_EPOCH" ]; then
    age=$(( now - C_EPOCH ))
    upd="$(TZ="$TZONE" date -d "@$C_EPOCH" '+%H:%M:%S')"
  else
    age=0; upd="--:--:--"
  fi
  h="${BLD}$(printf '%-17s' 'Claude Usage')${RST}${upd}  ${DIM}(refreshing ${REFRESH}s)${RST} ${DIM}(age: ${age}s)${RST}"
  [ "$STALE" = 1 ] && h="${h}  ${RED}(stale: ${FETCH_ERR})${RST}"
  printf '%s' "$h"
}

build_frame(){
  read_cache || true
  HDR="$(header)"
  L1="$(seg '5h Session' "$H5U" "$H5R")"
  L2="$(seg 'Weekly Session' "$D7U" "$D7R")"
}

need_fetch(){
  local now; now="$(date +%s)"
  read_cache || return 0
  [ $(( now - C_EPOCH )) -ge "$REFRESH" ]
}

if [ "$ONCE" = 1 ]; then
  STALE=0
  if need_fetch; then
    fetch
    [ "$FETCH_OK" = 1 ] || { read_cache && STALE=1; }
  fi
  build_frame
  printf '%s\n%s\n%s' "$HDR" "$L1" "$L2"
  exit 0
fi

cleanup(){ printf '\e[?25h\n'; }
trap cleanup EXIT INT TERM
printf '\e[2J\e[H\e[?25l'
while :; do
  STALE=0
  if need_fetch; then
    fetch
    [ "$FETCH_OK" = 1 ] || { read_cache && STALE=1; }
  fi
  build_frame
  printf '\e[H'
  printf '%s\e[K\n' "$HDR"
  printf '%s\e[K\n' "$L1"
  printf '%s\e[K'   "$L2"
  printf '\e[J'
  sleep "$REDRAW"
done
