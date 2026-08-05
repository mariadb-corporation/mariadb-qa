#!/bin/bash
# revgen test suite. Run by build.sh after every build.
#
#   ./test.sh [binary]        default ./revgen
#
# Server-backed tests (--validate-sql) run when a MariaDB socket is reachable,
# and are skipped otherwise; REVGEN_TEST_SOCKET overrides the socket path.
# Set REVGEN_TEST_KEEP=1 to keep the scratch directory for inspection.
cd "$(dirname "$0")"
BIN=${1:-./revgen}
SOCKET=${REVGEN_TEST_SOCKET:-/test/CLAUDE1/socket.sock}
W=$(mktemp -d /tmp/revgen-test.XXXXXX)
[ -n "${REVGEN_TEST_KEEP}" ] || trap 'rm -rf "$W"' EXIT
PASS=0; FAIL=0; SKIP=0

ok()   { PASS=$((PASS+1)); }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }
skip() { SKIP=$((SKIP+1)); echo "  skip: $1"; }

# check <name> <expected-rc> <args...>   - run and compare the exit status
check() {
  local name=$1 want=$2; shift 2
  "$BIN" "$@" >"$W/out" 2>"$W/err"; local got=$?
  [ "$got" = "$want" ] && ok || bad "$name: rc=$got want=$want"
}
# has <name> <file> <pattern>
has() { grep -qE -- "$3" "$2" && ok || bad "$1: no match for '$3'"; }
# hasnt <name> <file> <pattern>
hasnt() {
  local n; n=$(grep -cE -- "$3" "$2")
  [ "$n" = 0 ] && ok || bad "$1: $n unexpected matches for '$3'"
}
# gen <outfile> <args...>  - generate without contacting a server
gen() { local o=$1; shift; "$BIN" --output "$o" "$@" >/dev/null 2>"$W/gerr"; }

echo "revgen test suite: $BIN"

# ---- argument handling ---------------------------------------------------
check "help long"        0 --help
check "help short"       0 -h
check "unknown arg"      2 --no-such-flag
check "missing value"    2 --queries
# Every numeric option has to report which option was wrong. std::stol throws on
# a value that is not a number or does not fit, and an uncaught throw ends the run
# with a libc++abi message that names nothing - a typo in REVGEN_OPTIONS would
# look like a crash.
for f in --queries --depth --depth-max --max-chain --schema-every --seed \
        --grants --chain-share \
         --threads --coverage; do
  for v in 99999999999999999999 abc 1.5 "12x"; do
    "$BIN" $f "$v" --output /dev/null >"$W/n.out" 2>"$W/n.err"
    rc=$?
    if [ $rc = 2 ] && grep -q "needs a whole number" "$W/n.err"; then ok; else
      bad "$f $v: rc=$rc, no clean message"; fi
  done
done
# Out-of-range but parseable values clamp rather than being rejected.
gen "$W/clamp.sql" --queries 20 --depth 99999 --depth-max 99999 --max-chain 99999 --seed 1
[ -f "$W/clamp.sql" ] && ok || bad "large numeric values must clamp"
gen "$W/neg.sql" --queries 20 --depth -5 --schema-every -5 --max-chain -5 --seed 1
[ -f "$W/neg.sql" ] && ok || bad "negative numeric values must clamp"
check "queries zero"     2 --queries 0 --output -
check "queries negative" 2 --queries -5 --output -
check "yacc missing"     2 --yacc /nonexistent/sql_yacc.yy --output -
check "lex missing"      2 --lex /nonexistent/lex.h --queries 1 --output -
check "bad start symbol" 2 --start no_such_rule --queries 1 --output -
"$BIN" --help >"$W/usage" 2>&1
has "usage lists coverage" "$W/usage" "--coverage"
has "usage lists depth-max" "$W/usage" "--depth-max"

# ---- diagnostics --------------------------------------------------------
"$BIN" --info >/dev/null 2>"$W/info"
has "info rules"     "$W/info" "rules: +[0-9]+ nonterminals"
has "info terminals" "$W/info" "terminals: +[0-9]+ referenced"
has "info keywords"  "$W/info" "keywords: +[0-9]+ from lex.h"
has "info dropped"   "$W/info" "dropped: +[0-9]+ productions"
has "info start height" "$W/info" "start: +verb_clause \(min height [0-9]+\)"
# Pruning the last production of a rule silently removes whatever only reaches
# through it, so --info names those rules. The qualified-name rules must not be
# among them: SELECT t1.* has to stay reachable.
has   "info unreachable count" "$W/info" "unreachable: +[0-9]+ rules"
hasnt "qualified asterisk reachable" "$W/info" "^  (table_wild|select_sublist_qualified_asterisk)$"

"$BIN" --trace --start expr >/dev/null 2>"$W/trace"
has "trace min height" "$W/trace" "minH="
# A rule whose alternatives are bare terminals, so the trace renders the text a
# terminal emits and flags a silent one.
"$BIN" --trace --start describe_command >/dev/null 2>"$W/trace2"
has "trace terminal text" "$W/trace2" '\-> "DESC'

"$BIN" --dump --start bit_expr >/dev/null 2>"$W/dump"
has "dump productions" "$W/dump" "bit_expr: \([0-9]+ productions\)"
# The interval-first forms are pruned; the bit_expr-led ones are kept.
hasnt "dump interval-first pruned" "$W/dump" "^  \| ('[+-]' )?INTERVAL_SYM"
has   "dump interval kept"         "$W/dump" "bit_expr '[+-]' INTERVAL_SYM"

"$BIN" --audit >/dev/null 2>"$W/audit"
has "audit silent terminals" "$W/audit" "silent terminals"

"$BIN" --names >"$W/names" 2>/dev/null
has "names shows id leaf" "$W/names" "<ID>"
# No rule may still offer a '.'-qualified identifier: the name pools are flat,
# so a qualified name puts a table in the database slot.
hasnt "names no qualified ids" "$W/names" "<ID> '\.' <ID>"

"$BIN" --parens >"$W/parens" 2>/dev/null
has "parens reports family" "$W/parens" "'\(' [a-z_]+ '\)'"
hasnt "parens: empty-arg natives pruned" "$W/parens" "CONTAINS_SYM|OVERLAPS_SYM|WITHIN"
# The audit has to scan every position in a production, not only a production that
# is exactly '(' X ')'. The cases that matter sit behind a keyword, and a
# whole-production match misses all of them. --allow-unsafe keeps the natives in
# so there is something keyword-prefixed to find.
"$BIN" --parens --allow-unsafe >"$W/parens2" 2>/dev/null
has "parens finds keyword-prefixed" "$W/parens2" "CONTAINS_SYM '\(' opt_expr_list '\)'"
has "parens finds mid-production"   "$W/parens2" "'\(' [a-z_]+ '\)'  in  [A-Za-z_]+ "

"$BIN" --queries 500 --depth 6 --seed 1 --output /dev/null \
  --coverage 3 >/dev/null 2>"$W/cov"
has "coverage total"      "$W/cov" "coverage from verb_clause: [0-9]+/[0-9]+ productions"
has "coverage structural" "$W/cov" "structural [0-9]+/[0-9]+"
has "coverage untouched"  "$W/cov" "rules never entered"
has "coverage untried"    "$W/cov" "untried alternatives"
has "coverage limit honoured" "$W/cov" "\.\.\. [0-9]+ more"
"$BIN" --queries 500 --depth 6 --seed 1 --output /dev/null \
  --coverage 0 >/dev/null 2>"$W/cov0"
hasnt "coverage 0 = no cap" "$W/cov0" "\.\.\. [0-9]+ more"
# The denominator is what the start symbol can reach, not the whole grammar.
# Against a narrow --start the whole-grammar count reports a fraction of a
# percent for a run that covered everything available to it.
"$BIN" --start not --queries 50 --depth 3 --seed 1 \
  --output /dev/null --coverage 0 >/dev/null 2>"$W/covn"
has "coverage denominator is reachable set" "$W/covn" "coverage from not: 1/1 productions \(100%\)"

# ---- generation ---------------------------------------------------------
gen "$W/g.sql" --queries 2000 --depth 8 --seed 42
N=$(grep -c . "$W/g.sql")
[ "$N" -ge 2000 ] && ok || bad "count: emitted $N, wanted >= 2000"
hasnt "no blank lines"        "$W/g.sql" "^$"
hasnt "every line ends in ;"  "$W/g.sql" "[^;]$"
hasnt "no unresolved symbols" "$W/g.sql" "_SYM|IDENT_sys|TEXT_STRING_sys"
hasnt "no NOT2 as bang-EXISTS" "$W/g.sql" "IF ! (NOT )?EXISTS"
hasnt "no empty arg natives"  "$W/g.sql" "(CONTAINS|OVERLAPS|WITHIN) *\(\)"
# '||' is legitimate as the OR2_SYM spelling of OR. What must not survive is the
# concat production, which needs PIPES_AS_CONCAT to lex.
"$BIN" --dump --start mysql_concatenation_expr >/dev/null 2>"$W/cc"
hasnt "concat production pruned" "$W/cc" "MYSQL_CONCAT_SYM"
hasnt "no database DDL"       "$W/g.sql" "^(CREATE|DROP|ALTER) (DATABASE|SCHEMA)"
hasnt "no USE statement"      "$W/g.sql" "^USE "
hasnt "no XA"                 "$W/g.sql" "^XA "
hasnt "no admin statements"   "$W/g.sql" "^(SHUTDOWN|KILL|INSTALL|UNINSTALL|RESET|PURGE|CHANGE MASTER)"
# Balanced parentheses on every line: an unbalanced one cannot parse. String
# literals are stripped first, since random text legitimately holds stray parens.
UNBAL=$(sed "s/'\([^']\|''\)*'//g; s/\"\([^\"]\|\"\"\)*\"//g" "$W/g.sql" |
  awk '{o=gsub(/\(/,""); c=gsub(/\)/,""); if (o!=c) u++} END{print u+0}')
[ "$UNBAL" = 0 ] && ok || bad "unbalanced parens on $UNBAL lines"

# The qualifier in "t1.*" names a table, so a column name there cannot resolve.
# join() spaces the '.', which parses.
has "qualified asterisk uses a table" "$W/g.sql" "\bt[0-9] \. \*"
# The setup block must supply everything the identifier pools name.
for obj in "CREATE TABLE IF NOT EXISTS t1" "CREATE TABLE IF NOT EXISTS t4" \
           "CREATE OR REPLACE PROCEDURE sp1" "CREATE OR REPLACE FUNCTION f1" \
           "CREATE OR REPLACE VIEW cv1" "CREATE SEQUENCE IF NOT EXISTS cs1" \
           "UNLOCK TABLES" "BACKUP UNLOCK"; do
  has "setup has '$obj'" "$W/g.sql" "^$obj"
done
# Two of the four tables carry partitions and two do not.
P=$(grep -cE "^CREATE TABLE IF NOT EXISTS t[0-9] .*PARTITION BY" "$W/g.sql")
U=$(grep -cE "^CREATE TABLE IF NOT EXISTS t[0-9] " "$W/g.sql")
[ "$P" -gt 0 ] && [ "$U" -gt "$P" ] && ok || bad "partitioned setup tables: $P of $U"

gen "$W/nos.sql" --queries 300 --depth 6 --seed 42 --schema-every 0
hasnt "schema-every 0 = no setup" "$W/nos.sql" "^CREATE TABLE IF NOT EXISTS t1"

# Each object class draws from its own name pool, and the names match
# generatorcpp's so a mixed run resolves against one set of objects. A role that
# covers too much of the tree shows up here first: typing the whole right-hand
# side of a SET after its target named windows and tables c1-c4, and typing off
# the PARTITION keyword caught "PARTITION BY", where no partition is named.
gen "$W/id.sql" --queries 40000 --depth 10 --seed 5 --threads 4
for slot in "WINDOW:w" "OVER:w" "PREPARE:s" "SAVEPOINT:sp" "CONSTRAINT:chk"; do
  kw=${slot%%:*}; want=${slot##*:}
  T=$(grep -oE "\b$kw [a-z]+[0-9]" "$W/id.sql" | wc -l)
  R=$(grep -oE "\b$kw ${want}[0-9]" "$W/id.sql" | wc -l)
  [ "$T" -gt 0 ] && [ "$R" -ge $((T * 99 / 100)) ] && ok \
    || bad "$kw names: $R of $T use '$want', wanted 99%+"
done
# A partition is still named where one is really declared or referenced.
has "partition list names p" "$W/id.sql" "PARTITION\(p[0-9]"
# The assignment target keeps its own sequential column role.
has "SET target is a column" "$W/id.sql" "SET c[0-9] :?="

# ---- determinism and threading -----------------------------------------
gen "$W/a.sql" --queries 800 --depth 8 --seed 7 --threads 4
gen "$W/b.sql" --queries 800 --depth 8 --seed 7 --threads 4
cmp -s "$W/a.sql" "$W/b.sql" && ok || bad "same seed and threads must repeat exactly"
gen "$W/c.sql" --queries 800 --depth 8 --seed 8 --threads 4
cmp -s "$W/a.sql" "$W/c.sql" && bad "different seed produced identical output" || ok
# No --seed is the default: every engine seeds its own 256 bits from independent entropy, so
# two runs must differ. This is also the only path that reaches Xoshiro256pp::seed_full().
gen "$W/e1.sql" --queries 800 --depth 8 --threads 4
gen "$W/e2.sql" --queries 800 --depth 8 --threads 4
[ -s "$W/e1.sql" ] && [ -s "$W/e2.sql" ] && ok || bad "default seeding produced no output"
cmp -s "$W/e1.sql" "$W/e2.sql" && bad "default seeding repeated itself across runs" || ok
# --seed has to reach the generator itself, not only the interjection RNG.
# --schema-every 0 removes the interjections, so if the statements still differ the
# seed is genuinely feeding the derivation. Comparing whole files would pass on
# interjection placement alone.
gen "$W/s1.sql" --queries 600 --depth 8 --seed 21 --threads 1 --schema-every 0
gen "$W/s2.sql" --queries 600 --depth 8 --seed 22 --threads 1 --schema-every 0
D=$(diff -y --suppress-common-lines "$W/s1.sql" "$W/s2.sql" 2>/dev/null | wc -l)
[ "$D" -ge 500 ] && ok || bad "seed barely changes the derivation: only $D of 600 lines differ"
# And the per-thread seed derivation has to spread threads apart: without it every
# thread walks the same sequence and the parts are identical.
gen "$W/mt.sql" --queries 800 --depth 8 --seed 21 --threads 4 --schema-every 0
U=$(sort -u "$W/mt.sql" | wc -l); T=$(grep -c . "$W/mt.sql")
[ "$U" -ge $((T * 7 / 10)) ] && ok || bad "threads repeat each other: $U unique of $T"
for t in 1 2 16; do
  gen "$W/t$t.sql" --queries 600 --depth 7 --seed 3 --threads $t
  n=$(grep -c . "$W/t$t.sql")
  [ "$n" -ge 600 ] && ok || bad "threads=$t emitted $n, wanted >= 600"
done
# More threads than queries: the thread count is clamped, not an error.
gen "$W/few.sql" --queries 3 --depth 5 --seed 3 --threads 32
[ "$(grep -c . "$W/few.sql")" -ge 3 ] && ok || bad "threads > queries"
# Auto thread count.
gen "$W/auto.sql" --queries 400 --depth 6 --seed 3 --threads 0
[ "$(grep -c . "$W/auto.sql")" -ge 400 ] && ok || bad "threads=0 (auto)"

# ---- stdout sink -------------------------------------------------------
"$BIN" --queries 200 --depth 6 --seed 5 --output - 2>/dev/null >"$W/stdout.sql"
[ "$(grep -c . "$W/stdout.sql")" -ge 200 ] && ok || bad "--output - to stdout"

# ---- depth handling ----------------------------------------------------
gen "$W/d0.sql" --queries 100 --depth 0 --seed 5
[ -f "$W/d0.sql" ] && ok || bad "--depth 0 must not crash"
gen "$W/dclamp.sql" --queries 50 --depth 99999 --seed 5
[ -f "$W/dclamp.sql" ] && ok || bad "--depth is clamped, not rejected"
gen "$W/shallow.sql" --queries 4000 --depth 8 --seed 11
gen "$W/deep.sql"    --queries 4000 --depth 8 --depth-max 16 --seed 11
S_AVG=$(awk '{t+=length($0)}END{printf "%d",t/NR}' "$W/shallow.sql")
D_AVG=$(awk '{t+=length($0)}END{printf "%d",t/NR}' "$W/deep.sql")
[ "$D_AVG" -gt "$S_AVG" ] && ok || bad "--depth-max must derive deeper ($D_AVG vs $S_AVG)"
# The constructs --depth-max exists to reach.
has "depth-max reaches subqueries" "$W/deep.sql" "\( *SELECT"
has "depth-max reaches CTE"        "$W/deep.sql" "^WITH "
has "depth-max reaches UNION"      "$W/deep.sql" " UNION "
# At the production depth, with no --depth-max headroom to hide behind, the
# discount has to hold in the walk as well as in the height table. If the walk
# charges depth for unit productions while the heights do not, choose() offers
# alternatives the walk cannot afford, and the density of the nested constructs
# halves. Presence alone does not catch that, so these are rates. Measured 28-29%
# subqueries and 3.3-3.7% UNION across seeds, against 15-16% and 0.7-0.9% when the
# walk charges depth; the floors sit between.
gen "$W/prod.sql" --queries 6000 --depth 10 --seed 12
has "depth 10 reaches CTE"  "$W/prod.sql" "^WITH "
N=$(grep -c . "$W/prod.sql")
Q=$(grep -cE "\( *SELECT" "$W/prod.sql")
U=$(grep -c -F " UNION " "$W/prod.sql")
[ $((100 * Q / N)) -ge 18 ] && ok || bad "depth 10 subquery rate $((100 * Q / N))%, floor 18%"
[ $((1000 * U / N)) -ge 15 ] && ok || bad "depth 10 UNION rate $((1000 * U / N))/1000, floor 15"
# The aggregates other than COUNT are only reachable because a choice the depth
# left with one alternative may be widened, and because a forced pick is not
# counted against that alternative. Break either and these go to zero: AVG, SUM and
# MIN were each 0 per 20000 statements while COUNT was 4664. Rates, not presence,
# and a ceiling on COUNT so it cannot go back to crowding the rule out.
gen "$W/agg.sql" --queries 20000 --depth 10 --seed 14
AN=$(grep -c . "$W/agg.sql")
for f in AVG SUM MIN MAX STD; do
  C=$(grep -c -F "$f(" "$W/agg.sql")
  [ $((10000 * C / AN)) -ge 100 ] && ok \
    || bad "$f rate $((10000 * C / AN))/10000, floor 100"
done
CN=$(grep -c -F "COUNT(" "$W/agg.sql")
AV=$(grep -c -F "AVG(" "$W/agg.sql")
[ "$CN" -lt $((AV * 8)) ] && ok || bad "COUNT $CN crowds out AVG $AV, want under 8x"
# Window functions are the construct that suffers most when the balance counting goes:
# they sit at the bottom of the expression grammar, where the walk only gets to choose
# at all because pass-through picks are not counted against the route that leads there.
# Measured 144 per 1000 statements, against 26 with the counting removed.
OV=$(grep -cE " OVER *\(" "$W/agg.sql")
[ $((1000 * OV / AN)) -ge 80 ] && ok \
  || bad "window function rate $((1000 * OV / AN))/1000, floor 80"
# --grants 0 turns the widening off, which is what starves the aggregates; it must
# still run, and produce fewer of them than the default does.
gen "$W/g0.sql" --queries 8000 --depth 10 --grants 0 --seed 14
gen "$W/g1.sql" --queries 8000 --depth 10 --grants 1 --seed 14
gen "$W/g2.sql" --queries 8000 --depth 10 --seed 14
G0=$(grep -c -F "AVG(" "$W/g0.sql"); G1=$(grep -c -F "AVG(" "$W/g1.sql")
G2=$(grep -c -F "AVG(" "$W/g2.sql")
[ "$G2" -gt "$G0" ] && ok || bad "--grants makes no difference to AVG: $G0 vs $G2"
# One grant per path reaches fewer aggregates than two. Stop spending them - leave the
# count alone as the walk descends - and every path has an unlimited supply, so this
# is what says the allowance is per path and is actually paid out of. Measured 1.23 to
# 1.36 across seeds, against exactly 1.00 for that mutant, so the floor sits between.
[ "$G2" -gt $((G1 * 23 / 20)) ] && ok \
  || bad "grants are not spent per path: AVG $G1 with one grant, $G2 with two"
# A lower chain share leaves more depth at the bottom, so statements get shorter and
# the leaf grammar is reached more often; a higher one nests more, and UNION is a
# rule chaining into itself. Both directions are asserted with a margin, because
# size alone still moves when the share is only partly applied - the ratio between
# the two groups has to be the one that was asked for.
gen "$W/cs20.sql" --queries 8000 --depth 10 --chain-share 20 --seed 15
gen "$W/cs80.sql" --queries 8000 --depth 10 --chain-share 80 --seed 15
S20=$(stat -c%s "$W/cs20.sql"); S80=$(stat -c%s "$W/cs80.sql")
[ "$S20" -lt "$S80" ] && ok || bad "--chain-share does not change nesting: $S20 vs $S80"
U20=$(grep -c -F " UNION " "$W/cs20.sql"); U80=$(grep -c -F " UNION " "$W/cs80.sql")
[ "$U80" -gt $((U20 * 2)) ] && ok \
  || bad "chain share does not drive chaining: UNION $U20 at 20% vs $U80 at 80%"
W20=$(grep -cE " OVER *\(" "$W/cs20.sql"); W80=$(grep -cE " OVER *\(" "$W/cs80.sql")
[ "$W20" -gt $((W80 * 2)) ] && ok \
  || bad "low chain share does not free the leaf: OVER $W20 at 20% vs $W80 at 80%"
# --probe reports the depth a rule was entered at, and how much of it was usable.
"$BIN" --queries 2000 --depth 10 --seed 16 --coverage 0 --probe sum_expr \
  --output /dev/null >/dev/null 2>"$W/probe.err"
has "probe reports entries"    "$W/probe.err" "probe: entered [0-9]+ times"
has "probe reports depth"      "$W/probe.err" "depth at entry:"
has "probe reports affordable" "$W/probe.err" "alternatives affordable:"
has "choice stats reported"    "$W/probe.err" "choices: [0-9]+"

# Balance spreads the run over each rule's alternatives, so most of the grammar gets
# tried. Drop the counting, or flatten the weight it feeds, and the walk goes back to
# picking uniformly among whatever the depth happens to afford - which still produces
# plausible SQL, so only the breadth shows it. Structural coverage measures exactly
# that: alternatives reached, keyword pools excluded.
"$BIN" --queries 20000 --depth 9 --seed 17 --threads 4 --coverage 0 \
  --output /dev/null >/dev/null 2>"$W/cov.err"
SC=$(grep -oE "structural [0-9]+/[0-9]+ \([0-9]+" "$W/cov.err" | grep -oE "\([0-9]+" | tr -d '(')
[ -n "$SC" ] && [ "$SC" -ge 90 ] && ok || bad "structural coverage ${SC:-unknown}%, floor 90%"

# Full-scale reach, release binary only (the same code runs 10-30x slower under
# sanitizers, and the floor above already runs there): at 500,000 statements and
# the production depth, the walk has to try 99%+ of the structural alternatives
# and enter all but a handful of the rules. This is the distribution bar for a
# whole fuzz run's input. A few rules sit behind a rare parent and need more
# depth than production uses - measured 1 to 3 unentered across seeds at depth
# 10, against 2 at depth 14 - so the allowance is 4, well under the dozens a
# real reach regression costs.
if [ "$(basename "$BIN")" = "revgen" ]; then
  "$BIN" --queries 500000 --depth 10 --seed 21 --threads 4 --coverage 0 \
    --output /dev/null >/dev/null 2>"$W/full.err"
  FS=$(grep -oE "structural [0-9]+/[0-9]+ \([0-9.]+" "$W/full.err" | grep -oE "[0-9.]+$")
  NE=$(grep -oE "rules never entered \([0-9]+" "$W/full.err" | grep -oE "[0-9]+$")
  awk -v s="${FS:-0}" 'BEGIN{exit !(s+0 >= 99)}' && ok \
    || bad "full-scale structural coverage ${FS:-unknown}%, floor 99%"
  [ "${NE:-99}" -le 4 ] && ok || bad "${NE:-unknown} rules never entered at 500k, allowed 4"
fi

# Random literals are drawn fresh each time. Cache them by mistake - the terminal
# text is worked out once for the ones that are fixed - and every number, hex string
# and bit string in the output becomes the same value.
gen "$W/lit.sql" --queries 8000 --depth 9 --seed 4
DN=$(grep -oE "\b[0-9]{1,3}\b" "$W/lit.sql" | sort -u | wc -l)
DH=$(grep -oE "X'[0-9A-F]+'" "$W/lit.sql" | sort -u | wc -l)
DB=$(grep -oE "0b[01]+" "$W/lit.sql" | sort -u | wc -l)
[ "$DN" -ge 100 ] && ok || bad "only $DN distinct numbers, want 100+"
[ "$DH" -ge 100 ] && ok || bad "only $DH distinct hex strings, want 100+"
[ "$DB" -ge 50 ]  && ok || bad "only $DB distinct bit strings, want 50+"

# A walk that hits its step or token cap has stopped part-way, so that statement is
# cut off and is thrown away rather than emitted. Deep derivations are where the cap
# is reached, so that is where both halves are checked: the count is reported, and
# nothing that got through has unbalanced brackets.
"$BIN" --queries 4000 --depth 18 --seed 4 --threads 2 --output "$W/cut.sql" \
  >/dev/null 2>"$W/cut.err"
has "truncated statements counted" "$W/cut.err" "cut=[0-9]+"
# Strip quoted text first: a string literal may hold an unpaired bracket of its own.
UNBAL=$(sed "s/'[^']*'//g; s/\"[^\"]*\"//g" "$W/cut.sql" \
        | awk '{o=gsub(/\(/,"("); c=gsub(/\)/,")"); if (o!=c) n++} END{print n+0}')
[ "$UNBAL" -eq 0 ] && ok || bad "$UNBAL emitted statements have unbalanced brackets"

# The CTE CYCLE clause only parses on a WITH RECURSIVE, and the walk cannot pair the
# two, so it is pruned; it was two thirds of the statements the server rejected. Only
# the clause is gone - CYCLE is also in a keyword pool, so it still turns up as an
# identifier and as a function name, which is why this matches the clause shape.
gen "$W/cyc.sql" --queries 12000 --depth 9 --seed 18
hasnt "CYCLE clause pruned" "$W/cyc.sql" "CYCLE [a-z0-9, ]+ RESTRICT"

# depth-max below depth is ignored rather than inverting the range.
gen "$W/dmlow.sql" --queries 200 --depth 8 --depth-max 3 --seed 11
[ -f "$W/dmlow.sql" ] && ok || bad "--depth-max below --depth"
# max-chain floor of 1, and a long chain bound.
gen "$W/mc.sql" --queries 300 --depth 7 --max-chain 0 --seed 11
[ -f "$W/mc.sql" ] && ok || bad "--max-chain 0 is raised to 1"
gen "$W/mc9.sql" --queries 300 --depth 7 --max-chain 9 --seed 11
[ -f "$W/mc9.sql" ] && ok || bad "--max-chain 9"

# ---- skip list ---------------------------------------------------------
# A statement holding any of these ends the session, stops the server, stalls the
# run, or sets a variable that makes everything after it useless, so the walk
# derives another instead. pquery-run.sh filters the output as well, with grep;
# revgen only has to keep out what would waste its own statements.
gen "$W/skip.sql" --queries 20000 --depth 10 --seed 13
for t in RELEASE SHUTDOWN SLEEP dbug KILL key_buffer_size net_retry_count \
         innodb_flush_log_at_timeout; do
  hasnt "skipped: $t" "$W/skip.sql" "$t"
done
"$BIN" --queries 20000 --depth 10 --seed 13 --output /dev/null 2>"$W/skip.err"
has "skip count reported" "$W/skip.err" "skipped=[0-9]+"

# ---- exclude and allow-unsafe -----------------------------------------
# SELECT .. INTO OUTFILE is the separate select_into rule, so both are named; the
# empty element checks that a trailing or doubled comma is tolerated.
gen "$W/ex.sql" --queries 2000 --depth 7 --seed 17 --schema-every 0 \
  --exclude select,select_into,insert,,update
hasnt "exclude dropped select" "$W/ex.sql" "^SELECT"
hasnt "exclude dropped insert" "$W/ex.sql" "^INSERT"
hasnt "exclude dropped update" "$W/ex.sql" "^UPDATE"
gen "$W/unsafe.sql" --queries 4000 --depth 7 --seed 17 --allow-unsafe
has "allow-unsafe restores admin SQL" "$W/unsafe.sql" "^(XA|LOCK|SHUTDOWN|KILL|RESET|INSTALL|CHANGE|BACKUP STAGE|PURGE)"
# --allow-locking restores the session-serialising statements only, for
# multi-threaded runs, and leaves the admin ones out.
gen "$W/lk.sql" --queries 6000 --depth 7 --seed 17 --allow-locking
has   "allow-locking restores locking SQL" "$W/lk.sql" "^(XA |LOCK TABLE|BACKUP STAGE)"
hasnt "allow-locking keeps admin out"      "$W/lk.sql" "^(SHUTDOWN|KILL|INSTALL|RESET|CHANGE MASTER)"
hasnt "default keeps locking out"          "$W/g.sql" "^(XA |LOCK TABLE|BACKUP STAGE)"

# ---- explicit lex path -------------------------------------------------
gen "$W/lex.sql" --queries 200 --depth 6 --seed 19 \
  --lex "$HOME/mariadb-qa/yacc/13.1_lex.h"
[ "$(grep -c . "$W/lex.sql")" -ge 200 ] && ok || bad "--lex explicit path"

# ---- PREPARE validation ------------------------------------------------
# REVGEN_TEST_NO_CLIENT skips everything that enters libmysqlclient. Under MSAN
# the client library and the OpenSSL it initialises are uninstrumented system
# builds, so every read they make of their own memory reads as uninitialised and
# no suppression covers it.
# A socket file alone does not mean a live server: this box reaps long-running
# test servers, so the file often outlives the process. Probe before relying on
# it, with revgen itself so no client binary path is assumed.
server_answers() {
  "$BIN" --queries 5 --depth 5 --seed 1 --threads 1 --validate-sql \
    --socket "$SOCKET" --db test --output /dev/null 2>&1 |
    grep -qE "validation disabled|connect failed" && return 1
  return 0
}
if [ -n "${REVGEN_TEST_NO_CLIENT}" ]; then
  skip "PREPARE validation (client library excluded)"
elif [ -S "$SOCKET" ] && server_answers; then
  "$BIN" --queries 3000 --depth 8 --seed 23 --validate-sql \
    --socket "$SOCKET" --db test --output "$W/v.sql" --fails "$W/v.fails" \
    >/dev/null 2>"$W/v.err"
  has "validate counts prepared" "$W/v.err" "prepared=[0-9]+"
  has "validate reports rate"    "$W/v.err" "parse-valid rate=[0-9.]+%"
  [ -f "$W/v.fails" ] && ok || bad "validate must write the --fails file"
  # Measuring the rate writes output to /dev/null, so the derived fails path is
  # unwritable; the log has to land somewhere rather than be dropped.
  "$BIN" --queries 300 --depth 6 --seed 26 --validate-sql \
    --socket "$SOCKET" --output /dev/null >/dev/null 2>"$W/devnull.err"
  has "fails log falls back" "$W/devnull.err" "logging to /|parse-valid rate"
  R=$("$BIN" --queries 3000 --depth 8 --seed 24 --validate-sql \
      --socket "$SOCKET" --output /dev/null 2>&1 |
      grep -oP 'parse-valid rate=\K[0-9]+')
  # The walk emits SQL the server can parse. Below this the grammar handling has
  # regressed; the measured rate at depth 8 is around 98.7%.
  [ -n "$R" ] && [ "$R" -ge 95 ] && ok || bad "parse-valid rate ${R:-unknown}% below 95%"
  # Default --fails path is derived from the output directory.
  "$BIN" --queries 200 --depth 6 --seed 25 --validate-sql \
    --socket "$SOCKET" --output "$W/dflt.sql" >/dev/null 2>&1
  [ -f "$W/revgen_failed_1064.sql" ] && ok || bad "default --fails path"
elif [ -n "${REVGEN_TEST_SOCKET}" ]; then
  skip "PREPARE validation (no live server at $SOCKET)"
fi
# An unreachable socket disables validation and still emits.
if [ -n "${REVGEN_TEST_NO_CLIENT}" ]; then
  skip "bad-socket path (client library excluded)"
else
  "$BIN" --queries 200 --depth 6 --seed 27 --validate-sql \
    --socket "$W/no.sock" --output "$W/nv.sql" >/dev/null 2>"$W/nv.err"
  has "bad socket disables validation" "$W/nv.err" "validation disabled|connect failed"
  [ "$(grep -c . "$W/nv.sql")" -ge 200 ] && ok || bad "bad socket must not stop generation"
fi

echo "----"
echo "pass=$PASS fail=$FAIL skip=$SKIP"
[ "$FAIL" = 0 ]
