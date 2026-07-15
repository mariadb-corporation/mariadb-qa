#!/bin/bash
# Sequential coverage driver: run each scenario one at a time (parallel runs wedge on disk
# I/O), then grand-union every scenario's profraw and report the merged coverage. Levers are
# run one per phase so each contribution is visible. Requires the instrumented build at $BT.
set -u
BT="${BT:-/tmp/13.0_cov_opt}"
G="$HOME/mariadb-qa/generatorcpp"
ROOT="${ROOT:-/data/cov}"
PHASE_TMO="${PHASE_TMO:-1500}"
mkdir -p "$ROOT"
[ -x "$BT/sql/mariadbd" ] || { echo "instrumented build missing at $BT (rebuild first)"; exit 1; }

run(){ local name="$1"; shift; echo "=== [$(date +%T)] phase: $name ==="; BT="$BT" timeout "$PHASE_TMO" "$@"; }

run base        bash "$G/coverage_run.sh"
run repl_row    env BINFMT=ROW       bash "$G/cov_replication.sh"
run repl_stmt   env BINFMT=STATEMENT bash "$G/cov_replication.sh"
run repl_mixed  env BINFMT=MIXED     bash "$G/cov_replication.sh"
run galera      bash "$G/cov_galera.sh"
run oracle      bash "$G/cov_oracle.sh"
run recovery    bash "$G/cov_recovery.sh"

echo "=== [$(date +%T)] grand union ==="
GU="$ROOT/grand"; rm -rf "$GU"; mkdir -p "$GU"
n=0
for p in /tmp/covrun_*/prof "$ROOT"/covrun_*/prof "$ROOT"/covrun_*/prof_all; do
  for f in "$p"/*.profraw; do [ -e "$f" ] || continue; cp "$f" "$GU/gu_$((n++)).profraw"; done
done
echo "collected $n profraw files"
BT="$BT" bash "$G/cov_measure.sh" "$GU" "$ROOT/grand_report" "grand-union" | tee "$ROOT/grand_report.txt"
