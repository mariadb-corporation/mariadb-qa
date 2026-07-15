---
name: mtr_testcase
description: Craft and verify a MariaDB MTR (.test) testcase from a CLI/pquery testcase - engine guards (InnoDB/partition/RocksDB/Spider), Mroonga/replication setup, default-engine differences, --error coverage, server options, reverse-gating, and run-in-place verification. Use any time a crash/assert/SAN repro must run under mariadb-test-run.pl, including when building the MTR block of a bug report.
claude: please note - this skill exists in a public repo and should only be updated with specific written signoff by the updater
---

# mtr_testcase

Turn a CLI/pquery testcase into a `.test` that reproduces the SAME failure under `mariadb-test-run.pl`, then verify it in place. The `/test/<basedir>/mariadb-test` trees are STANDARD MariaDB test trees - use the standard mechanisms below, do not invent `-master.opt` workarounds.

## Default engine - the #1 gotcha

The standalone CLI defaults to **InnoDB**; the MTR **main** suite does NOT (it runs with a leaner default and InnoDB/partition gated). So a CLI testcase that "just works" can do nothing under MTR.

- **Test whether the engine is load-bearing first.** Re-run the repro on the default engine (drop any explicit `ENGINE=InnoDB`). If it still fires, InnoDB is NOT required - keep the table `ENGINE`-less and the `.test` needs NO `have_innodb.inc`, and InnoDB is NOT a component on the ticket.
- If the bug is genuinely InnoDB-specific, keep `ENGINE=InnoDB` AND add `--source include/have_innodb.inc` AND set `Storage Engine - InnoDB` as a component.
- `ENGINE=` must precede a `PARTITION BY` clause (`... ENGINE=InnoDB WITH SYSTEM VERSIONING PARTITION BY ...`); `ENGINE` after `PARTITION BY` is `ER_PARSE_ERROR`.

## Engine / feature guards (one per line, at the top)

Require a guard ONLY when that engine/feature is load-bearing; reflect a load-bearing engine in the ticket components.

| Need | Guard | Notes |
|---|---|---|
| InnoDB | `--source include/have_innodb.inc` | see default-engine note above |
| Partitioning | `--source include/have_partition.inc` | main suite skips partition by default |
| RocksDB | `--source include/have_rocksdb.inc` | also self-`INSTALL SONAME 'ha_rocksdb'` if the testcase installs it |
| Spider | `--source include/have_spider.inc` | Spider needs its own init; consider the `spider` suite |
| Mroonga | **none exists** | there is NO `have_mroonga.inc`; just use `INSTALL SONAME 'ha_mroonga';` in the testcase (the `.so` is present in QA builds; the bug needs it installed) |
| log-bin / binlog | `--source include/have_log_bin.inc` | the STANDARD way to get a binlog - MTR starts the server with `--log-bin` for you. Do NOT use a `-master.opt --log-bin`. A `# mysqld options required for replay: --log_bin` header maps to this include |
| sequences | `--source include/have_sequence.inc` | |
| binlog format | `--source include/have_binlog_format_row.inc` (or `_statement` / `_mixed`) | when the bug is format-specific |
| other server opts | inline `SET` (dynamic vars), else `--mysqld=--<opt>` / `$restart_parameters` | prefer a `have_*.inc` include when one exists |

NEVER add `--source include/not_embedded.inc`. It is not needed - drop it always (even for `INSTALL SONAME` / plugin / connect-using-auth-plugin tests).

If a `have_log_bin.inc` testcase does NOT reproduce, add (these reset the gtid table that otherwise interferes):

```
ALTER TABLE mysql.gtid_slave_pos ENGINE=InnoDB;
ALTER TABLE mysql.gtid_slave_pos DROP PRIMARY KEY;
```

WSREP/Galera: the galera suites auto-detect the provider; `common.pm` searches `$::bindir/lib/` first. Use the `galera`/`wsrep` suites, not main.

## Replication

A replication bug (trial shows `MASTER_EXTRA`/`SLAVE_EXTRA`/`REPL_EXTRA`, or needs `--log-bin` + a replica) uses `--source include/master-slave.inc` (or `rpl_init.inc`) and runs `--connection master` / `--connection slave`. For a binlog-only bug (no replica needed) a single server with `--log-bin` via `-master.opt` suffices.

## sql_mode and expected errors

- `--sql_mode=` header -> inline `SET sql_mode='';` (tcp converts it). Strict mode rejects loose data (`'' `/`'a'` into INT); set `sql_mode=''` when the reduced testcase relies on it.
- Gate each statement that LEGITIMATELY errors with a SPECIFIC `--error <ER_NAME|errno>` on the line ABOVE it (e.g. `--error ER_PARSE_ERROR`), so MTR does not abort before the triggering statement. A statement that only WARNS (very common under `SET sql_mode=''`) needs NO gate at all - do not gate warnings. **Do NOT use `--disable_abort_on_error`** - it is a blunt instrument that hides which statements error and reads as sloppy; determine each statement's actual result during reduction (run it, read the `--error`/warning) and gate precisely. (`--disable_abort_on_error` only as an absolute last resort for a still-noisy reduced testcase, and then note why.) Each `--error <X>` also documents the expected error for the dev.
- `--write_file` and other directives must be hoisted ABOVE any `if(){}` - a `--write_file` inside a false `if` leaks its body as SQL (`ER_PARSE_ERROR`).

## Form

- ONE SQL statement per line (mariadb-test-run.pl, pquery, and reducer all assume this).
- For a CRASH/assert/SAN bug, the test is a REVERSE GATE: it FAILS (server dies / Lost connection) while the bug is live and PASSES once fixed. Do NOT `--record` buggy output; do NOT add a `.result` that bakes in the crash.
- Functional (non-crash) feature pre-tests use the plain `test` db and UPPERCASE SQL.
- CLI vs MTR: if the exact SQL runs in both, note "CLI/MTR compatible" (one block). If MTR needs guards/directives the CLI lacks, present two blocks (CLI Testcase / MTR Testcase).

## Scaffold templates

Start from these and uncomment only what the repro needs (each `--source` / `SET` is load-bearing-or-cut; verify the UniqueID after enabling/disabling each).

**Generic crash/assert** - candidate guards/prep to try:

```
#--source include/have_innodb.inc
#--source include/have_sequence.inc
#--source include/have_binlog_format_row.inc
#--source include/have_log_bin.inc
#--source include/have_partition.inc
#ALTER TABLE mysql.gtid_slave_pos ENGINE=InnoDB;   # use when have_log_bin is on and the testcase does not reproduce
#ALTER TABLE mysql.gtid_slave_pos DROP PRIMARY KEY;
#SET sql_mode='';
<testcase_code>
```

**Replication** (master-slave) - the standard rpl harness:

```
#--source include/have_binlog_format_row.inc
#--source include/have_binlog_format_statement.inc
#--source include/have_binlog_format_mixed.inc
#--source include/have_log_bin.inc
#--source include/have_sequence.inc
#--source include/have_partition.inc
--source include/have_innodb.inc
--source include/master-slave.inc
ALTER TABLE mysql.gtid_slave_pos ENGINE=InnoDB;
ALTER TABLE mysql.gtid_slave_pos DROP PRIMARY KEY;
SET GLOBAL binlog_direct_non_transactional_updates=OFF;
SET default_storage_engine=InnoDB;
--connection slave
STOP SLAVE;
#SET GLOBAL slave_run_triggers_for_rbr=LOGGING;
#SET GLOBAL slave_parallel_mode=aggressive;
#SET GLOBAL gtid_strict_mode=1;
SET GLOBAL slave_parallel_threads=10;
START SLAVE;
SELECT SLEEP(2);
--connection master
#SET GLOBAL gtid_strict_mode=1;
#SET GLOBAL log_bin_trust_function_creators=1;
#SET sql_mode='';
<testcase_code>
--sync_slave_with_master
DROP TABLE t1,t2;
--source include/rpl_end.inc
```

## Verify in place (mandatory)

Drop the test into the reproducing basedir's `mariadb-test/main/` (or `mysql-test/main/` on older versions where that is the binary test dir) and run it THERE - no /tmp copy. ALWAYS place it in the MAIN suite under a distinct claude-owned name, e.g. `main/test_claude.test`. Never call it `test.test` (that clobbers the tester's own scratch) and never leave it only under `suite/rpl/` or another suite the tester will not run - the tester verifies with `./mtr test_claude` in the main suite, so a test filed elsewhere can pass for you yet never be run by them (a master-slave.inc test runs fine from the main suite).

```bash
cd /test/<basedir>/mariadb-test      # or /test/<basedir>/mysql-test on older versions
cp <name>.test main/test_claude.test
./mtr test_claude        # plain dbg/opt build
./mtra test_claude       # SAN build (applies SAN suppressions; use for ASAN/UBSAN/MSAN repros)
```

NEVER put a backtick in a test you output. The cause is SOLELY the Claude Code TUI: it renders a backtick span as colored inline code and does not display the literal backtick characters, so they are absent from what the TUI shows and therefore from the test the tester ends up with. The test then has a let-capture line with no backticks, so the query is not executed, the variable holds a truthy literal string, every if (!$var) gate is skipped, and the test PASSES while proving nothing. This has silently defeated a reverse-gate more than once. Never use a backtick-captured let. Capture values with query_get_value(SELECT ..., <col_or_alias>, 1), or gate functionally with --error <ER_NAME> on the statement itself. Grep the file for a backtick and remove any before shipping.

Confirm it reproduces (server crash / `Lost connection` for a crash bug; the expected `--error` for an error bug) and that `~/tt` reports the SAME UniqueID as the original. Ship the EXACT file you verified (verify-as-shipped) and clean the scratch (`main/<name>.test`, `<name>-master.opt`, `var/log/main.<name>`) when done.

## Common failure signatures and fixes

- `running with the --skip-partition option` -> add `have_partition.inc`.
- `Unknown storage engine 'InnoDB'` (only with a `-master.opt`) -> a bare `-master.opt` restart can drop the InnoDB plugin in some QA configs; prefer the `have_innodb.inc` guard over `-master.opt --partition`.
- `Could not open 'include/have_X.inc'` -> that include does not exist (e.g. Mroonga); drop the guard line and load the engine via `INSTALL SONAME`.
- Test "passes" with `--disable_abort_on_error` but should crash -> a required statement silently errored (wrong engine, missing table, strict sql_mode); check the per-statement output.

## Related

- `~/mariadb-qa/skills/_shared/jira_markup.md` - Jira wiki markup for the CLI/MTR blocks when they go into a bug report.
- `claude-basedir-fix-copy-setup` - a plain MTR verification runs in place in `/test/<basedir>/mariadb-test` and needs no copy; use that skill only when a standalone server is required.
