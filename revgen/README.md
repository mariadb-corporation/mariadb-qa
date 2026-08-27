# revgen

Reverse SQL generator driven by the MariaDB bison grammar. It reads a
`sql_yacc.yy`, derives random statements top-down from the grammar rules up to a
depth budget, fills identifiers and literals with names typed by the slot they
sit in, interjects a schema so the generated DML has something to work on,
and (optionally) PREPARE-validates each statement against a live server.

## Build

```
./build.sh              # revgen (-O2), then test.sh, then the coverage gate
BUILD=dbg ./build.sh    # revgen_dbg (-O0 -g), then test.sh
BUILD=cov ./build.sh    # coverage report only
BUILD=asan ./build.sh   # also: ubasan, msan, tsan
SKIP_TESTS=1 ./build.sh     # build only
SKIP_COVERAGE=1 ./build.sh  # build and test, no coverage gate
```

libc++ is used to avoid the gcc-14 libstdc++ `<unicode.h>` clash with clang.
`--validate-sql` links the system `libmysqlclient`.

Every default build runs `test.sh` and then measures line coverage of
`revgen.cpp` with `llvm-cov`, failing below 95% (`COV_MIN` overrides). The suite
is what stands between a grammar-handling regression and thousands of wasted
trials, so a change that is not covered is a change nothing checks.

MSAN links the instrumented libc++ from `/MSAN_libs`; the tests that enter
`libmysqlclient` are skipped there, because it and the OpenSSL it initialises are
uninstrumented system builds and no suppression covers that.

## Test

```
./test.sh [binary]      # default ./revgen
```

Server-backed tests use `/test/CLAUDE1/socket.sock`, overridable with
`REVGEN_TEST_SOCKET`, and skip when it is absent. `REVGEN_TEST_NO_CLIENT=1` skips
everything that enters the client library. `REVGEN_TEST_KEEP=1` keeps the scratch
directory.

## Run

```
./revgen --queries 100000 --depth 9 --output out.sql
./revgen --queries 100000 --validate-sql --socket /test/CLAUDE1/socket.sock \
         --output out.sql --fails failed_1064.sql
```

Flags:

- `--yacc PATH`     grammar file. Default `$HOME/mariadb-qa/yacc/13.1_sql_yacc.yy`
                    (shipped with mariadb-qa). Errors out if the file is missing.
- `--lex PATH`      `lex.h` keyword table. Default: version-matched sibling of
                    `--yacc` (`13.1_sql_yacc.yy` -> `13.1_lex.h`). Errors out
                    when the file holds no `SYM()` entries. See Grammar files.
- `--queries N`     statements to emit. Default 100000.
- `--depth N`       derivation depth budget. Default 9 (clamped to 2000).
- `--depth-max N`   derive one statement in four at a random depth between
                    `--depth` and this. Default off. What reaches subqueries,
                    CTEs, UNION and window functions.
- `--max-chain N`   times a rule may chain into itself before its chaining
                    alternatives are withheld. Default 3.
- `--chain-share N` percent of the time a rule chains into itself rather than
                    moving on, where it can do either. Default 30. Lower leaves
                    more depth for the bottom of an expression, which is where
                    the aggregates and window functions are; higher nests more,
                    which is where UNION is.
- `--grants N`      times one derivation may widen a choice the depth left with
                    a single alternative. Default 2, 0 disables. Counted per
                    path, so a widened subtree cannot widen again.
- `--schema-every N` interject the setup/reset block every N statements.
                    Default 25, 0 disables. The tables go back every fourth
                    interval, the routines and views every sixteenth, the rest
                    every thirty-second.
- `--coldefs PATH`  column definitions the `t1`-`t4` shapes are built from, one
                    per line. Default: sibling of `--yacc`, so
                    `13.1_sql_yacc.yy` pairs with `13.1_coldefs.txt`. Written by
                    `yacc/harvest_coldefs.sh`. Missing: the plain shapes carry
                    the run.
- `--wild-cols N`   percent of columns whose type is derived from the grammar
                    rather than taken from `--coldefs`. Default 12, 0 disables.
- `--start SYM`     start symbol. Default `verb_clause`.
- `--seed N`        base RNG seed. Default: random. Threads derive from it.
- `--threads N`     generation threads. Default: nproc/4.
- `--output FILE`   write output here. Default: `out.sql`; `-` writes to stdout.
- `--validate-sql`  PREPARE-test each statement; drop on parse error (1064).
- `--socket PATH`   server socket for `--validate-sql`. Default
                    `/test/CLAUDE1/socket.sock`.
- `--db NAME`       database for `--validate-sql`. Default `test`.
- `--fails FILE`    log dropped 1064 statements. Default
                    `<output-dir>/revgen_failed_1064.sql`, falling back to the
                    temp directory when that is not writable.
- `--exclude A,B`   also prune these nonterminals.
- `--probe RULE`    with `--coverage`, report the depth left and the number of
                    alternatives affordable each time RULE was entered.
- `--allow-unsafe`  keep admin/replication statements (CHANGE MASTER, SHUTDOWN,
                    KILL, INSTALL, RESET, ...); skipped by default.
- `--allow-locking` keep LOCK TABLES, BACKUP LOCK and XA. Worth having only when
                    several client threads contend, so it is off by default and
                    on in the multi-threaded pquery config. Implied by
                    `--allow-unsafe`.

Diagnostics (print and exit, except `--coverage`):

- `--info`          grammar stats, the start symbol's minimum height, and the
                    rules no derivation can complete - which is how a prune that
                    silently removes a statement class gets noticed.
- `--dump`          all productions of `--start`.
- `--trace`         the minimum-height derivation of `--start` (flags silent
                    terminals and empty productions).
- `--audit`         referenced terminals that emit nothing, by ref-count.
- `--names`         every production holding an identifier leaf, keywords
                    rendered as SQL and the leaf as `<ID>`. Checks the
                    identifier-role table against the whole grammar rather than a
                    guessed subset.
- `--parens`        every `'(' X ')'` where X can derive nothing, at any position
                    in a production - so `CONTAINS_SYM '(' opt_expr_list ')'` is
                    found, not only a rule that is exactly `'(' X ')'`.
- `--coverage [N]`  after generating, report which grammar alternatives the run
                    reached. N caps the untried-alternatives list (0 = no cap).

## Grammar files

revgen reads three files per server version, all in `mariadb-qa/yacc/`:

| File | Copied from | Holds |
|---|---|---|
| `<version>_sql_yacc.yy` | `sql/sql_yacc.yy` | the grammar revgen walks |
| `<version>_lex.h` | `sql/lex.h` | the text of each keyword |
| `<version>_coldefs.txt` | written by `yacc/harvest_coldefs.sh` | the column types the tables are built from |

`--yacc` names the grammar and the other two default to its version-matched
siblings, so `13.1_sql_yacc.yy` takes `13.1_lex.h` and `13.1_coldefs.txt`. The
grammar and the keyword table have to come from the same source tree.

`sql/lex.h` and `sql/sql_lex.h` sit next to each other in the server tree and
have near-identical names. `sql/sql_lex.h` holds no `SYM()` entries. With that
file in place revgen finds no text for any keyword, every keyword drops out of
the derivation, and the output is unparsable fragments that no server can
execute. Nothing about the run looks wrong: the hardcoded setup block still
reads as valid SQL. revgen therefore stops with an error when the keyword table
holds no `SYM()` entries, and `pquery-run.sh` makes the same check before a run
starts.

Install a matched pair with the refresh script. It copies both files and checks
each one before it installs anything:

```
./refresh_grammar.sh /test/git-bisect/13.1     # version taken from the directory name
./refresh_grammar.sh /test/10.11 10.11
./refresh_grammar.sh all                       # every tree under /test/git-bisect
```

The column definitions come from the test suite of that version rather than
from its source, so they are harvested separately:

```
../yacc/harvest_coldefs.sh /test/git-bisect/13.1/mysql-test 13.1 [socket]
```

With a running server of that version given as the third argument, only the
definitions that server accepts are kept.

## How it works

1. Reads the grammar and replays the MARIADB/ORACLE preprocessor of
   `gen_yy_files.cmake`: the MARIADB branch of every `%ifdef` is kept, the
   ORACLE branch dropped. This matches the default server parser and avoids
   duplicate rule heads.
2. Scans the rules section, skipping semantic actions, comments and `%prec`
   directives. Rule heads are nonterminals; any named symbol never seen as a
   head is a terminal. A rule may omit its trailing `;` (GNU bison allows it) -
   the next `ident :` starts a new rule. Productions whose action only raises a
   parse error are dropped: the grammar accepts them to give a better message.
3. Terminals resolve to text: keyword tokens via the `lex.h` symbol tables;
   `IDENT`/`NUM`/`TEXT_STRING`/etc. to typed or random data; char-literals
   verbatim; the lexer-synthesised operators (`:=`, `->`, `(` variants) and the
   tokens the lexer builds by collapsing two keywords in a lookahead
   (`VALUES LESS`, `WITH SYSTEM`, `FOR SYSTEM_TIME`, ...) mapped explicitly.
   Without those the pair is dropped and the statement comes out truncated.
4. Statement classes are weighted (`kVerbWeights`) toward SELECT and the DML that
   carries the deep expression and subquery grammar. An unweighted walk puts
   every one of the 48 alternatives near 2%.
5. Generation picks productions that fit the remaining depth budget; when the
   budget runs out it takes a shortest terminating production, at random when
   several tie, so it always ends and deep subtrees do not all collapse to one
   shape. A minimum-height table per nonterminal drives that choice.
6. A unit production - one nonterminal, nothing else - emits no text, so it costs
   no depth, in both the height table and the walk. The grammar is full of them:
   the operator-precedence cascade from `expr` down to `simple_expr` is eleven,
   and `select` reaches `query_specification` through six more. Counting them put
   `select` at height 20 against a depth budget of 13, which made the
   highest-weighted statement unreachable and left the aggregate and
   function-call alternatives permanently out of budget. A run of consecutive
   free steps is capped so a cycle of unit productions cannot loop.
7. An alternative is weighted by how little it has been used, so a run spreads over
   each rule's alternatives instead of re-picking whichever the RNG favours. Only
   the alternatives that emit something are counted: a unit production is a
   pass-through, so a pick of one is not an output occurrence, and counting it held
   back everything behind it. `primary_base_expr` routes to
   `column_default_non_parenthesized_expr`, which is the only way to any aggregate,
   and once that route had been taken often enough the balance read it as over-used
   and stopped taking it. Counting emitting alternatives only is the difference
   between 37% of statements carrying a subquery and 11%, and between 192 window
   functions per 1000 statements and 1.
8. How often a rule chains into itself is set (`--chain-share`), not left to how
   many of its alternatives happen to chain. `expr` offers seven chaining
   alternatives against one exit into the next precedence level, so an even choice
   chains seven times in eight; over the eleven levels of the cascade that spends
   the whole depth budget on operator nesting before any leaf is reached.
9. A choice the remaining depth left with a single alternative is not a choice, and
   that is where every expression ends up. There, and only there, the budget is
   widened by three (`--grants`). `sum_expr` was entered 3188 times per 5000
   statements with one of its 22 alternatives affordable, so `COUNT(*)` was the only
   aggregate it could build. Grants are counted per path and each is spent for good,
   and a pass-through does not spend one - widening a rule that only routes buys
   nothing, and spending a grant there left none for the rule at the bottom.
10. Every symbol is numbered once the grammar is final, and each one's facts - its
   productions, whether it is an identifier leaf, its role, its alternatives'
   heights - are held in arrays indexed by that number. Looking them up by name was
   the bulk of the run: three string-keyed hash maps and the hash itself came to
   59% of the time.
11. A statement holding `RELEASE`, `SHUTDOWN`, `SLEEP`, `dbug`, `KILL`,
   `key_buffer_size`, `net_retry_count` or `innodb_flush_log_at_timeout` is derived
   again instead: each one either ends the session, stops the server, stalls the run
   or sets a variable that makes everything after it useless. A walk that hit its
   step or token cap stopped part-way, so that statement is cut off and is thrown
   away too. `pquery-run.sh` filters the output as well, with grep, so revgen only
   keeps out what would waste its own statements.
12. Threads split the query count, each writing a part file that is concatenated
   into the output at the end.

## Typed identifiers and the setup block

Identifier leaves are filled by the role of the slot they sit in, so a name one
statement creates is a name a later statement can reference. The names are
generatorcpp's, so in a mixed run each generator's statements resolve against
the other's objects: `t1`-`t4` tables, `c1`-`c4` columns, `sp1`/`sp2`
procedures and savepoints (own server namespaces), `f1`/`f2` functions,
`cv1`/`cv2` views, `tr` triggers, `ev` events, `cs` sequences, `ci` indexes,
`chk` constraints, `p` partitions, `u` users, `r` roles, `d` databases, `srv`
servers, `cur` cursors, `a` aliases, `s1`/`s2` prepared statements, `w1`/`w2`
windows, `cte1`/`cte2` CTEs, `@a`/`@b`/`@c` user variables, `i1`/`i2` where no
more specific slot is known. A keyword in the production types the name that
follows it, which is how `CREATE PROCEDURE` and `CREATE FUNCTION` are told
apart when both route through `sp_name`.

`--names` lists every production with an identifier leaf, so the role table can
be checked against the whole grammar instead of a guessed subset.

The setup block creates everything those names refer to. A grammar walk cannot
build a usable table of its own: its `CREATE TABLE` derivations almost never
reach a plain column list.

`t1`-`t4` are built once per run rather than written out here. `c1` is always the
integer primary key the generated DML leans on; `c2` to `c4` take a real column
definition from `--coldefs`, which `yacc/harvest_coldefs.sh` takes from the test
suite of the version under test and checks against a server of that version. A
type the version added is therefore covered without a list here to maintain. One
column in eight has its type derived from the grammar instead (`--wild-cols`),
which reaches shapes no test file holds; about one built table in six is refused
by the server, and the plain shape emitted behind it carries those. The engine,
the table options and which two of the four tables carry partitions are picked
per run too, so separate trials meet separate schemas while one trial keeps a
single shape. Partitioning all four spent a third of the trials on one known
partitioning assert, so two carry partitions and two do not, and a `PARTITION()`
clause the walk puts on one of the others is moved to one that has them.

Every line of the block is a line of the file that is not generated SQL, so each
one goes out at the rate at which what it holds is destroyed: `COMMIT` every
interval, the tables and their rows every fourth, the routines, views, sequences
and typed rows every sixteenth, and the users, roles, servers, events, triggers,
indexes, prepared statements and session settings every thirty-second. The two
unlock lines are only emitted with `--allow-locking`, which is what lets the walk
hold a lock in the first place. The file is shuffled before it is used, so every
line stands on its own: `IF NOT EXISTS`, `OR REPLACE` or `IGNORE` throughout.

## Validation

With `--validate-sql`, each statement is `PREPARE`d against the server. errno
1064 (ER_PARSE_ERROR) means the syntax is wrong - the statement is dropped and
logged to the fails file. Other errors (unknown table, type mismatch, ...) are
semantic; the syntax is fine, so the statement is kept. Statements that cannot
be prepared at all (SET, USE, transaction control, ...) skip the PREPARE and are
kept.

After the rate, the run prints those other rejections clustered by error code,
worst first, with one example message each. A statement the server refuses for a
bad date is as lost to a generator run as an unparseable one, and only the code says
which kind, so this is the list to work down. Two things it shows that the rate
alone hides. A value the server does not know masks whatever is wrong further
along: with `COLLATE i1` the statement stops at "Unknown collation", and with a
real collation name the same statement reaches a genuine syntax error, so the
parse rate falls while nothing has got worse. And removing one whole class of
rejection moves the total very little, because the freed statements fail on
their next fault - the four classes worth 11,398 of 20,294 rejections that the
fixed vocabularies removed bought 415 more accepted statements. Semantic
acceptance is around 60% and barely moves with depth (62% at 6, 59% at 12).

Measured parse-valid rate: 98.3% at depth 6, 97.7% at depth 9, 97.0% at depth 11,
96.7% at depth 13. Deeper derivations reach more of the grammar and get more of it
wrong, so the two have to be measured together - `--coverage` for reach,
`--validate-sql` for correctness. Depth 9 reaches 93% of the structural grammar
alternatives at 20000 statements, and more with a longer run: coverage is a
property of the run length as well as the depth.

PREPARE of generated SQL reaches crashing code paths, so a validation server has
to be one whose death does not matter, and a rate measured over a run that lost
its server is a rate over whatever ran before that.

A statement the grammar derives but the server rejects with 1064 is a
grammar-versus-server discrepancy. Two kinds turn up. A token the lexer only
produces under a non-default `sql_mode` - `MYSQL_CONCAT_SYM` needs
PIPES_AS_CONCAT, `NOT2_SYM` needs HIGH_NOT_PRECEDENCE - has no default spelling,
so the productions offering it are pruned. And a production whose symbols bison's
precedence rules will not actually admit in every context that uses the rule:
`bit_expr` has interval-first forms whose trailing symbol is a full `expr`, which
puts a logical operator at `bit_expr` level, and `UPDATE .. FOR PORTION OF .. FROM
.. TO` then fails to parse. revgen walks productions and does not model
precedence, so these are pruned rather than resolved. After triage, genuine ones
are logged under `~/mariadb-qa/security/YACC/`.

## Scope

Output is grammar-faithful, not semantically valid: names come from fixed pools
with no knowledge of what exists on the server, so statements that parse can
still fail on an unknown column or a type mismatch. There is deliberately no
server-awareness pass - generatorcpp does not have one either.
