#!/bin/bash
# Coverage scenario: crash recovery. Seed + replay some DML, then kill -9 the server (no
# clean shutdown) and restart, so InnoDB redo recovery (log0recv, trx recovery) runs on the
# restart. The recovery restart is then shut down cleanly to flush the profraw it produced.
set -u
BT="${BT:-/tmp/13.0_cov_opt}"
BIN="$BT/sql/mariadbd"
CLIENT="$BT/client/mariadb --no-defaults -uroot"
ADMIN="$BT/client/mariadb-admin --no-defaults -uroot"
SEED="${SEED:-$HOME/mariadb-qa/generatorcpp/cov_seed.sql}"
GEN="${GEN:-$HOME/mariadb-qa/generatorcpp/generator}"
NQ="${NQ:-60000}"; GTHREADS="${GTHREADS:-$(nproc)}"; TMO="${TMO:-120}"
TAG="${TAG:-recovery}"; PORT="${PORT:-3421}"; CYCLES="${CYCLES:-4}"
WORK="${WORK:-/data/cov/covrun_$TAG}"
PROF=$WORK/prof; DATA=$WORK/data; SOCK=$WORK/m.sock
rm -rf "$WORK"; mkdir -p "$PROF" "$DATA"
FILTER='REGEXP|RLIKE|debug_sync|WAIT_FOR|GET_LOCK|SLEEP[[:space:]]*\(|(START|STOP|RESET)[[:space:]]+(SLAVE|REPLICA)|CHANGE[[:space:]]+MASTER'

start(){
  LLVM_PROFILE_FILE="$PROF/cov-%p.profraw" \
  "$BIN" --no-defaults --basedir="$BT" --datadir="$DATA" --socket="$SOCK" --port="$PORT" \
    --secure-file-priv= --performance-schema=ON --event-scheduler=OFF --innodb-buffer-pool-size=512M \
    --max-recursive-iterations=100000 --log-error="$WORK/err.log" >/dev/null 2>&1 &
  SRV=$!
  for i in $(seq 1 90); do [ -S "$SOCK" ] && return 0; kill -0 $SRV 2>/dev/null || return 1; sleep 1; done
  return 1
}

"$BT/scripts/mariadb-install-db" --no-defaults --srcdir="$BT" --datadir="$DATA" \
  --auth-root-authentication-method=normal >/dev/null 2>"$WORK/install.log" || { echo install-db failed; exit 1; }
( cd "$HOME/mariadb-qa/generatorcpp" && "$GEN" --threads "$GTHREADS" --output "$WORK/corpus.sql" "$NQ" ) >/dev/null 2>&1
grep -ivE "$FILTER" "$WORK/corpus.sql" | awk 'NR%15==0{print "UNLOCK TABLES;"} {print}' > "$WORK/corpus.f.sql"

start || { echo "initial start failed"; exit 1; }
$CLIENT --socket="$SOCK" --force < "$SEED" 2>"$WORK/seed_err.log"
bash "$HOME/mariadb-qa/generatorcpp/cov_qkiller.sh" "$SOCK" & QK=$!
for c in $(seq 1 "$CYCLES"); do
  timeout "$TMO" $CLIENT --socket="$SOCK" --force test < "$WORK/corpus.f.sql" >/dev/null 2>>"$WORK/run_err.log"
  kill -9 "$SRV" 2>/dev/null; wait "$SRV" 2>/dev/null           # crash: no flush, dirty redo
  start || { echo "recovery restart $c failed"; tail "$WORK/err.log"; exit 1; }  # redo recovery runs here
  printf "\r    recovery cycle %d/%d   " "$c" "$CYCLES"
done
echo
kill "$QK" 2>/dev/null
$ADMIN --socket="$SOCK" shutdown 2>/dev/null                  # clean stop flushes the recovery profraw - wait for it
for i in $(seq 1 90); do kill -0 "$SRV" 2>/dev/null || break; sleep 1; done
kill -0 "$SRV" 2>/dev/null && kill -9 "$SRV" 2>/dev/null
BT="$BT" bash "$HOME/mariadb-qa/generatorcpp/cov_measure.sh" "$PROF" "$WORK/cov" "$TAG"
