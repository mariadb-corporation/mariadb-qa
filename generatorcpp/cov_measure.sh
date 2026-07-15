#!/bin/bash
# Merge a scenario's profraw set and report line coverage overall + for sql/, InnoDB, strings.
# Usage: cov_measure.sh <profraw_dir> <out_prefix> [label]
set -u
PROFDIR="${1:?usage: cov_measure.sh <profraw_dir> <out_prefix> [label]}"
OUT="${2:?out_prefix}"
LABEL="${3:-cov}"
BT="${BT:-/tmp/13.0_cov_opt}"
BIN="$BT/sql/mariadbd"
ls "$PROFDIR"/*.profraw >/dev/null 2>&1 || { echo "NO PROFRAW in $PROFDIR"; exit 2; }
llvm-profdata merge -sparse "$PROFDIR"/*.profraw -o "$OUT.profdata" 2>"$OUT.merge.log" \
  || { echo "merge failed"; cat "$OUT.merge.log"; exit 2; }
report_line(){ llvm-cov report "$BIN" -instr-profile="$OUT.profdata" "$@" 2>/dev/null | tail -1 \
  | awk '{printf "lines %s/%s = %s\n", $(NF-2)-$(NF-1), $(NF-2), $NF}'; }
echo "==================== COVERAGE ($LABEL) ===================="
printf "OVERALL  "; report_line
for d in sql storage/innobase strings; do printf "%-18s " "$d"; report_line "$BT/$d/"; done
echo "profdata: $OUT.profdata"
