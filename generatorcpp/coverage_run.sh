#!/bin/bash
# Crash-resilient LLVM coverage harness for the SQL generator (proposal #1).
# Profraw flushes only on clean exit, and fuzz SQL can crash mariadbd -- so we run
# the corpus in chunks, clean-shutdown (flush) after each, restart on crash, and
# merge every per-instance profraw. Datadir persists across restarts (schema deepens).
set -u
BT=/tmp/13.0_cov_opt
BIN=$BT/sql/mariadbd
CLIENT="$BT/client/mariadb --no-defaults -uroot"
ADMIN="$BT/client/mariadb-admin --no-defaults -uroot"
GEN="${GEN:-$HOME/mariadb-qa/generatorcpp/generator}"
NQ="${NQ:-500000}"
GTHREADS="${GTHREADS:-$(nproc)}"
CHUNK="${CHUNK:-20000}"
CPAR="${CPAR:-4}"
TAG="${TAG:-base}"
PORT="${PORT:-3399}"
TMO="${TMO:-180}"
WORK=/tmp/covrun_$TAG
PROF=$WORK/prof; DATA=$WORK/data; SOCK=$WORK/m.sock
rm -rf "$WORK"; mkdir -p "$PROF" "$DATA"

start_server(){
  LLVM_PROFILE_FILE="$PROF/cov-%p.profraw" \
  "$BIN" --no-defaults --basedir="$BT" --datadir="$DATA" --socket="$SOCK" --port="$PORT" \
    --secure-file-priv= ${SQLMODE:+--sql-mode="$SQLMODE"} ${EXTRA_OPTS:-} --log-error="$WORK/err.log" --innodb-buffer-pool-size=512M \
    --max-connections=256 --performance-schema=ON --max-recursive-iterations=100000 \
    --skip-slave-start --log-bin="$WORK/binlog" --server-id=1 --optimizer-trace-max-mem-size=1048576 >/dev/null 2>&1 &
  SRV=$!
  for i in $(seq 1 90); do [ -S "$SOCK" ] && return 0; kill -0 $SRV 2>/dev/null || return 1; sleep 1; done
  return 1
}
stop_server(){
  [ -n "${SRV:-}" ] || return 0
  $ADMIN --socket="$SOCK" shutdown 2>/dev/null
  for i in $(seq 1 60); do kill -0 $SRV 2>/dev/null || break; sleep 1; done
  kill -9 "$SRV" 2>/dev/null; SRV=""
}
alive(){ [ -n "${SRV:-}" ] && kill -0 "$SRV" 2>/dev/null && [ -S "$SOCK" ]; }

echo "[$(date +%T)] init datadir"
"$BT/scripts/mariadb-install-db" --no-defaults --srcdir="$BT" --datadir="$DATA" \
  --auth-root-authentication-method=normal >/dev/null 2>"$WORK/install.log" || { echo install-db failed; tail "$WORK/install.log"; exit 1; }

echo "[$(date +%T)] generate corpus ($NQ)"
( cd "$HOME/mariadb-qa/generatorcpp" && "$GEN" --threads "$GTHREADS" --output "$WORK/corpus.sql" "$NQ" ) >/dev/null 2>&1
split -l "$CHUNK" -d -a 4 "$WORK/corpus.sql" "$WORK/chunk_"
nch=$(ls "$WORK"/chunk_* 2>/dev/null | wc -l); echo "    corpus=$(wc -l < "$WORK/corpus.sql") lines, $nch chunks"

echo "[$(date +%T)] start + seed"
start_server || { echo "initial start failed"; tail "$WORK/err.log"; exit 1; }
$CLIENT --socket="$SOCK" --force < /tmp/cov_seed.sql 2>"$WORK/seed_err.log"

ci=0; restarts=0
for ch in "$WORK"/chunk_*; do
  ci=$((ci+1))
  alive || { start_server || { sleep 3; start_server; }; restarts=$((restarts+1)); }
  split -n l/$CPAR -d "$ch" "$ch.sp_" 2>/dev/null || cp "$ch" "$ch.sp_00"
  pids=()
  for sp in "$ch".sp_*; do
    timeout "$TMO" $CLIENT --socket="$SOCK" --force test < "$sp" >/dev/null 2>>"$WORK/run_err.log" &
    pids+=($!)
  done
  wait "${pids[@]}" 2>/dev/null
  rm -f "$ch".sp_*
  stop_server
  [ "$ci" -lt "$nch" ] && { start_server || { sleep 3; start_server; }; }
  printf "\r    chunk %d/%d (restarts=%d)   " "$ci" "$nch" "$restarts"
done
stop_server; echo

echo "[$(date +%T)] profraw files: $(ls "$PROF"/*.profraw 2>/dev/null | wc -l), restarts: $restarts"
ls "$PROF"/*.profraw >/dev/null 2>&1 || { echo "NO PROFRAW"; exit 2; }
llvm-profdata merge -sparse "$PROF"/*.profraw -o "$WORK/cov.profdata" 2>"$WORK/merge.log" || { echo merge failed; cat "$WORK/merge.log"; exit 2; }

report_line(){ llvm-cov report "$BIN" -instr-profile="$WORK/cov.profdata" "$@" 2>/dev/null | tail -1 \
  | awk '{printf "lines %s/%s = %s\n", $(NF-2)-$(NF-1), $(NF-2), $NF}'; }
echo "==================== COVERAGE ($TAG) ===================="
printf "OVERALL  "; report_line
for d in sql storage/innobase strings; do printf "%-18s " "$d"; report_line "$BT/$d/"; done
echo "profdata: $WORK/cov.profdata"
