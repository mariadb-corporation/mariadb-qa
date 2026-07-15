#!/bin/bash
# Coverage scenario: 2-node Galera cluster (rsync SST) on the instrumented binary plus the
# separate Galera provider. node1 replays the corpus, node2 applies the writesets, so
# wsrep_* / service_wsrep apply code is exercised. Both nodes are profraw-instrumented and
# merged. Provider defaults to /test/galera_4x_dbg/libgalera_smm.so.
set -u
BT="${BT:-/tmp/13.0_cov_opt}"
BIN="$BT/sql/mariadbd"
CLIENT="$BT/client/mariadb --no-defaults -uroot"
ADMIN="$BT/client/mariadb-admin --no-defaults -uroot"
PROVIDER="${PROVIDER:-/test/galera_4x_dbg/libgalera_smm.so}"
SEED="${SEED:-$HOME/mariadb-qa/generatorcpp/cov_seed.sql}"
GEN="${GEN:-$HOME/mariadb-qa/generatorcpp/generator}"
NQ="${NQ:-200000}"; CHUNK="${CHUNK:-20000}"; GTHREADS="${GTHREADS:-$(nproc)}"
TMO="${TMO:-150}"; TAG="${TAG:-galera}"
P1="${P1:-3411}"; P2="${P2:-3412}"; G1="${G1:-4567}"; G2="${G2:-4568}"
WORK="${WORK:-/data/cov/covrun_$TAG}"
[ -r "$PROVIDER" ] || { echo "provider not found: $PROVIDER"; exit 1; }
D1=$WORK/n1; D2=$WORK/n2; PR1=$WORK/prof1; PR2=$WORK/prof2
S1=$WORK/n1.sock; S2=$WORK/n2.sock
rm -rf "$WORK"; mkdir -p "$D1" "$D2" "$PR1" "$PR2"
FILTER='REGEXP|RLIKE|debug_sync|WAIT_FOR|GET_LOCK|SLEEP[[:space:]]*\(|(START|STOP|RESET)[[:space:]]+(SLAVE|REPLICA)|CHANGE[[:space:]]+MASTER'

start(){ # $1=n1|n2 datadir prof sock port gport clusteraddr id newcluster
  local prof=$3 extra=""
  [ "$9" = 1 ] && extra="--wsrep-new-cluster"
  LLVM_PROFILE_FILE="$prof/cov-%p.profraw" \
  "$BIN" --no-defaults --basedir="$BT" --datadir="$2" --socket="$4" --port="$5" --server-id="$8" \
    --wsrep-on=ON --wsrep-provider="$PROVIDER" \
    --wsrep-cluster-address="$7" --wsrep-node-address="127.0.0.1:$6" \
    --wsrep-cluster-name=covcl --wsrep-sst-method=rsync --binlog-format=ROW \
    --log-bin="$WORK/$1-bin" --secure-file-priv= --performance-schema=ON --event-scheduler=OFF \
    --innodb-buffer-pool-size=512M --max-recursive-iterations=100000 \
    --log-error="$WORK/$1.err" $extra >/dev/null 2>&1 &
  eval "PID_$1=$!"
  for i in $(seq 1 120); do [ -S "$4" ] && return 0; sleep 1; done
  return 1
}
stop(){ $ADMIN --socket="$1" shutdown 2>/dev/null; }

for d in "$D1" "$D2"; do
  "$BT/scripts/mariadb-install-db" --no-defaults --srcdir="$BT" --datadir="$d" \
    --auth-root-authentication-method=normal >/dev/null 2>>"$WORK/install.log" || { echo install-db failed; exit 1; }
done
start n1 "$D1" "$PR1" "$S1" "$P1" "$G1" "gcomm://" 1 1 || { echo n1 bootstrap failed; tail "$WORK/n1.err"; exit 1; }
for i in $(seq 1 60); do
  sz=$($CLIENT --socket="$S1" -Nse "SHOW STATUS LIKE 'wsrep_cluster_size'" 2>/dev/null | awk '{print $2}')
  [ "$sz" = 1 ] && break; sleep 1
done
start n2 "$D2" "$PR2" "$S2" "$P2" "$G2" "gcomm://127.0.0.1:$G1" 2 0 || { echo n2 join failed; tail "$WORK/n2.err"; exit 1; }
for i in $(seq 1 90); do
  sz=$($CLIENT --socket="$S1" -Nse "SHOW STATUS LIKE 'wsrep_cluster_size'" 2>/dev/null | awk '{print $2}')
  [ "$sz" = 2 ] && break; sleep 1
done
[ "$sz" = 2 ] || { echo "cluster did not reach size 2"; exit 1; }

$CLIENT --socket="$S1" --force < "$SEED" 2>"$WORK/seed_err.log"
bash "$HOME/mariadb-qa/generatorcpp/cov_qkiller.sh" "$S1" & QK=$!
echo "[$(date +%T)] generate corpus ($NQ)"
( cd "$HOME/mariadb-qa/generatorcpp" && "$GEN" --threads "$GTHREADS" --output "$WORK/corpus.sql" "$NQ" ) >/dev/null 2>&1
grep -ivE "$FILTER" "$WORK/corpus.sql" | awk 'NR%15==0{print "UNLOCK TABLES;"} {print}' > "$WORK/corpus.f.sql"
split -l "$CHUNK" -d -a 4 "$WORK/corpus.f.sql" "$WORK/chunk_"
nch=$(ls "$WORK"/chunk_* 2>/dev/null | wc -l)
ci=0
for ch in "$WORK"/chunk_*; do
  ci=$((ci+1))
  timeout "$TMO" $CLIENT --socket="$S1" --force test < "$ch" >/dev/null 2>>"$WORK/run_err.log"
  printf "\r    chunk %d/%d   " "$ci" "$nch"
done
echo
kill "$QK" 2>/dev/null
stop "$S2"; stop "$S1"                                        # profraw flushes only on clean exit - wait for it
for i in $(seq 1 90); do kill -0 "${PID_n1:-0}" 2>/dev/null || kill -0 "${PID_n2:-0}" 2>/dev/null || break; sleep 1; done
for p in "${PID_n2:-}" "${PID_n1:-}"; do [ -n "$p" ] && kill -0 "$p" 2>/dev/null && kill -9 "$p" 2>/dev/null; done
mkdir -p "$WORK/prof_all"; cp "$PR1"/*.profraw "$PR2"/*.profraw "$WORK/prof_all/" 2>/dev/null
BT="$BT" bash "$HOME/mariadb-qa/generatorcpp/cov_measure.sh" "$WORK/prof_all" "$WORK/cov" "$TAG"
