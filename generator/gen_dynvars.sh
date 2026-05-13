#!/bin/bash
# Created by Roel Van de Paar, MariaDB Corporation
# Regenerate dynvars_session.txt and dynvars_global.txt with intelligible name=value pairs
# derived from information_schema.SYSTEM_VARIABLES on a running mariadbd.
# Run from a basedir containing ./cl with a running server on its socket.

if [ ! -x ./cl ]; then
  echo "Error: ./cl not found in current directory. Run from a mariadb-qa basedir with a running server."
  exit 1
fi

OUTDIR=~/mariadb-qa/generator
SES_FILE=${OUTDIR}/dynvars_session.txt
GLB_FILE=${OUTDIR}/dynvars_global.txt
RAW=$(mktemp)
SES_TMP=$(mktemp)
GLB_TMP=$(mktemp)

# Use a non-whitespace field separator (\x1f / unit separator) so empty fields
# survive bash IFS coalescing of consecutive whitespace IFS chars.
SEP=$'\x1f'
# Sessions started by the QA framework often run with tiny tmp_*_table_size
# (e.g. tmp_disk_table_size=1024) which blocks materializing I_S.SYSTEM_VARIABLES.
# Raise them and SQL_BIG_SELECTS for the duration of this query.
echo "SET SESSION tmp_memory_table_size=134217728, SESSION tmp_disk_table_size=18446744073709551615, SESSION sql_big_selects=1; SELECT CONCAT(LOWER(VARIABLE_NAME),CHAR(31),VARIABLE_SCOPE,CHAR(31),VARIABLE_TYPE,CHAR(31),IFNULL(NUMERIC_MIN_VALUE,''),CHAR(31),IFNULL(NUMERIC_MAX_VALUE,''),CHAR(31),IFNULL(ENUM_VALUE_LIST,'')) FROM information_schema.SYSTEM_VARIABLES WHERE READ_ONLY='NO' ORDER BY VARIABLE_NAME" \
  | ./cl --skip-column-names --batch --raw 2>/dev/null \
  | grep -v '^CONCAT\|^Warning\|^$' > "$RAW"

# Discover which writable vars actually reject SET GLOBAL at runtime. Some are
# marked SESSION/BOTH in I_S but the server still throws ER 1228/1238 (e.g.
# tcp_nodelay, where the "global" value is a build-time socket-option default).
NO_GLOBAL=$(mktemp)
NO_SESSION=$(mktemp)
PROBE=$(mktemp)
NAMES=()
while IFS=$SEP read -r N _; do NAMES+=("$N"); done < "$RAW"

# Probe pass: try SET GLOBAL <var>=DEFAULT and SET SESSION <var>=DEFAULT for
# every writable var. Mariadb errors report "at line N" (Nth statement in the
# batch), so we map error lines back to var names.
#   ER 1228/1238: scope mismatch (session-only or global-only var).
#   ER 1230: no default value (DEFAULT keyword rejected).
#   ER 1210: WSREP / SET argument issue (e.g. galera-not-started, tcp_nodelay).
#   ER 1621: session var is read-only, use SET GLOBAL instead.
probe() {  # $1=verb (GLOBAL|SESSION) $2=output_file
  awk -v V="$1" -F$'\x1f' '{ print "SET " V " " $1 "=DEFAULT;" }' "$RAW" > "$PROBE"
  ./cl --force --batch --skip-column-names < "$PROBE" 2>&1 \
    | awk 'match($0,/^ERROR (1228|1238|1230|1210|1621).* at line ([0-9]+)/,m) { print m[2] }' \
    | sort -nu > "$PROBE.lines"
  : > "$2"
  while read -r ln; do
    echo "${NAMES[$((ln-1))]}" >> "$2"
  done < "$PROBE.lines"
  sort -u "$2" -o "$2"
}
probe GLOBAL "$NO_GLOBAL"
probe SESSION "$NO_SESSION"
rm -f "$PROBE" "$PROBE.lines"

emit() {  # $1=name $2=value (already quoted/formatted as needed) $3=scope
  # MariaDB I_S exposes four scopes:
  #   GLOBAL        -> only SET GLOBAL works (e.g. sync_binlog)
  #   BOTH          -> both forms work (typical tunable)
  #   SESSION       -> usually both forms work (SET GLOBAL sets the new-session default)
  #   SESSION ONLY  -> only SET SESSION works (per-statement transient, e.g. timestamp)
  # The runtime probe ($NO_GLOBAL / $NO_SESSION) overrides I_S where the server
  # rejects the verb despite the documented scope (e.g. tcp_nodelay, net_buffer_length).
  local skip_global=0 skip_session=0
  grep -qx "$1" "$NO_GLOBAL" 2>/dev/null && skip_global=1
  grep -qx "$1" "$NO_SESSION" 2>/dev/null && skip_session=1
  if [ $skip_global -eq 0 ]; then
    case "$3" in
      GLOBAL|SESSION|BOTH)
        echo "${1}=${2}" >> "$GLB_TMP" ;;
    esac
  fi
  if [ $skip_session -eq 0 ]; then
    case "$3" in
      SESSION|BOTH|"SESSION ONLY")
        echo "${1}=${2}" >> "$SES_TMP" ;;
    esac
  fi
}

# Bash arithmetic handles up to 2^63-1; use awk for big-number comparisons.
ge() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a+0 >= b+0) }'; }
le() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a+0 <= b+0) }'; }

while IFS=$SEP read -r NAME SCOPE TYPE MIN MAX ENUMLIST; do
  [ -z "$NAME" ] && continue
  case "$TYPE" in
    BOOLEAN)
      emit "$NAME" "0" "$SCOPE"
      emit "$NAME" "1" "$SCOPE"
      emit "$NAME" "DEFAULT" "$SCOPE"
      ;;
    ENUM)
      IFS=',' read -ra ENUMARR <<< "$ENUMLIST"
      for e in "${ENUMARR[@]}"; do
        emit "$NAME" "'${e}'" "$SCOPE"
      done
      emit "$NAME" "DEFAULT" "$SCOPE"
      ;;
    SET)
      # SET: comma-separated flag names. Empty string is rejected for many SET
      # vars (e.g. log_output, create_tmp_table_binlog_formats), so it's omitted.
      IFS=',' read -ra ENUMARR <<< "$ENUMLIST"
      for e in "${ENUMARR[@]}"; do
        emit "$NAME" "'${e}'" "$SCOPE"
      done
      ALL_JOINED=$(IFS=,; echo "${ENUMARR[*]}")
      emit "$NAME" "'${ALL_JOINED}'" "$SCOPE"
      emit "$NAME" "DEFAULT" "$SCOPE"
      ;;
    FLAGSET)
      # FLAGSET: each flag carries =on or =off (e.g. optimizer_switch='index_merge=on').
      # The bare flag name is rejected with ER 1231.
      IFS=',' read -ra ENUMARR <<< "$ENUMLIST"
      for e in "${ENUMARR[@]}"; do
        # Skip the 'default' pseudo-flag itself; it surfaces below.
        [ "$e" = "default" ] && continue
        emit "$NAME" "'${e}=on'" "$SCOPE"
        emit "$NAME" "'${e}=off'" "$SCOPE"
      done
      emit "$NAME" "'default'" "$SCOPE"
      emit "$NAME" "DEFAULT" "$SCOPE"
      ;;
    "BIGINT UNSIGNED"|"INT UNSIGNED"|INT)
      emit "$NAME" "DEFAULT" "$SCOPE"
      # MIN is always useful (often a corner case like 2048 for buffer sizes).
      [ -n "$MIN" ] && emit "$NAME" "$MIN" "$SCOPE"
      # For narrow ranges (MAX<=100), include MAX; wider ranges are capped at 1048576
      # so we don't trigger OOM/perf cliffs by setting buffer sizes to 16 exabytes.
      if [ -n "$MAX" ] && le "$MAX" 100; then
        emit "$NAME" "$MAX" "$SCOPE"
      fi
      for v in 0 1 8 64 1024 65536 1048576; do
        [ -n "$MIN" ] && ! ge "$v" "$MIN" && continue
        [ -n "$MAX" ] && ! le "$v" "$MAX" && continue
        emit "$NAME" "$v" "$SCOPE"
      done
      ;;
    DOUBLE)
      emit "$NAME" "DEFAULT" "$SCOPE"
      [ -n "$MIN" ] && emit "$NAME" "$MIN" "$SCOPE"
      if [ -n "$MAX" ] && le "$MAX" 100; then
        emit "$NAME" "$MAX" "$SCOPE"
      fi
      for v in 0 0.5 1 10 100; do
        [ -n "$MIN" ] && ! ge "$v" "$MIN" && continue
        [ -n "$MAX" ] && ! le "$v" "$MAX" && continue
        emit "$NAME" "$v" "$SCOPE"
      done
      ;;
    VARCHAR)
      # VARCHAR values are too varied to enumerate safely; rely on DEFAULT.
      emit "$NAME" "DEFAULT" "$SCOPE"
      ;;
    *)
      emit "$NAME" "DEFAULT" "$SCOPE"
      ;;
  esac
done < "$RAW"

# Deduplicate while preserving order.
awk '!seen[$0]++' "$SES_TMP" > "$SES_FILE"
awk '!seen[$0]++' "$GLB_TMP" > "$GLB_FILE"
echo "Probe: $(wc -l < "$NO_GLOBAL") vars rejected SET GLOBAL, $(wc -l < "$NO_SESSION") rejected SET SESSION."
rm -f "$RAW" "$SES_TMP" "$GLB_TMP" "$NO_GLOBAL" "$NO_SESSION"

echo "Wrote:"
echo "  $SES_FILE: $(wc -l < $SES_FILE) entries"
echo "  $GLB_FILE: $(wc -l < $GLB_FILE) entries"
