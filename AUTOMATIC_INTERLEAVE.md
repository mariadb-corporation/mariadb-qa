# AUTOMATIC_INTERLEAVE

`pquery-run.sh` can pick random SQL lines from `INFILE`, or from the SQL files on the disk, keep
only the lines the server under test parses, and insert them into every trial's SQL at a fixed
interval. A new set of lines is picked every N trials. The feature is off by default.

It extends `INTERLEAVE`, which inserts the fixed `INTERLEAVE_SQL` every `INTERLEAVE_LINES` lines.
With both on, `INTERLEAVE_SQL` and the picked lines form one set.

## Options

| Option | Default | Meaning |
|---|---|---|
| `AUTOMATIC_INTERLEAVE` | 0 | 1 adds the picked lines to the interleaved SQL. Works without `INTERLEAVE=1` |
| `AUTOMATIC_INTERLEAVE_SQL_COUNT` | 5 | Lines per set |
| `AUTOMATIC_INTERLEAVE_NEW_SQL_EVERY_X_TRIALS` | 50 | A new set at trial 1, 51, 101, and so on |
| `AUTOMATIC_INTERLEAVE_FROM_ALL_DISK_SQL` | 0 | 0 picks from `INFILE`, also with `USE_INFILE=0`. 1 picks from any `*.sql` file on the disk |

`INTERLEAVE_LINES` (default 100) sets how often the set is inserted.

A run stops at startup with an `Assert` when a value is invalid. The two switches must be 0 or 1.
The count and the interval must be positive whole numbers of at most 10 digits.

While `AUTOMATIC_INTERLEAVE=0`, the other three options do nothing, but they are still validated,
and the trial SQL is the same as without them. `AUTOMATIC_INTERLEAVE_FROM_ALL_DISK_SQL=1` on its own
builds no disk index and picks nothing, so the run logs this warning at startup, on the console and
in `pquery-run.log`:

```
Warning: AUTOMATIC_INTERLEAVE_FROM_ALL_DISK_SQL=1 has no effect while AUTOMATIC_INTERLEAVE=0, so no interleave SQL lines are picked from the disk
```

### Turning it on

In the configuration file:

```
AUTOMATIC_INTERLEAVE=1
AUTOMATIC_INTERLEAVE_SQL_COUNT=5
AUTOMATIC_INTERLEAVE_NEW_SQL_EVERY_X_TRIALS=50
AUTOMATIC_INTERLEAVE_FROM_ALL_DISK_SQL=0
```

The `pquery-run*.conf` templates carry these four lines after `INTERLEAVE_LINES`, with the feature
off. A configuration file without them gets the defaults above.

Other settings that affect the picks:

- `INFILE` is the source when `AUTOMATIC_INTERLEAVE_FROM_ALL_DISK_SQL=0`.
- `ADV_FILTER_SQL` and `FILTER_SQL` filter the picks, as they filter the trial SQL.
- `MYSQLD_START_TIMEOUT` limits how long the syntax-check server may take to start, and to check
  the lines.

## How a run uses it

### At startup

- The options are validated.
- A `.tar.*` `INFILE` is unpacked, also when only the picks use it.
- With `AUTOMATIC_INTERLEAVE_FROM_ALL_DISK_SQL=1`, every `*.sql` file on the disk is indexed once
  per run. This is the index `USE_ALL_DISK_SQL` uses, and it is built once when both are on.

### When a new set is due

1. Sample. From `INFILE`: 100 times the count random lines. From the disk: 5 random lines from each
   of 20 times the count random files, every file with the same chance, and then 100 times the
   count random lines from those. Every random choice takes its random bytes from the framework's
   xoshiro256++ RNG, `random` (`RANDOM_BIN`), through `shuf --random-source`, as the `INFILE`
   source and the per-trial shuffle do.
2. Clean and filter. The sample gets the same clean-up as the trial SQL. Then:
   - `ADV_FILTER_LIST` applies when `ADV_FILTER_SQL=1`, and always to lines from the disk.
   - `filter.sql` applies when `FILTER_SQL=1`.
   - Empty lines, lines over 4096 bytes and duplicates are dropped.
   - The first 10 times the count lines go on to the syntax check.
3. Syntax check. The first count lines that parse become the set. See the next section.
4. The set is saved to `${TRIAL_SQL_DIR}/<RANDOMD>_auto_interleave.sql`, and each line is logged.
5. If fewer than count lines are left, a warning is logged. If none are left, the run stops with an
   `Assert`.

### Every trial

- After the shuffle and the storage-engine swap, the set is inserted every `INTERLEAVE_LINES` lines:
  `INTERLEAVE_SQL` first when `INTERLEAVE=1`, then the picks.
- The picks are copied as they are, so no backslash escapes are processed in them.
- The table-name swaps (`SWAP_CREATE_TABLE_NAMES_TO_T1`, `SWAP_ALL_TABLE_NAMES_TO_T1`) apply to the
  picks, as they do to `INTERLEAVE_SQL`.
- If the set file disappears mid-run, a new set is picked at the next trial.

### At the end of the run, and on Ctrl-C

The set file is removed with the rest of the run's SQL. Ctrl-C also kills a syntax-check server
that is running.

## Syntax check

- A throwaway server from `BASEDIR` starts in `${RUNDIR}/syntax_check`. It has an empty datadir,
  listens on a socket only, has no grant tables, and writes no core files.
- It runs `PREPARE` on each line. `PREPARE` parses a statement without running it.
- Parse errors 1064, 1065 and 1149 drop the line. Any other result keeps it, for example 1146 for a
  missing table, or 1295 for a statement that cannot be prepared.
- A line that crashes or hangs the server is dropped and logged, and a new server checks the lines
  after it. A pick uses at most 3 servers.
- If the check cannot run, for example when the server does not start, unchecked lines fill the
  set, and a `Warning:` line says how many and why.

Without the check, 7.4% of the lines sampled from `INFILE` (614 of 8348) and 12.7% of the lines
sampled from the disk (568 of 4489) did not parse. Of the lines the check keeps, about 0.1% still
hold a syntax error. See the limits below.

## Log output

An excerpt from a run with a count of 10 and a new set every 2 trials:

```
[20:52:58] [0 SAVED] [0 DUPS] AUTOMATIC_INTERLEAVE: The server under test parsed 89 of the 100 SQL lines the syntax check reached, in 2.96s
[20:52:58] [0 SAVED] [0 DUPS] AUTOMATIC_INTERLEAVE: Picked a new set of 10 SQL lines from .../mariadb-qa/pquery/main-ms-ps-md.sql in 10.33s. A new set is picked every 2 trials
[20:52:58] [0 SAVED] [0 DUPS] AUTOMATIC_INTERLEAVE: SQL 2/10: INSERT INTO t1  VALUES('a');
[20:52:59] [0 SAVED] [0 DUPS] INTERLEAVE: Interleaving SQL in the AUTOMATIC_INTERLEAVE set (10 lines) into the input file every 100th line
```

A line that crashed the check server, and a check server that did not start (MySQL 9.7.2):

```
AUTOMATIC_INTERLEAVE: In the syntax check, the server crashed on this SQL line, which is dropped: SELECT EXTRACTVALUE('','/a[number()]');
Warning: AUTOMATIC_INTERLEAVE: the server for the syntax check did not start within 60s (... [ERROR] [MY-012592] [InnoDB] Operating system error number 2 in a file operation.), so 5 SQL lines of this set are not syntax-checked
```

## Time per pick

Measured with a count of 10, on a 32-core box at a load average of about 174:

- From `INFILE`: 10 to 14 seconds, mostly to read a 452 MB `INFILE`.
- From the disk: 19 to 22 seconds, plus 2.5 to 40 seconds once per run to index the disk.
- The syntax check takes 2 to 3 seconds of this.

With the default interval, a pick happens once every 50 trials.

## Limits

### What the syntax check misses

- It uses the default `sql_mode`, and no `MYEXTRA`.
- It checks the syntax only. Lines that parse but always fail are kept, such as 1146 (missing
  table) or 1193 (unknown variable).
- About 0.1% of the kept lines still hold a syntax error, which an earlier parse-time error hides,
  for example in a truncated `CREATE PROCEDURE ... BEGIN`.
- Lines with `?` placeholders are kept. Lines with more than one statement are dropped.
- All lines of one check share one timeout, so on a very slow box a line that does not hang could
  be dropped as a hang.

### Other

- MySQL: the check server cannot start on an empty datadir, so every pick goes in unchecked, with
  a warning. Seen on MySQL 9.7.2.
- The syntax check was verified on MariaDB 10.6 to 13.2, Community and Enterprise, optimized and
  debug builds, and UBSAN+ASAN builds. It was not tested when running as root, in Galera or
  replication runs, or with VillageSQL.
- Security: each pick briefly starts a server with no authentication. It is reachable through its
  socket in `RUNDIR` for about a second. Trial servers are already reachable the same way, as root
  without a password.

## In the code

- `pquery-run.sh`:
  - the option defaults and their validation;
  - `auto_interleave_pick()`: the sample, the clean-up and the filters;
  - `auto_interleave_check()`: the syntax check;
  - `all_disk_sql_index()`: the disk index, shared with `USE_ALL_DISK_SQL`;
  - the interleave step in `assemble_trial_sql()`.
- `pquery-run*.conf`: the four option lines.
- `cheatsheet.md`: one row, in the "Applied to the per-trial SQL" table.
