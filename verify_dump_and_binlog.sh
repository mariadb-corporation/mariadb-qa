#!/bin/bash
# verify_dump_and_binlog.sh — MariaDB dump/binlog roundtrip fidelity checker.
#
# Two modes:
#   (1) Default loop mode: repeatedly
#         - generator.sh produces random SQL
#         - ./anc [--log_bin]  (fresh install + start)
#         - load the generated SQL
#         - snapshot checksums
#         - dump via mariadb-dump  OR  flush logs + copy binlogs
#         - ./anc  (fresh install + start again)
#         - restore via mariadb client OR via mariadb-binlog
#         - snapshot checksums
#         - compare; on diff, save the SQL and stop
#
#   (2) --verify FILE single-shot mode: takes FILE, runs the same roundtrip,
#       exits 0 if checksums match, 1 if they differ, 2 on infra error.
#       Intended for reducer.sh MODE=11 (which implements its own native path).
#
# Must be executed from inside a basedir that was set up by ~/mariadb-qa/startup.sh
# (expects ./anc, ./cl, ./bin/mariadb, ./bin/mariadb-dump, ./bin/mariadb-binlog, ./socket.sock).

set -u

# ---------- defaults ----------
MODE="dump"               # dump | binlog
ITERATIONS=0              # 0 = unlimited (loop until diff)
QUERIES=2000              # queries per generator run
BINLOG_FORMAT="MIXED"     # MIXED | ROW | STATEMENT
KEEP_ARTIFACTS=0          # preserve dump.sql/binlogs even when no diff
VERIFY_FILE=""            # if set: single-shot verify mode on this file
BASEDIR="${PWD}"
MYEXTRA=""                # additional mysqld options
GENERATOR_DIR="${HOME}/mariadb-qa/generator"
WORKSUBDIR="verify_work"  # under $BASEDIR
QUIET=0

usage(){
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Loop mode (default):
    --mode=dump|binlog       Restore mechanism (default: $MODE)
    --iterations=N           Stop after N iterations (default: unlimited)
    --queries=N              Queries per generator run (default: $QUERIES)
    --binlog-format=FMT      MIXED|ROW|STATEMENT (binlog mode only; default: $BINLOG_FORMAT)
    --myextra="..."          Extra mysqld startup options
    --keep-artifacts         Keep dump.sql/binlog snapshots on success
    --quiet                  Less output

Single-shot (reducer.sh MODE=11 helper):
    --verify=FILE            Run roundtrip on FILE; exit 0=match, 1=diff, 2=error

Artifacts land in  \$BASEDIR/$WORKSUBDIR/ .
On a diff, the failing SQL is saved as  \$BASEDIR/verify_failed.sql
and a timestamped copy  \$BASEDIR/verify_failed_<epoch>.sql .

This script assumes PWD (or --basedir) is a st/startup.sh-set-up basedir.
EOF
  exit 1
}

# ---------- arg parsing ----------
for arg in "$@"; do
  case "$arg" in
    --mode=*)           MODE="${arg#*=}" ;;
    --iterations=*)     ITERATIONS="${arg#*=}" ;;
    --queries=*)        QUERIES="${arg#*=}" ;;
    --binlog-format=*)  BINLOG_FORMAT="${arg#*=}" ;;
    --myextra=*)        MYEXTRA="${arg#*=}" ;;
    --verify=*)         VERIFY_FILE="${arg#*=}" ;;
    --basedir=*)        BASEDIR="${arg#*=}" ;;
    --keep-artifacts)   KEEP_ARTIFACTS=1 ;;
    --quiet)            QUIET=1 ;;
    -h|--help)          usage ;;
    *) echo "Unknown argument: $arg"; usage ;;
  esac
done

case "$MODE" in
  dump|binlog) ;;
  *) echo "--mode must be 'dump' or 'binlog' (got: $MODE)"; exit 2 ;;
esac
case "$BINLOG_FORMAT" in
  MIXED|ROW|STATEMENT) ;;
  *) echo "--binlog-format must be MIXED|ROW|STATEMENT"; exit 2 ;;
esac

# ---------- env ----------
cd "$BASEDIR" || { echo "Cannot cd to basedir: $BASEDIR"; exit 2; }
BASEDIR="$(pwd -P)"  # canonical
WORKDIR="${BASEDIR}/${WORKSUBDIR}"
mkdir -p "$WORKDIR"

SOCKET="${BASEDIR}/socket.sock"
CLI_BIN="${BASEDIR}/bin/mariadb"
DUMP_BIN="${BASEDIR}/bin/mariadb-dump"
BINLOG_BIN="${BASEDIR}/bin/mariadb-binlog"
[ -x "$CLI_BIN" ]    || { echo "missing: $CLI_BIN (is this a basedir?)"; exit 2; }
[ -x "$DUMP_BIN" ]   || { echo "missing: $DUMP_BIN"; exit 2; }
[ -x "$BINLOG_BIN" ] || { echo "missing: $BINLOG_BIN"; exit 2; }
[ -x "${BASEDIR}/anc" ] || { echo "missing ./anc in basedir. Run ~/mariadb-qa/startup.sh first."; exit 2; }

log(){ [ "$QUIET" -eq 1 ] || echo "$(date +'%F %T') [vdb] $*"; }
err(){ echo "$(date +'%F %T') [vdb][ERROR] $*" >&2; }

cli_exec(){
  # One-shot exec; $1 = SQL.  Uses the basedir's mariadb client directly.
  "$CLI_BIN" -uroot -S"$SOCKET" --force -Nse "$1" 2>>"$WORKDIR/cli.err"
}

cli_exec_snapshot(){
  # Snapshot queries use the same session state as any user connection would
  # see after `anc` + load.  If that differs between before and after, it IS a
  # fidelity difference — sql_mode, charsets, and the like are server state
  # that a correct dump/restore cycle must preserve.  So: no session mutation.
  "$CLI_BIN" -uroot -S"$SOCKET" --force -Nse "$1" 2>>"$WORKDIR/cli.err"
}

cli_source(){
  # Pipe an SQL file through the client, after filtering statements that would
  # leave data uncommitted from the dump connection's perspective.
  # Reason: `SET autocommit=0` (and similar) start an implicit transaction; any
  # subsequent DML stays invisible to the separate mariadb-dump session until a
  # COMMIT.  That produces false-positive snapshot diffs (before: in-transaction
  # state; after: only-committed state).  Strip those lines and COMMIT at the end.
  local src="$1"
  local filtered="$WORKDIR/load.filtered.sql"
  grep -Eiv '^[[:space:]]*SET[[:space:]]+([A-Z_]+[[:space:]]*=[[:space:]]*[^,;]*,[[:space:]]*)*(@@|@@GLOBAL\.|@@SESSION\.|SESSION[[:space:]]+|GLOBAL[[:space:]]+)?autocommit[[:space:]]*=' "$src" >"$filtered"
  "$CLI_BIN" -uroot -S"$SOCKET" --binary-mode --force test <"$filtered" >"$WORKDIR/load.out" 2>>"$WORKDIR/cli.err"
  # Flush any in-flight transactions before the snapshot/dump runs in a fresh session.
  "$CLI_BIN" -uroot -S"$SOCKET" --force -Nse "COMMIT" >>"$WORKDIR/load.out" 2>>"$WORKDIR/cli.err"
}

server_up(){
  "$CLI_BIN" -uroot -S"$SOCKET" -Nse "SELECT 1" >/dev/null 2>&1
}

wait_for_server(){
  for _ in $(seq 1 90); do server_up && return 0; sleep 0.25; done
  return 1
}

# Build a canonical "snapshot" of all user DB/table/view/routine state.
# System DBs are excluded. Output: $1 (destination file), sorted & stable.
take_snapshot(){
  local out="$1"
  : >"$out"
  server_up || { err "server not responding during snapshot"; return 2; }
  local dbs
  dbs=$(cli_exec_snapshot "SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ('mysql','information_schema','performance_schema','sys') ORDER BY schema_name")
  if [ -z "$dbs" ]; then
    echo "# no user databases" >>"$out"
    return 0
  fi
  local db
  while IFS= read -r db; do
    [ -z "$db" ] && continue
    echo "### DATABASE: $db" >>"$out"
    # Tables and views
    local tv
    tv=$(cli_exec_snapshot "SELECT table_name, table_type FROM information_schema.tables WHERE table_schema='$db' ORDER BY table_name, table_type")
    local tbl typ
    while IFS=$'\t' read -r tbl typ; do
      [ -z "$tbl" ] && continue
      if [ "$typ" = "VIEW" ]; then
        echo "## VIEW $db.$tbl" >>"$out"
        cli_exec_snapshot "SHOW CREATE VIEW \`$db\`.\`$tbl\`" >>"$out" 2>&1
      else
        echo "## TABLE $db.$tbl" >>"$out"
        # SHOW CREATE — schema fidelity (incl. AUTO_INCREMENT)
        cli_exec_snapshot "SHOW CREATE TABLE \`$db\`.\`$tbl\`" >>"$out" 2>&1
        # Row count + checksum — data fidelity
        cli_exec_snapshot "SELECT 'count',COUNT(*) FROM \`$db\`.\`$tbl\`" >>"$out" 2>&1
        cli_exec_snapshot "CHECKSUM TABLE \`$db\`.\`$tbl\` EXTENDED" >>"$out" 2>&1
      fi
    done <<<"$tv"
    # Routines, triggers, events
    echo "## ROUTINES $db" >>"$out"
    cli_exec_snapshot "SELECT routine_type, routine_name FROM information_schema.routines WHERE routine_schema='$db' ORDER BY routine_type, routine_name" >>"$out"
    local rt rn
    while IFS=$'\t' read -r rt rn; do
      [ -z "$rn" ] && continue
      cli_exec_snapshot "SHOW CREATE $rt \`$db\`.\`$rn\`" >>"$out" 2>&1
    done < <(cli_exec_snapshot "SELECT routine_type, routine_name FROM information_schema.routines WHERE routine_schema='$db' ORDER BY routine_type, routine_name")
    echo "## TRIGGERS $db" >>"$out"
    cli_exec_snapshot "SHOW TRIGGERS FROM \`$db\`" >>"$out" 2>&1
    echo "## EVENTS $db" >>"$out"
    cli_exec_snapshot "SHOW EVENTS FROM \`$db\`" >>"$out" 2>&1
  done <<<"$dbs"
  return 0
}

generate_sql(){
  # Produce $WORKDIR/gen.sql via generator.sh.
  local qcount="$1"
  local target="$WORKDIR/gen.sql"
  [ -d "$GENERATOR_DIR" ] || { err "generator dir not found: $GENERATOR_DIR"; return 2; }
  [ -x "$GENERATOR_DIR/generator.sh" ] || { err "generator.sh not executable"; return 2; }
  # generator.sh hard-codes OUTPUT_FILE=out and runs in its own dir, so two
  # concurrent invocations clobber each other's out.sql.  Serialize with flock
  # over a lock under the generator dir itself (so it works across basedirs).
  (
    flock 9
    cd "$GENERATOR_DIR" && ./generator.sh "$qcount" >"$WORKDIR/generator.log" 2>&1
    local rc=$?
    if [ $rc -ne 0 ] || [ ! -s "$GENERATOR_DIR/out.sql" ]; then
      echo "GENFAIL:$rc" >"$WORKDIR/genstatus"
      exit $rc
    fi
    mv "$GENERATOR_DIR/out.sql" "$target"
    echo "OK" >"$WORKDIR/genstatus"
  ) 9>"$GENERATOR_DIR/.vdb_generate.lock"
  if ! grep -q '^OK$' "$WORKDIR/genstatus" 2>/dev/null; then
    err "generator.sh failed. See $WORKDIR/generator.log"
    return 2
  fi
  echo "$target"
}

anc_start(){
  # Fresh install + start.  $1 may contain extra mysqld args ("--log_bin ...").
  local extra="${1:-}"
  log "anc $extra"
  # ./anc writes to stdout/stderr; keep it quiet.
  ( cd "$BASEDIR" && ./anc ${extra} >"$WORKDIR/anc.log" 2>&1 )
  wait_for_server || { err "server failed to come up after anc"; return 2; }
}

do_dump(){
  local dest="$1"
  log "mariadb-dump → $dest"
  # Dump all user DBs with routines/triggers/events.  Skip system DBs.
  local user_dbs
  user_dbs=$(cli_exec "SELECT GROUP_CONCAT(schema_name SEPARATOR ' ') FROM information_schema.schemata WHERE schema_name NOT IN ('mysql','information_schema','performance_schema','sys')")
  if [ -z "$user_dbs" ] || [ "$user_dbs" = "NULL" ]; then
    # Nothing to dump — write an empty marker dump.
    : >"$dest"
    return 0
  fi
  # shellcheck disable=SC2086
  "$DUMP_BIN" -uroot -S"$SOCKET" --force --hex-blob --routines --triggers --events \
      --skip-dump-date --skip-comments \
      --databases $user_dbs >"$dest" 2>"$WORKDIR/dump.err"
  local rc=$?
  if [ $rc -ne 0 ]; then
    err "mariadb-dump rc=$rc; see $WORKDIR/dump.err"
    return 2
  fi
}

do_dump_restore(){
  local dest="$1"
  log "restoring dump from $dest"
  "$CLI_BIN" -uroot -S"$SOCKET" --binary-mode --force <"$dest" >"$WORKDIR/restore.out" 2>>"$WORKDIR/cli.err"
}

capture_binlogs(){
  # Called before anc_start() wipes data/.  Copy out all binlog files.
  local dest_dir="$1"
  log "capturing binlogs → $dest_dir"
  rm -rf "$dest_dir"
  mkdir -p "$dest_dir"
  # Flush so all events are in the current binlog and the index is consistent.
  cli_exec "FLUSH LOGS" >/dev/null
  local files
  files=$(cli_exec "SHOW BINARY LOGS" | awk '{print $1}')
  if [ -z "$files" ]; then
    err "SHOW BINARY LOGS returned nothing — was the server started with --log_bin?"
    return 2
  fi
  local f
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    cp -a "$BASEDIR/data/$f" "$dest_dir/" 2>>"$WORKDIR/cli.err" || {
      err "failed to copy binlog file $f"; return 2; }
  done <<<"$files"
}

replay_binlogs(){
  local src_dir="$1"
  log "replaying binlogs from $src_dir"
  local files
  files=$(ls -1 "$src_dir"/ 2>/dev/null | sort)
  if [ -z "$files" ]; then
    err "no binlog files in $src_dir"; return 2
  fi
  # mariadb-binlog takes the files in order and emits SQL.
  # shellcheck disable=SC2086
  ( cd "$src_dir" && "$BINLOG_BIN" --disable-log-bin $files ) \
      | "$CLI_BIN" -uroot -S"$SOCKET" --binary-mode --force \
      >"$WORKDIR/binlog_replay.out" 2>>"$WORKDIR/cli.err"
}

# --- The core roundtrip: take an SQL file, do the full dump/binlog roundtrip,
#     return 0 if snapshots match, 1 if diff, 2 on infra error.
roundtrip_once(){
  local sqlfile="$1"
  local before="$WORKDIR/snap_before.txt"
  local after="$WORKDIR/snap_after.txt"
  local dumpfile="$WORKDIR/dump.sql"
  local binlog_snapshot="$WORKDIR/binlogs"
  rm -f "$before" "$after" "$dumpfile" "$WORKDIR/cli.err"

  local start_extra=""
  if [ "$MODE" = "binlog" ]; then
    start_extra="--log_bin --binlog_format=$BINLOG_FORMAT --server-id=100"
  fi

  # First anc (with user --myextra appended)
  anc_start "$start_extra $MYEXTRA" || return 2

  log "loading SQL: $sqlfile"
  cli_source "$sqlfile"

  take_snapshot "$before" || return 2

  if [ "$MODE" = "dump" ]; then
    do_dump "$dumpfile" || return 2
  else
    capture_binlogs "$binlog_snapshot" || return 2
  fi

  # Second anc: fresh instance (binlog mode restarts with --log_bin too,
  # otherwise server-id changes which is cosmetic; keep it consistent).
  anc_start "$start_extra $MYEXTRA" || return 2

  if [ "$MODE" = "dump" ]; then
    do_dump_restore "$dumpfile" || return 2
  else
    replay_binlogs "$binlog_snapshot" || return 2
  fi

  take_snapshot "$after" || return 2

  if diff -u "$before" "$after" >"$WORKDIR/snap.diff" 2>&1; then
    log "snapshots MATCH"
    return 0
  else
    log "snapshots DIFFER — see $WORKDIR/snap.diff"
    return 1
  fi
}

# ===================================================================
# --verify single-shot path (used by reducer.sh MODE=11 helper or manual)
# ===================================================================
if [ -n "$VERIFY_FILE" ]; then
  [ -r "$VERIFY_FILE" ] || { err "--verify file not readable: $VERIFY_FILE"; exit 2; }
  roundtrip_once "$VERIFY_FILE"
  rc=$?
  exit $rc
fi

# ===================================================================
# loop mode
# ===================================================================
log "loop mode: MODE=$MODE QUERIES=$QUERIES BINLOG_FORMAT=$BINLOG_FORMAT BASEDIR=$BASEDIR"
ITER=0
while :; do
  ITER=$((ITER + 1))
  if [ "$ITERATIONS" -gt 0 ] && [ $ITER -gt "$ITERATIONS" ]; then
    log "reached iteration cap ($ITERATIONS); stopping with no diff"
    exit 0
  fi
  log "=== iteration $ITER ==="
  GENSQL=$(generate_sql "$QUERIES") || exit 2

  roundtrip_once "$GENSQL"
  rc=$?
  case $rc in
    0)
      log "iter $ITER: match"
      if [ "$KEEP_ARTIFACTS" -eq 0 ]; then
        rm -f "$WORKDIR/dump.sql" "$WORKDIR/snap_before.txt" "$WORKDIR/snap_after.txt"
        rm -rf "$WORKDIR/binlogs"
      fi
      ;;
    1)
      TS=$(date +%s)
      cp -a "$GENSQL" "$BASEDIR/verify_failed.sql"
      cp -a "$GENSQL" "$BASEDIR/verify_failed_${TS}.sql"
      cp -a "$WORKDIR/snap.diff" "$BASEDIR/verify_failed_${TS}.diff" 2>/dev/null
      [ "$MODE" = "dump" ] && cp -a "$WORKDIR/dump.sql" "$BASEDIR/verify_failed_${TS}.dump.sql" 2>/dev/null
      [ "$MODE" = "binlog" ] && cp -a "$WORKDIR/binlogs" "$BASEDIR/verify_failed_${TS}.binlogs" 2>/dev/null
      log "DIFF FOUND on iteration $ITER"
      log "  failing SQL: $BASEDIR/verify_failed.sql  (and verify_failed_${TS}.sql)"
      log "  diff:        $BASEDIR/verify_failed_${TS}.diff"
      log ""
      log "To reduce, use reducer.sh with:"
      log "    MODE=11"
      log "    MODE11_TYPE=$MODE"
      log "    INPUTFILE=$BASEDIR/verify_failed.sql"
      log "    BASEDIR=$BASEDIR"
      exit 1
      ;;
    2)
      err "infra error on iteration $ITER; continuing"
      ;;
    *)
      err "unexpected rc=$rc; continuing"
      ;;
  esac
done
