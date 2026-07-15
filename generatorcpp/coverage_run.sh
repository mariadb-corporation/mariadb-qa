#!/bin/bash
# Crash-resilient LLVM coverage harness for the SQL generator (proposal #1).
# Profraw flushes only on clean exit, and fuzz SQL can crash mariadbd -- so we run
# the corpus in chunks, clean-shutdown (flush) after each, restart on crash, and
# merge every per-instance profraw. Datadir persists across restarts (schema deepens).
set -u
BT="${BT:-/tmp/13.0_cov_opt}"
BIN=$BT/sql/mariadbd
CLIENT="$BT/client/mariadb --no-defaults -uroot"
ADMIN="$BT/client/mariadb-admin --no-defaults -uroot"
SEED="${SEED:-$HOME/mariadb-qa/generatorcpp/cov_seed.sql}"
GEN="${GEN:-$HOME/mariadb-qa/generatorcpp/generator}"
PQUERY="${PQUERY:-$HOME/mariadb-qa/pquery/pquery2-md}"   # one line = one query (no ';' split); the CLI would shatter compound bodies
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
( cd "$HOME/mariadb-qa/generatorcpp" && "$GEN" --threads "$GTHREADS" ${WEIGHTS:+--weights "$WEIGHTS"} --output "$WORK/corpus.sql" "$NQ" ) >/dev/null 2>&1
# Drop wedge statements (pcre2 catastrophic REGEXP, blocking waits, slave-control) and inject a
# periodic UNLOCK TABLES so a lone LOCK TABLES cannot poison the rest of a chunk with ER_TABLE_NOT_LOCKED
FILTER='REGEXP|RLIKE|debug_sync|WAIT_FOR|GET_LOCK|SLEEP[[:space:]]*\(|(START|STOP|RESET)[[:space:]]+(SLAVE|REPLICA)|CHANGE[[:space:]]+MASTER'
grep -ivE "$FILTER" "$WORK/corpus.sql" | awk 'NR%15==0{print "UNLOCK TABLES;"; print "ROLLBACK;"; print "SET SESSION TRANSACTION READ WRITE;"; print "SET @@SESSION.transaction_read_only=0;"} {print}' > "$WORK/corpus.f.sql"
split -l "$CHUNK" -d -a 4 "$WORK/corpus.f.sql" "$WORK/chunk_"
nch=$(ls "$WORK"/chunk_* 2>/dev/null | wc -l); echo "    corpus=$(wc -l < "$WORK/corpus.f.sql") lines, $nch chunks"

echo "[$(date +%T)] start + seed"
start_server || { echo "initial start failed"; tail "$WORK/err.log"; exit 1; }
$CLIENT --socket="$SOCK" --force < "$SEED" 2>"$WORK/seed_err.log"

ci=0; restarts=0
for ch in "$WORK"/chunk_*; do
  ci=$((ci+1))
  alive || { start_server || { sleep 3; start_server; }; restarts=$((restarts+1)); }
  split -n l/$CPAR -d "$ch" "$ch.sp_" 2>/dev/null || cp "$ch" "$ch.sp_00"
  pids=()
  for sp in "$ch".sp_*; do
    pqlog="$WORK/pq_${ci}_$(basename "$sp")"; mkdir -p "$pqlog"
    timeout "$TMO" "$PQUERY" --infile="$sp" --socket="$SOCK" --database=test --user=root \
      --threads=1 --queries-per-thread="$(wc -l < "$sp")" --no-shuffle --logdir="$pqlog" >/dev/null 2>&1 &
    pids+=($!)
  done
  wait "${pids[@]}" 2>/dev/null
  if ! alive; then                    # server crashed this chunk - preserve evidence before the next restart clobbers it
    cd="$WORK/crashes/$ci"; mkdir -p "$cd"
    [ -e "$DATA/core" ] && mv "$DATA/core" "$cd/core"
    cp "$WORK/err.log" "$cd/err.log" 2>/dev/null; cp "$ch" "$cd/chunk.sql" 2>/dev/null
    [ -e "$cd/core" ] && gdb -batch -iex 'set debuginfod enabled off' -ex bt "$BIN" "$cd/core" >"$cd/bt.txt" 2>&1
    echo; echo "[$(date +%T)] CRASH in chunk $ci -> $cd (get UID via gdb/tt before rerun)"
  fi
  rm -f "$ch".sp_*
  stop_server
  [ "$ci" -lt "$nch" ] && { start_server || { sleep 3; start_server; }; }
  printf "\r    chunk %d/%d (restarts=%d)   " "$ci" "$nch" "$restarts"
done
stop_server; echo

# aggregate pquery per-part success rate (a low rate means the corpus wastes coverage on errors)
tot=0; fail=0
for g in "$WORK"/pq_*/*general.log; do
  [ -e "$g" ] || continue
  line=$(grep -oE '[0-9]+/[0-9]+ queries failed' "$g" | head -1); [ -z "$line" ] && continue
  f=${line%%/*}; rest=${line#*/}; t=${rest%% *}; fail=$((fail+f)); tot=$((tot+t))
done
[ "$tot" -gt 0 ] && echo "[$(date +%T)] pquery success: $((tot-fail))/$tot ($(((tot-fail)*100/tot))%)"

echo "[$(date +%T)] profraw files: $(ls "$PROF"/*.profraw 2>/dev/null | wc -l), restarts: $restarts"
ls "$PROF"/*.profraw >/dev/null 2>&1 || { echo "NO PROFRAW"; exit 2; }
llvm-profdata merge -sparse "$PROF"/*.profraw -o "$WORK/cov.profdata" 2>"$WORK/merge.log" || { echo merge failed; cat "$WORK/merge.log"; exit 2; }

report_line(){ llvm-cov report "$BIN" -instr-profile="$WORK/cov.profdata" "$@" 2>/dev/null | tail -1 \
  | awk '{printf "lines %s/%s = %s\n", $(NF-2)-$(NF-1), $(NF-2), $NF}'; }
echo "==================== COVERAGE ($TAG) ===================="
printf "OVERALL  "; report_line
for d in sql storage/innobase strings; do printf "%-18s " "$d"; report_line "$BT/$d/"; done
echo "profdata: $WORK/cov.profdata"
