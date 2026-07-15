#!/bin/bash
# Coverage scenario: primary + GTID replica. Exercises the replica APPLY path
# (slave.cc, rpl_parallel.cc, log_event_server.cc, sql_repl.cc) that single-node replay
# never reaches. The replica is set up and started BEFORE seeding, so it receives the seed
# schema. BINFMT selects the binlog format. Both servers are profraw-instrumented and their
# profraw is merged. Run cov_qkiller.sh against the primary socket during the replay.
set -u
BT="${BT:-/tmp/13.0_cov_opt}"
BIN="$BT/sql/mariadbd"
CLIENT="$BT/client/mariadb --no-defaults -uroot"
ADMIN="$BT/client/mariadb-admin --no-defaults -uroot"
SEED="${SEED:-$HOME/mariadb-qa/generatorcpp/cov_seed.sql}"
GEN="${GEN:-$HOME/mariadb-qa/generatorcpp/generator}"
NQ="${NQ:-200000}"; CHUNK="${CHUNK:-20000}"; GTHREADS="${GTHREADS:-$(nproc)}"
BINFMT="${BINFMT:-ROW}"; TMO="${TMO:-150}"; TAG="${TAG:-repl_$BINFMT}"
MP="${MP:-3401}"; SP="${SP:-3402}"
WORK="${WORK:-/data/cov/covrun_$TAG}"
MPROF=$WORK/prof_m; SPROF=$WORK/prof_s; MDATA=$WORK/data_m; SDATA=$WORK/data_s
MSOCK=$WORK/m.sock; SSOCK=$WORK/s.sock
rm -rf "$WORK"; mkdir -p "$MPROF" "$SPROF" "$MDATA" "$SDATA"

FILTER='REGEXP|RLIKE|debug_sync|WAIT_FOR|GET_LOCK|SLEEP[[:space:]]*\(|(START|STOP|RESET)[[:space:]]+(SLAVE|REPLICA)|CHANGE[[:space:]]+MASTER'

start(){ # $1=role datadir prof sock port serverid
  local prof=$3
  LLVM_PROFILE_FILE="$prof/cov-%p.profraw" \
  "$BIN" --no-defaults --basedir="$BT" --datadir="$2" --socket="$4" --port="$5" \
    --server-id="$6" --log-bin="$WORK/$1-bin" --binlog-format="$BINFMT" --gtid-strict-mode=0 \
    --secure-file-priv= --skip-slave-start --performance-schema=ON --event-scheduler=OFF \
    --slave-skip-errors=ALL --slave-parallel-threads=4 --max-recursive-iterations=100000 \
    --log-error="$WORK/$1.err" --innodb-buffer-pool-size=512M --max-connections=256 >/dev/null 2>&1 &
  eval "PID_$1=$!"
  for i in $(seq 1 90); do [ -S "$4" ] && return 0; sleep 1; done
  return 1
}
stop(){ $ADMIN --socket="$1" shutdown 2>/dev/null; }

for r in m s; do
  d=$([ $r = m ] && echo "$MDATA" || echo "$SDATA")
  "$BT/scripts/mariadb-install-db" --no-defaults --srcdir="$BT" --datadir="$d" \
    --auth-root-authentication-method=normal >/dev/null 2>>"$WORK/install.log" || { echo install-db failed; exit 1; }
done
start master "$MDATA" "$MPROF" "$MSOCK" "$MP" 1 || { echo master start failed; exit 1; }
start slave  "$SDATA" "$SPROF" "$SSOCK" "$SP" 2 || { echo slave start failed; exit 1; }

# wire replication BEFORE seeding so the schema replicates
$CLIENT --socket="$SSOCK" -e "CHANGE MASTER TO MASTER_HOST='127.0.0.1', MASTER_PORT=$MP, MASTER_USER='root', MASTER_USE_GTID=slave_pos; START SLAVE;" 2>/dev/null
$CLIENT --socket="$MSOCK" --force < "$SEED" 2>"$WORK/seed_err.log"
bash "$HOME/mariadb-qa/generatorcpp/cov_qkiller.sh" "$MSOCK" & QK=$!

echo "[$(date +%T)] generate corpus ($NQ), fmt=$BINFMT"
( cd "$HOME/mariadb-qa/generatorcpp" && "$GEN" --threads "$GTHREADS" --output "$WORK/corpus.sql" "$NQ" ) >/dev/null 2>&1
grep -ivE "$FILTER" "$WORK/corpus.sql" | awk 'NR%15==0{print "UNLOCK TABLES;"} {print}' > "$WORK/corpus.f.sql"
split -l "$CHUNK" -d -a 4 "$WORK/corpus.f.sql" "$WORK/chunk_"
nch=$(ls "$WORK"/chunk_* 2>/dev/null | wc -l)

ci=0
for ch in "$WORK"/chunk_*; do
  ci=$((ci+1))
  timeout "$TMO" $CLIENT --socket="$MSOCK" --force test < "$ch" >/dev/null 2>>"$WORK/run_err.log"
  printf "\r    chunk %d/%d   " "$ci" "$nch"
done
echo
kill "$QK" 2>/dev/null
# let the replica drain, then flush both via clean shutdown
$CLIENT --socket="$MSOCK" -e "FLUSH LOGS" 2>/dev/null
for i in $(seq 1 120); do                                    # wait for the replica GTID to catch the primary
  gm=$($CLIENT --socket="$MSOCK" -Nse "SELECT @@gtid_binlog_pos" 2>/dev/null)
  gs=$($CLIENT --socket="$SSOCK" -Nse "SELECT @@gtid_slave_pos" 2>/dev/null)
  [ -n "$gm" ] && [ "$gm" = "$gs" ] && break; sleep 1
done
stop "$MSOCK"; stop "$SSOCK"                                 # profraw flushes only on clean exit - wait for it
for i in $(seq 1 90); do kill -0 "${PID_master:-0}" 2>/dev/null || kill -0 "${PID_slave:-0}" 2>/dev/null || break; sleep 1; done
for p in "${PID_master:-}" "${PID_slave:-}"; do [ -n "$p" ] && kill -0 "$p" 2>/dev/null && kill -9 "$p" 2>/dev/null; done

mkdir -p "$WORK/prof_all"; cp "$MPROF"/*.profraw "$SPROF"/*.profraw "$WORK/prof_all/" 2>/dev/null
BT="$BT" bash "$HOME/mariadb-qa/generatorcpp/cov_measure.sh" "$WORK/prof_all" "$WORK/cov" "$TAG"
