# corlogic

corlogic runs the same SQL on two or more servers at once and reports where they answer
differently. It is a differential tester: no expected results, no test suite. The other
server is the oracle.

A "side" is one running server. Sides can differ by build, by storage engine, by server
options, or by one `optimizer_switch` combination. Every difference that survives a
reduction and two replays becomes a paste-ready bug report.

## Build

```
  ./build.sh                # release            -> corlogic
  ./build.sh debug          # -O0 -g3            -> corlogic_dbg
  ./build.sh static         # fully static       -> corlogic_static (needs libp11-kit-dev)
  ./build.sh ubasan         # UBSAN + ASAN       -> corlogic_ubasan
  ./build.sh msan           # MSAN               -> corlogic_msan
  ./build.sh tsan           # TSAN               -> corlogic_tsan
  ./build.sh all            # release, debug, ubasan, msan and tsan, in order
  ./build.sh coverage       # instrumented, then measure and report
```

Every build runs `./corlogic --selftest` before it keeps the binary. A build that fails
the tests is left as `corlogic.failed` and the script exits non-zero. `./build.sh coverage`
runs the tests and twenty run shapes over an instrumented binary and reports the line
coverage, currently 82.1%; it exits non-zero below `COVERAGE_TARGET`, 75 by default.

MSAN reads every byte it sees, so it needs the client library to be instrumented too.
`./build.sh msan` links against an MSAN MariaDB basedir when `gendirs.sh msan` lists one,
and says which it used. With no such basedir it links the stock client library, and then a
workload stops in pre-flight on reports from inside that library rather than from corlogic:
the mode covers the selftest only, and the build says so.

A binary in this directory can be older than the source beside it. A run says so on its
first log line when that is the case, so a sanitizer binary built by hand is not read as
the current tool.

## Run

```
  ./corlogic /test/<basedir-a> /test/<basedir-b>
```

One basedir alone runs A/A: the same build against itself, which is how you check that
the tool itself is quiet. Any setting from `corlogic.conf` also works on the command
line:

```
  ./corlogic TRIALS=500 QUERIES_PER_TRIAL=2000 WORKERS=24 \
    /test/MD180826-mariadb-13.0.2-linux-x86_64-opt \
    /test/MD180826-mariadb-13.1.0-linux-x86_64-opt
```

| Option | Meaning |
|---|---|
| `--config FILE` | config file to read; `./corlogic.conf` by default, else the one beside the tool |
| `--check` | run the pre-flight probes, print the support matrix, exit |
| `--resume ID` | carry on in the workdir of run `ID`, with its options and counters |
| `--selftest [N]` | run the unit tests, `N` threads for the concurrent pass, exit |
| `--seed N` | fixed seed, so a run repeats |
| `--version` | print the version, exit |

## What comes out

Results go to `WORKDIR_BASE/<7-digit run id>`, runtime state to `RUNDIR_BASE/<same id>`,
which is `/dev/shm` unless it is set. That directory holds a `corlogic.pid`, so `~/ds` can
tell a live run from one that is over, and clear the one that is over along with any server
still holding it.

| File | Holds |
|---|---|
| `bugN.report` | the finding, in Jira syntax: title, testcase, both outcomes, the version matrix |
| `bugN.log.sh` | a ready `~/jira` call that files `bugN.report` |
| `bugN.sql` `bugN.core` `bugN.master.err` | a crash finding only |
| `bugs.seen` | every candidate and bug, with its UID |
| `corlogic-<id>.log` | the run log |
| `pr` | run it in the workdir for a summary of the run |
| `corlogic.cursor` | combinatorics only: the next combination |

## What the run log counts as a note

A note is a difference the tool measured and did not report, with the reason. The end of the
run counts each kind: rows in a different order that a total ORDER BY showed to be a tie,
different rows under a LIMIT that never specified which rows, a warning-only difference, a
plan estimate that moved between two reads, a plan whose shape changed so the estimates are
not comparable, a plan whose two sides join the same tables in a different order so the
access types are not comparable, a plan read held back because a transaction was open, and
a statement where one side met contention, a deadlock or a time limit. The last kind also
stops the trial when the statement writes, because from there the two sides hold different
rows.

The version matrix in a report answers one question per build: did this build behave like
the build the run compared against. A build that agreed reads `Same as base/source`, not
`No diff found`, because the build it was compared against was never assessed itself. Where
both sides of a run share a defect, every build that shares it agrees, and the matrix cannot
say more than that.

## The settings that matter most

| Setting | What it does |
|---|---|
| `QUERIES_PER_TRIAL` | generated statements per trial. Lower reduces faster, higher finds more |
| `TRIALS` | 0 runs until you stop it |
| `WORKERS` | servers the box may run at once. Left at 0 the run measures what the box carries |
| `PLAN_COMPARE` | compare execution plans as well as results |
| `ENGINES` | `innodb,myisam` makes one side per engine on one build |
| `OPTIONS_SETS` | one side per server-option group |
| `OPTIMIZER_SWITCH_COMBINATORICS` | side 2 runs one `optimizer_switch` combination per trial |
| `REDUCE_TIMEOUT` | seconds a reduction may spend before it hands back what it has |
| `KNOWN_FILE` | the known-difference filter; one path or a comma list. Left empty the run picks its own, see below |

`corlogic.conf` carries every setting with a one-line comment. `corlogic.weights` is the
generator weight file the run passes on.

## Filtering what you already know

`corlogic.known` mutes a difference by its UID. A UID is
`CATEGORY|MECHANISM|CONSTRUCTS|STATEMENT`, and it is printed at the end of every report.
A field of `*` matches anything, a field ending in `*` matches by prefix, and a field
wrapped in `*` matches anywhere in the value, so one line can mute a whole family. Use the
last form for a family a construct triggers rather than a statement shape, since the
construct can sit anywhere in the statement.

The third field is a set of tokens, comma separated and sorted, naming what the statement
contains: its shape (JOIN, SUBQ, GROUPBY), its verb (INSERT, ALTER), and the dialect
features a version or a vendor difference turns on (CSINTRO for a charset introducer, JSON,
SEQ, GENCOL, SPATIAL, VECTOR). Match it with the wrapped form, `*CTE*`; a prefix only
matches when that token sorts first. On that field the wrapped form is anchored on the
commas, so `*IN*` is the token `IN` and not the `IN` inside `INSERT`.

Two more tokens exist in the code, `COLLATE` and `WINDOW`, and neither can reach a UID as
the stream filter stands: the filter drops every statement holding `COLLATE` or a window
frame, because a window frame leaves the order of tied rows unspecified. Relax the filter
and they appear.

In the statement field each number reads `N`, each string `'X'`, each table `tX` and each
column `cX`, so two findings that differ only in the table or column they touch share one
UID.

An entry that names one statement does not hide the same defect reached another way. A
finding that agrees with such an entry on the category and the mechanism, on a statement
the entry does not name, is still reported, and the report says which entry it sits beside
so it can go on that ticket instead of becoming a new bug. A comment above an entry naming
an MDEV or MENT number puts that number in the notice. The notice needs a mechanism that
names both sides, an error pair or an affected-count pair among them. A mechanism naming
neither side, `content` and `coltype` for example, is shared by too much to say anything,
so it gets no notice.

`corlogic.known.INFO` is the long form beside it: one section per entry with the cause,
the code citations and the evidence, plus the differences that were looked at and left
unmuted on purpose.

## Running an engine matrix

`ENGINES=innodb,myisam,aria` makes one side per engine on one build. Two families of
difference come out of that on their own, and neither is a defect:

- a statement that stops part-way. InnoDB undoes the whole statement, MyISAM and Aria
  keep the rows they already wrote, so every later read of that table differs.
- a feature only one engine has, such as an index on a virtual column.

An engine that ships as a plugin is loaded by name, so `ENGINES=innodb,rocksdb` works with
no extra options. The testcase in the report installs the plugin and sources the guard the
test tree ships for that engine, so it runs under `./mtr` as it is written.

corlogic handles the first one itself: on an engine axis where one side is not
transactional, a trial stops at the first statement that fails on every side, because from
there on the sides hold different rows. Nothing is compared after that, the end-of-trial
table scan included. The run log counts those stops. It costs the rest of each such trial,
which is the price of comparing like with like.

That cost is large. On a 12-trial innodb / myisam / aria run, 11 trials stopped early and
the statements executed per trial were 107 to 318 against a stream of about 500, so the run
reached about a quarter of its stream. A same-build run reaches all of it. Read an engine
run's trial count with that in mind: a trial there is worth less than a trial elsewhere.

One file takes care of the rest, and one mutes the feature gap, so what is left is worth
reading. `corlogic.known.engines` is added by the run itself, because more than one engine
is named:

```
  ./corlogic ENGINES=innodb,myisam,aria \
    SQL_FILTER_FILE=corlogic.filter.engines \
    /test/<basedir>
```

## Running MariaDB against MySQL

The two products promise different things in places, so a cross-vendor run finds the
dialect before it finds a defect: a function only one of them has, `DELETE QUICK` which is
a keyword on one side and a table alias on the other, an unused common table expression
whose columns only one of them resolves, and a subquery on the table being updated.
`corlogic.known.mysql` mutes those families and nothing else, and the run adds it by itself
once it has probed a MariaDB side and a MySQL side:

```
  ./corlogic /test/<mariadb-basedir> /test/<mysql-basedir>
```

Either list is added to `corlogic.known`, never swapped for it, so the differences that are
known whatever the sides are stay muted. A `KNOWN_FILE` you name wins outright, and it may
name several files, comma separated.

Error codes are compared by state on a cross-vendor run, not by code, because the numbers
do not mean the same thing. corlogic works that out itself from the two versions.

## Design

`plan.md` holds the specification and the milestone list: what counts as a difference,
how the environment is held still, how a candidate is reduced, and what the reports
promise. `../generatorcpp/generator_bugs.md` tracks what the SQL generator still gets wrong.
