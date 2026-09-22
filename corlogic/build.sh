#!/bin/bash
# Created by Roel Van de Paar, MariaDB
# Build script for corlogic. Clang + libc++ is the canonical toolchain.
#
# Usage:  ./build.sh           # release build -> corlogic
#         ./build.sh debug     # -O0 -g3      -> corlogic_dbg
#         ./build.sh static    # fully static -> corlogic_static
#         ./build.sh ubasan    # UBSAN+ASAN   -> corlogic_ubasan
#         ./build.sh msan      # MSAN         -> corlogic_msan
#         ./build.sh tsan      # TSAN         -> corlogic_tsan
#         ./build.sh coverage  # instrumented -> corlogic_cov, then measure and report
#                              # COV_BUILD_ONLY=1 builds it and stops, for a run of your own
#         ./build.sh all       # release, debug, ubasan, msan, tsan, in order
#                              # coverage stays separate: it takes minutes and has a gate
#                              # static stays out: it needs libp11-kit.a, see that mode
#
# Every build runs --selftest before it is kept. SKIP_SELFTEST=1 keeps it anyway.
# MSAN needs an instrumented libc++ and an instrumented client library. Without the first it
# reports the standard library; without the second it reports the client library and a
# workload stops in pre-flight, so the mode then covers the selftest only.

set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-release}"
CXX="${CXX:-clang++}"

# MariaDB basedir whose libmariadbclient + headers we link against.
# Override with MARIADB_BASEDIR=/path. Default: the newest MariaDB -opt basedir in /test
# (via gendirs.sh where present, else a plain glob), so standalone boxes work too.
# MSAN wants an instrumented client library, so that mode takes an MSAN basedir where /test
# holds one. Every byte the client library hands over is otherwise uninstrumented, and the
# reports name that library rather than corlogic.
pick_mariadb_basedir() {
  if [ -n "${MARIADB_BASEDIR:-}" ]; then printf '%s\n' "${MARIADB_BASEDIR}"; return; fi
  local best=""
  if [ "$MODE" = msan ] && [ -x /test/gendirs.sh ]; then
    best=$( ( cd /test && ./gendirs.sh msan ) 2>/dev/null \
      | grep -E '^MSAN_MD.*-opt$' \
      | awk -F'-mariadb-' '{ print $2, $0 }' \
      | sort -V | tail -1 | awk '{print $2}')
    [ -n "$best" ] && best="/test/$best"
    if [ -n "$best" ] && [ ! -f "$best/lib/libmariadbclient.a" ]; then best=""; fi
  fi
  if [ -z "$best" ] && [ -x /test/gendirs.sh ]; then
    best=$( ( cd /test && ./gendirs.sh ) 2>/dev/null \
      | grep -E '^MD.*-opt$' \
      | awk -F'-mariadb-' '{ print $2, $0 }' \
      | sort -V | tail -1 | awk '{print $2}')
    [ -n "$best" ] && best="/test/$best"
  fi
  if [ -z "$best" ]; then
    best=$(ls -d /test/MD*-mariadb-*-opt 2>/dev/null \
      | awk -F'-mariadb-' '{ print $2, $0 }' | sort -V | tail -1 | awk '{print $2}')
  fi
  [ -n "$best" ] || { echo "[build.sh] no MariaDB -opt basedir found; set MARIADB_BASEDIR=" >&2; exit 2; }
  printf '%s\n' "$best"
}
MARIADB_BASEDIR="$(pick_mariadb_basedir)"
[ -f "$MARIADB_BASEDIR/lib/libmariadbclient.a" ] || { echo "[build.sh] $MARIADB_BASEDIR: libmariadbclient.a missing" >&2; exit 2; }
[ -f "$MARIADB_BASEDIR/include/mysql/mysql.h" ] || { echo "[build.sh] $MARIADB_BASEDIR: include/mysql/mysql.h missing" >&2; exit 2; }

COMMON_FLAGS=(
  -std=c++20
  -stdlib=libc++
  -pthread
  -Wall -Wno-unused-function
  -Wl,--build-id=sha1
)
REL_FLAGS=(-O3 -march=native -mtune=native -DNDEBUG -pipe)
DBG_FLAGS=(-O0 -g3 -fno-omit-frame-pointer)

# Client auth plugin dir baked in as the default (caching_sha2_password.so for MySQL 8+ sides)
MYSQL_FLAGS=(-I"$MARIADB_BASEDIR/include" -DCORLOGIC_PLUGIN_DIR="\"$MARIADB_BASEDIR/lib/plugin\"")
MYSQL_LIBS=(-L"$MARIADB_BASEDIR/lib" -lmariadbclient -lgnutls -lssl -lcrypto -lz -lzstd -lresolv -lm -ldl)
MYSQL_RPATH=(-Wl,-rpath,"$MARIADB_BASEDIR/lib")

echo "[build.sh] mode=$MODE cxx=$CXX"
echo "[build.sh] mariadb basedir: $MARIADB_BASEDIR"

case "$MODE" in
  release|rel|"")
    OUT="corlogic"
    FLAGS=("${COMMON_FLAGS[@]}" "${REL_FLAGS[@]}")
    LINK_FLAGS=(-stdlib=libc++ -lc++abi -Wl,--as-needed "${MYSQL_RPATH[@]}")
    ;;
  debug|dbg)
    OUT="corlogic_dbg"
    FLAGS=("${COMMON_FLAGS[@]}" "${DBG_FLAGS[@]}")
    LINK_FLAGS=(-stdlib=libc++ -lc++abi "${MYSQL_RPATH[@]}")
    ;;
  static|stat)
    OUT="corlogic_static"
    FLAGS=("${COMMON_FLAGS[@]}" "${REL_FLAGS[@]}")
    # a static link resolves left to right, and the driver puts libc++ last, so the two
    # archives go in a group: libc++ needs the guard symbols out of libc++abi
    LINK_FLAGS=(-static -stdlib=libc++ -Wl,--start-group -lc++ -lc++abi -Wl,--end-group)
    # gnutls pulls its own chain in a static link, and each archive has to come after
    # the one that needs it. The chain ends at p11-kit, and Ubuntu ships no libp11-kit.a,
    # libp11-kit-dev included, so the link stops on p11_kit_* symbols
    [ -f /usr/lib/x86_64-linux-gnu/libp11-kit.a ] || [ -f /lib/x86_64-linux-gnu/libp11-kit.a ] ||
      echo "[build.sh] libp11-kit.a is not on this box: the static link will not finish" >&2
    MYSQL_LIBS+=(-Wl,--start-group -lnettle -lhogweed -Wl,--end-group
                 -lgmp -ltasn1 -lidn2 -lunistring -lffi
                 -lssl -lcrypto -lz -lzstd -lresolv -lm -ldl -lpthread)
    ;;
  ubasan|ubsan|asan)
    OUT="corlogic_ubasan"
    FLAGS=("${COMMON_FLAGS[@]}" -O1 -g -fno-omit-frame-pointer
           -fsanitize=undefined,address -fno-sanitize-recover=undefined)
    LINK_FLAGS=(-stdlib=libc++ -lc++abi -fsanitize=undefined,address "${MYSQL_RPATH[@]}")
    ;;
  msan)
    OUT="corlogic_msan"
    FLAGS=("${COMMON_FLAGS[@]}" -O1 -g -fno-omit-frame-pointer
           -fsanitize=memory -fsanitize-memory-track-origins=2)
    LINK_FLAGS=(-stdlib=libc++ -lc++abi -fsanitize=memory "${MYSQL_RPATH[@]}")
    # MSAN needs every byte it sees to come from instrumented code, the standard library
    # included, or it reports the library. /MSAN_libs holds an instrumented libc++.
    MSAN_LIBS="${MSAN_LIBS:-/MSAN_libs}"
    if [ -f "$MSAN_LIBS/libc++.a" ] && [ -d "$MSAN_LIBS/include/c++/v1" ]; then
      FLAGS+=(-nostdinc++ -isystem "$MSAN_LIBS/include/c++/v1")
      # the static archives, named by full path: -L or an rpath into that directory would
      # also be searched for gnutls and nettle, whose copies there carry other symbol
      # versions than the client library was built against
      LINK_FLAGS=(-nostdlib++ -fsanitize=memory "$MSAN_LIBS/libc++.a" "$MSAN_LIBS/libc++abi.a"
                  "${MYSQL_RPATH[@]}")
      echo "[build.sh] msan: instrumented libc++ from $MSAN_LIBS"
    else
      echo "[build.sh] msan: no instrumented libc++ in $MSAN_LIBS; expect reports in the library" >&2
    fi
    case "$MARIADB_BASEDIR" in
      */MSAN_*) echo "[build.sh] msan: instrumented client library from $MARIADB_BASEDIR" ;;
      *) echo "[build.sh] msan: $MARIADB_BASEDIR is not an MSAN build, so the client library" \
              "is uninstrumented. The selftest is clean; a workload stops in pre-flight on" \
              "reports from inside that library. Build an MSAN basedir (gendirs.sh msan) or" \
              "set MARIADB_BASEDIR to one." >&2 ;;
    esac
    ;;
  tsan)
    OUT="corlogic_tsan"
    FLAGS=("${COMMON_FLAGS[@]}" -O1 -g -fno-omit-frame-pointer -fsanitize=thread)
    LINK_FLAGS=(-stdlib=libc++ -lc++abi -fsanitize=thread "${MYSQL_RPATH[@]}")
    ;;
  coverage|cov)
    OUT="corlogic_cov"
    FLAGS=("${COMMON_FLAGS[@]}" -O1 -g -fprofile-instr-generate -fcoverage-mapping)
    LINK_FLAGS=(-stdlib=libc++ -lc++abi -fprofile-instr-generate "${MYSQL_RPATH[@]}")
    ;;
  all)
    for m in release debug ubasan msan tsan; do "$0" "$m" || exit $?; done
    exit 0
    ;;
  *)
    echo "usage: $0 [release|debug|static|ubasan|msan|tsan|coverage|all]"; exit 2
    ;;
esac

TMP="${OUT}.tmp"
rm -f "$TMP"
"$CXX" "${FLAGS[@]}" "${MYSQL_FLAGS[@]}" corlogic.cpp -o "$TMP" "${LINK_FLAGS[@]}" "${MYSQL_LIBS[@]}"
mv -f "$TMP" "$OUT"

echo "[build.sh] built: $OUT ($(stat -c %s "$OUT") bytes)"
echo "[build.sh] sanity: $(LLVM_PROFILE_FILE=/dev/null ./$OUT --version 2>&1 | head -1)"

# The unit tests gate the build: a binary that fails them is kept as .failed and the
# script exits non-zero, so a broken build is never the one a run picks up.
if [ "${SKIP_SELFTEST:-0}" != "1" ] && [ "$OUT" != "corlogic_cov" ]; then
  if ! ./"$OUT" --selftest; then
    mv -f "$OUT" "$OUT.failed"
    echo "[build.sh] selftest FAILED: kept as $OUT.failed" >&2
    exit 1
  fi
fi

# The coverage mode measures what the tests reach: the unit tests, then the run shapes
# that need a live server. What is left uncovered needs a server that dies, a query that
# ignores KILL, a real timing finding and a 30-build sweep, so the gate sits below 100.
if [ "$OUT" = "corlogic_cov" ] && [ -n "${COV_BUILD_ONLY:-}" ]; then
  echo "[build.sh] coverage: built $OUT, shapes skipped (COV_BUILD_ONLY)"
  exit 0
fi
if [ "$OUT" = "corlogic_cov" ]; then
  TARGET="${COVERAGE_TARGET:-75}"
  COVDIR="${COVDIR:-/dev/shm/corlogic_cov}"
  BD="$MARIADB_BASEDIR"
  rm -rf "$COVDIR"; mkdir -p "$COVDIR"
  cov() {                                  # cov <name> <args...>
    local name="$1"; shift
    echo "[build.sh] coverage: $name"
    LLVM_PROFILE_FILE="$COVDIR/$name.profraw" ./"$OUT" "$@" >"$COVDIR/$name.log" 2>&1 \
      || echo "[build.sh] coverage: $name ended non-zero, see $COVDIR/$name.log" >&2
  }
  COMMON=(TUI=0 VERSION_SWEEP=0 WORKERS=4 WORKDIR_BASE="$COVDIR")
  cov selftest --selftest
  cov help --help
  cov check --check "${COMMON[@]}" "$BD" "$BD"
  cov aa "${COMMON[@]}" TRIALS=4 QUERIES_PER_TRIAL=200 "$BD" "$BD"
  # a difference on purpose, so the candidate, every reduction pass, the final replay and
  # the report all run
  cov diff "${COMMON[@]}" TRIALS=1 QUERIES_PER_TRIAL=10 MYEXTRA_SIDE2=--max_join_size=500 "$BD" "$BD"
  RID=$(sed -n 's|.*results: .*/\([0-9]\{1,\}\)$|\1|p' "$COVDIR/diff.log" | tail -1)
  [ -n "$RID" ] && cov resume "${COMMON[@]}" TRIALS=1 --resume "$RID"
  cov options "${COMMON[@]}" TRIALS=1 QUERIES_PER_TRIAL=50 \
    "OPTIONS_SETS=--optimizer_switch=derived_merge=on;--optimizer_switch=derived_merge=off" "$BD"
  cov engines "${COMMON[@]}" TRIALS=1 QUERIES_PER_TRIAL=50 ENGINES=innodb,myisam "$BD"
  # no WORKERS, so the pool is measured off the pre-flight the way a plain run does it
  cov autopool TUI=0 VERSION_SWEEP=0 WORKDIR_BASE="$COVDIR" TRIALS=1 QUERIES_PER_TRIAL=20 \
    "$BD" "$BD"
  cov mix "${COMMON[@]}" TRIALS=1 QUERIES_PER_TRIAL=50 ENGINE_MIX=1 ENGINES=innodb,myisam \
    VIEWS=1 SEQUENCES=1 PARTITIONING=2 GENERATED_COLUMNS=1 "$BD" "$BD"
  # plans compared on purpose, so the plan read, the two-read guard and the shape gate run
  cov plan "${COMMON[@]}" TRIALS=2 QUERIES_PER_TRIAL=100 PLAN_COMPARE=1 PLAN_PERF_REPORT=1 \
    PLAN_FACTOR=2 MYEXTRA_SIDE2=--optimizer_switch=derived_merge=off "$BD" "$BD"
  # one combination per trial, and the cursor picked up by a second run of the same workdir
  cov combo "${COMMON[@]}" TRIALS=2 QUERIES_PER_TRIAL=50 OPTIMIZER_SWITCH_COMBINATORICS=1 "$BD"
  RID=$(sed -n 's|.*results: .*/\([0-9]\{1,\}\)$|\1|p' "$COVDIR/combo.log" | tail -1)
  [ -n "$RID" ] && cov combo_resume "${COMMON[@]}" TRIALS=1 --resume "$RID"
  # the user SQL filter, a seed file instead of the built-in schema, and the SQL_MODE knobs
  printf 'select.*information_schema\ncreate +view\n' > "$COVDIR/filter.txt"
  printf 'CREATE TABLE s1 (c1 INT PRIMARY KEY, c2 VARCHAR(20));\nINSERT INTO s1 VALUES (1,%s),(2,%s);\n' \
    "'a'" "'b'" > "$COVDIR/seed.sql"
  cov filters "${COMMON[@]}" TRIALS=1 QUERIES_PER_TRIAL=50 \
    SEED_SQL="$COVDIR/seed.sql" SQL_FILTER_FILE="$COVDIR/filter.txt" \
    SQL_MODE_ADD=ANSI_QUOTES SQL_MODE_REMOVE=ONLY_FULL_GROUP_BY "$BD" "$BD"
  # a warning-only difference, so the warning compare and its report line run
  printf 'CREATE TABLE w1 (c1 INT);\nSELECT CAST(%s AS SIGNED) AS c;\n' "'abc'" > "$COVDIR/warn.sql"
  cov warnings "${COMMON[@]}" TRIALS=1 QUERIES_PER_TRIAL=1 SEED_SQL="$COVDIR/warn.sql" \
    WARNINGS_AS_BUG=1 MYEXTRA_SIDE2=--max-error-count=0 "$BD" "$BD"
  # a table-content compare at every checkpoint, not only at the end of the stream
  cov checkpoint "${COMMON[@]}" TRIALS=1 QUERIES_PER_TRIAL=120 CHECKPOINT_EVERY=20 "$BD" "$BD"
  # a time limit on one side, so the timing notes, the trial stop and the guarded table
  # scans all run
  cov timing "${COMMON[@]}" TRIALS=3 QUERIES_PER_TRIAL=200 \
    MYEXTRA_SIDE2=--max_statement_time=0.001 "$BD" "$BD"
  # a difference that depends on how many rows are there: one side refuses the join once
  # the estimate passes max_join_size. The rows cannot all be reduced away, so the row,
  # table-list and literal passes each have real work to do
  {
    R=; for i in $(seq 1 40); do R="$R${R:+,}($i,$i)"; done
    echo "CREATE TABLE r1 (c1 INT PRIMARY KEY, c2 INT);"
    echo "CREATE TABLE r2 (c1 INT PRIMARY KEY, c2 INT);"
    echo "INSERT INTO r1 VALUES $R;"
    echo "INSERT INTO r2 VALUES $R;"
    echo "SELECT r1.c1, r2.c2 FROM r1, r2 WHERE r1.c2 > 0 AND r2.c2 > 0 ORDER BY r1.c1, r2.c1;"
  } > "$COVDIR/rich.sql"
  cov rich "${COMMON[@]}" TRIALS=1 QUERIES_PER_TRIAL=5 SEED_SQL="$COVDIR/rich.sql" \
    MYEXTRA_SIDE2=--max_join_size=500 "$BD" "$BD"
  # a long stream with table-content compares along it, so a checkpoint difference carries
  # every statement before it
  cov longstream "${COMMON[@]}" TRIALS=2 QUERIES_PER_TRIAL=250 CHECKPOINT_EVERY=25 \
    MYEXTRA_SIDE2=--div_precision_increment=10 "$BD" "$BD"
  # one side materialises both derived tables and the other merges them, so the gap is wide
  # enough to be a PERF difference and the amplify pass runs on it
  {
    echo "CREATE TABLE p1 (c1 INT PRIMARY KEY, c2 INT, c3 VARCHAR(50));"
    echo "INSERT INTO p1 SELECT seq, seq MOD 997, CONCAT('x', seq) FROM seq_1_to_50000;"
    echo "SELECT COUNT(*) FROM (SELECT c1, c2 FROM p1) a JOIN (SELECT c1, c2 FROM p1) b ON a.c2 = b.c2 WHERE a.c1 < 200;"
  } > "$COVDIR/perf.sql"
  cov perf "${COMMON[@]}" TRIALS=2 QUERIES_PER_TRIAL=5 SEED_SQL="$COVDIR/perf.sql" \
    PLAN_COMPARE=1 PLAN_PERF_REPORT=1 PLAN_FACTOR=2 \
    MYEXTRA_SIDE2=--optimizer_switch=derived_merge=off "$BD" "$BD"
  # a side that dies under the run, so the crash grade, the core capture and the revive all
  # run. Its run dir is its own, and the kill matches that path alone, so it can reach no
  # server but this shape's
  mkdir -p "$COVDIR/run"
  (
    for _ in $(seq 1 180); do
      CP=$(ps -eo pid,args -ww --no-headers | grep -F -- "--datadir=$COVDIR/run/" \
           | grep -F "/side2" | grep mariadbd | awk '{print $1}' | head -1)
      if [ -n "$CP" ]; then sleep 4; kill -9 "$CP" 2>/dev/null; break; fi
      sleep 1
    done
  ) &
  COV_KILLER=$!
  cov crash TUI=0 VERSION_SWEEP=0 WORKERS=4 WORKDIR_BASE="$COVDIR" RUNDIR_BASE="$COVDIR/run" \
    TRIALS=3 QUERIES_PER_TRIAL=200 "$BD" "$BD"
  wait "$COV_KILLER" 2>/dev/null || true
  # three sides, so every per-side loop runs with a side that is neither first nor last
  cov threesides "${COMMON[@]}" TRIALS=1 QUERIES_PER_TRIAL=40 "$BD" "$BD" "$BD"
  # a known-difference filter that matches, so the load, the match and the mute all run
  printf '# a UID that the run will meet\nRESULT|\n' > "$COVDIR/known.txt"
  cov known "${COMMON[@]}" TRIALS=1 QUERIES_PER_TRIAL=10 KNOWN_FILE="$COVDIR/known.txt" \
    MYEXTRA_SIDE2=--max_join_size=500 "$BD" "$BD"
  # a MySQL side, so the cross-vendor error compare and the parse-skip path run
  MSBD=$(ls -d /test/MS*-mysql-8.0*-opt 2>/dev/null | tail -1)
  if [ -n "$MSBD" ]; then
    cov vendor "${COMMON[@]}" TRIALS=1 QUERIES_PER_TRIAL=50 "$BD" "$MSBD"
  fi
  # the version sweep, its build matrix and the Jira version split, on a difference that
  # always reproduces
  cov sweep TUI=0 WORKERS=4 WORKDIR_BASE="$COVDIR" VERSION_SWEEP=1 TRIALS=1 \
    QUERIES_PER_TRIAL=10 MYEXTRA_SIDE2=--max_join_size=500 "$BD" "$BD"
  # the panel, which needs a terminal to draw on
  if command -v script >/dev/null; then
    echo "[build.sh] coverage: tui"
    # the keys go in on a pipe: pause on and off, then reduce-now on and off
    { sleep 6; printf 'pp'; sleep 1; printf 'rr'; } |
      LLVM_PROFILE_FILE="$COVDIR/tui.profraw" script -qec "./$OUT TUI=1 \
      VERSION_SWEEP=0 WORKERS=4 WORKDIR_BASE=$COVDIR TRIALS=3 QUERIES_PER_TRIAL=300 $BD $BD" \
      /dev/null >"$COVDIR/tui.log" 2>&1 || true
  fi
  llvm-profdata merge -sparse "$COVDIR"/*.profraw -o "$COVDIR/all.profdata"
  llvm-cov report ./"$OUT" -instr-profile="$COVDIR/all.profdata" corlogic.cpp \
    | tee "$COVDIR/report.txt"
  llvm-cov show ./"$OUT" -instr-profile="$COVDIR/all.profdata" corlogic.cpp \
    -show-line-counts-or-regions > "$COVDIR/lines.txt"
  # the TOTAL row carries four percentages: regions, functions, lines, branches
  PCT=$(awk '/^TOTAL/ { n = 0; for (i = 1; i <= NF; i++) if ($i ~ /%$/ && ++n == 3) { gsub("%", "", $i); print $i } }' \
    "$COVDIR/report.txt")
  echo "[build.sh] coverage: ${PCT}% of lines, target ${TARGET}% (detail in $COVDIR)"
  awk -v p="$PCT" -v t="$TARGET" 'BEGIN { exit (p + 0 >= t + 0) ? 0 : 1 }' \
    || { echo "[build.sh] coverage below target" >&2; exit 1; }
fi

