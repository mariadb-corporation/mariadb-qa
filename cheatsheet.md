# MariaDB QA Framework Cheatsheet

Installed by `~/mariadb-qa/linkit`. Run each command from the directory its section names.

## The pipeline

```
  build a server    test it            keep the failures   minimise        report
 ┌─────────────┐   ┌───────────────┐   ┌────────────────┐  ┌────────────┐  ┌──────────┐
 │ ba/bas/.../ │──>│ gomd          │──>│ /data/<workdir>│─>│ pg / sr    │─>│ tt + b   │
 │ build_mdpsms│   │ pquery-run.sh │   │   <trial>/     │  │ reducer<N> │  │ HIRA     │
 └─────────────┘   └───────────────┘   └────────────────┘  └────────────┘  └──────────┘
  /test/<basedir>   /dev/shm/<wkdir>    saved trials only   *_out testcase  MDEV / MENT

 Every failure gets a UniqueID (t / tt). Known ones are dropped automatically.
 New ones are kept for reduction.
```

## Where things live

```
/test/                      All server builds (basedirs) and the build helpers
  <version>/                  Source tree (e.g. /test/13.1)
  MD220726-mariadb-13.1.0-linux-x86_64-opt/    A built basedir, ready to run
  d1 o1 u1 uo1              What the d / o / ds / os aliases source to jump to the newest
                              dbg / opt / UBASAN dbg / UBASAN opt build
  gendirs.sh                Lists the basedirs b and mb test against, per build flavour
  REGEX_EXCLUDE             Builds to leave out of that list
  TESTCASES/                Archived reduced testcases
  git-bisect/               Bisect helpers and full-history clones
  actual_release_build/     Official release tarballs, for real-release comparison

/data/                      All test run workdirs and their reducers
  <6-digit workdir>/          One pquery-run run
    <trial>/                    A saved failing trial (data, logs, SQL, core)
    reducer<N>.sh               Per-trial reducer, auto-generated
    pquery-run.log              The run log
  results.list              The workdirs you are tracking (MON[1]=... lines)
  TARS/                     Build tarballs
  VARIOUS_BUILDS/           Basedirs retired from /test
  NEWBUGS/  NBUGS/          Automation bug deposit and verification

/dev/shm/<6-digit>/         Live run directory (tmpfs); trials execute here
/dev/shm/<10-digit>/        A reducer's working directory

~/mariadb-qa/               The framework itself (all scripts, filters, known-bug lists)
~/<name>                    Helper symlinks into the framework, made by linkit
```

## One-time setup

| Command | What it does |
|---|---|
| `~/mariadb-qa/setup_server.sh` | Box prep: core dumps, limits, kernel settings. Best run manually step-by-step |
| `li` | Run linkit: all `~/` helpers, the `/test` and `/data` links, the Claude Code skills, the alias block |
| `sb` | Re-source `~/.bashrc` after the alias list changed |
| `st` | In a basedir: bake its runtime scripts. Re-run after any move or rename |
| `g` `gsan` `gmsan` `gtsan` `gval` | List the basedirs `b` tests against, per flavour |

Trials run in tmpfs, so size `/dev/shm` to about 80% of RAM: 95 GB on a 128 GB box.

## Build a server

| Command | What it does |
|---|---|
| `cd /test; ./clone.sh 13.1` | Fetch one source tree. `cloneall.sh` fetches every current branch |
| `ba` | Optimised + debug build, in a screen |
| `bas` | Same, UBSAN+ASAN builds |
| `bam` / `bat` / `bav` | Same, MSAN / TSAN / Valgrind builds. MSAN needs clang-20 and `/MSAN_libs` |
| `bo` / `bd` | Optimised only / debug only |

Run from inside the source tree. Basedirs land in `/test`, tarballs in `/data/TARS`.

## Inside a basedir (`/test/<basedir>/`)

| Command | What it does |
|---|---|
| `a` | Full cycle: kill, wipe, start, open the client |
| `anc` | Same but no client. This is the "fresh server" call |
| `./test` | Feed `in.sql` into the client, output to `mysql.out` |
| `in` | Edit `in.sql` |
| `./start` `./stop` `./kill` `./wipe` `./init` `./cl` | Server lifecycle and client connect |
| `mu` / `mul` / `mup` | Loop `in.sql` until it crashes (plain / shutdown issues / via pquery) |
| `str` / `stopr` | Start / stop replication |
| `./gal` and `./gal_start` `./gal_stop` `./gal_wipe` `./gal_cl` | The same chain for a Galera cluster. Only on builds that ship a Galera plugin |
| `cd mariadb-test; ./mtra <test>` | MTR with the sanitizer suppression filters applied |
| `m` | Version banner for a bug report |
| `stack` | Stack trace from the core |
| `tl` / `vl` | Tail / edit the server error log |

## Run a test test

1. Edit `~/gomd`: set `BASEDIR`, pick a `CONF`, set `RUNSOPT` and `RUNSDBG`.
2. Run `gomd`. It starts one `pr<N>` screen per run plus a `ge<N>` reducer handler for each.
3. Copy the `MON[N]=...` lines it prints into `/data/results.list`.

Configs are `~/mariadb-qa/pquery-run-*.conf`, one per test target:

| Setting | Controls |
|---|---|
| `BASEDIR` | The server to test |
| `INFILE` | The SQL input file |
| `THREADS` | Client threads per trial. 1 is easiest to reduce, more finds more races |
| `TRIALS` | How many trials to run |
| `MYEXTRA` / `MYINIT` | Extra server options, at runtime / also at data directory init |
| `MYSAFE` | Options the framework always adds, to cap memory use |
| `ADD_RANDOM_OPTIONS` | Add random server options per trial |
| `USE_GENERATOR` / `USE_REVGEN` / `USE_INFILE` / `USE_ALL_DISK_SQL` | Which SQL sources to use, see below |
| `QUERY_CORRECTNESS_TESTING` | Compare results between two option sets instead of hunting crashes |
| `ENABLE_ENCRYPTION` | Run with the file-key-management plugin |

## Where the SQL comes from

Turn on any set of the four sources. Each one contributes lines to one SQL file per trial, and that
file is shuffled before the trial runs, so the SQL of each source is spread over the whole file.

| Source | What it is | Turn it on with |
|---|---|---|
| `generatorcpp/generator` | Random SQL built from hand-written templates | `USE_GENERATOR=1`, `QUERIES_PER_GENERATOR_RUN` |
| `revgen/revgen` | Random SQL built by walking the server's own yacc grammar | `USE_REVGEN=1`, `QUERIES_PER_REVGEN_RUN` |
| `INFILE` | A fixed SQL file. The default is every distribution's MTR suite converted to SQL | `USE_INFILE=1` |
| all SQL on the disk | A random sample of every `*.sql` file found | `USE_ALL_DISK_SQL=1`, `QUERIES_PER_ALL_DISK_RUN` |

The generator and revgen run every trial. The all-disk source is the slow one, so it collects a
new pool every `ALL_DISK_SQL_NEW_QUERIES_EVERY_X_TRIALS` trials; the file list it samples from is
indexed once per run. An `INFILE` larger than the line cap is read from a random offset each
trial, so a run covers the whole file over its trials.

The share each source gets is simply its line count: `QUERIES_PER_GENERATOR_RUN`,
`QUERIES_PER_REVGEN_RUN`, `QUERIES_PER_ALL_DISK_RUN`, and the length of the `INFILE`. So for 25%
generator, 25% revgen and 50% `INFILE`, set both query counts to half the `INFILE`'s line count.

`PQUERY_MAX_SQL_LINES` (5141189, the pquery maximum) caps the per-trial SQL. Lines are cut from
the end, and the sources are joined in the order generator, revgen, `INFILE`, all-disk, so the
last source in use loses lines first. The file lands in `TRIAL_SQL_DIR`.
`REVGEN_YACC` picks the grammar revgen walks, so it tracks the version under test. Beside it sits
`<version>_coldefs.txt`, the column definitions revgen builds its tables from; `yacc/harvest_coldefs.sh`
writes one per version from that version's own test suite.

| Applied to the per-trial SQL | What it does |
|---|---|
| `ADV_FILTER_SQL=1` | Removes any line matching `ADV_FILTER_LIST`, e.g. shutdown and kill |
| `INTERLEAVE` / `INTERLEAVE_SQL` / `INTERLEAVE_LINES` | Inserts your SQL every n lines |
| `STORAGE_ENGINE_SWAP` (+`_PERCENTAGE`) | Changes engine names |
| `SWAP_ALL_TABLE_NAMES_TO_T1` / `SWAP_CREATE_TABLE_NAMES_TO_T1` | Collapses table names to `t1` |

`FILTER_SQL=1` is the separate, lighter filter through `mariadb-qa/filter.sql`. It runs once per
trial, over all the sources together, after they are joined. The pass is split over up to 24 cores,
which keeps a 150,000 line mix at about 2.6 seconds.

## See what happened

| Command | What it does |
|---|---|
| `da` / `ct` / `cm` | Go to `/data` / `/test` / `~/mariadb-qa` |
| `j <workdir>` | Jump to `/data/<workdir>` |
| `pr` | Results for this workdir: every UniqueID, how often, which trials |
| `prg <text>` | Search the `pr` output |
| `r` | Results for every workdir in `results.list` |
| `res` / `ms` | All reduced testcases, biggest first, so the best ones sit at the bottom |
| `my` | Reduced testcases in this workdir, smallest first |
| `ii` | This workdir's configuration |
| `i <trial>` | Details of one trial |
| `vt <trial>` | Open that trial's error log |
| `cto` | What still needs reducing, across all workdirs |
| `vr` | Edit `/data/results.list` |

## Identify a failure

| Command | What it does |
|---|---|
| `t` | Print the UniqueID: the crash, assert or sanitizer signature |
| `tt` | Same, plus a known-bug lookup and ready-made JIRA search links |
| `sts` | UniqueID for a sanitizer failure only |
| `stack` | Stack trace from the core |
| `kbs <text>` / `kbsa <text>` | Search the known-bug lists (plain / sanitizer) |
| `kb` / `kba` | Edit those lists |
| `scanerr` | Scan every error log against the framework's error patterns |
| `ge <text>` | Search every basedir error log for a string |
| `scanall <text>` | Search known bugs plus every log under `/test` and `/data` |
| `fb` | Find every place a given UniqueID or error-log bug turned up |
| `ft` | Find a testcase for a bug already reduced |

A UniqueID looks like `<signal or assert>|<frame1>|<frame2>|<frame3>|<frame4>`.

## Filtering the noise

A trial is kept only when it matches a real problem and is not already known.

| File | Purpose |
|---|---|
| `known_bugs.strings` / `.SAN` | UniqueIDs already reported. Matching trials are dropped. Edit with `kb` / `kba` |
| `REGEX_ERRORS_SCAN` | Error-log lines that count as a problem. Edit with `rf` |
| `REGEX_ERRORS_FILTER` `REGEX_ERRORS_LASTLINE` | Lines to ignore. Edit with `rfi` / `rfil` |
| `UBSAN.filter` / `ASAN.filter` | Sanitizer suppressions, also used by `mtra`. Edit with `ubf` / `asf` |
| `/test/REGEX_EXCLUDE` | Builds `gendirs.sh` should skip. Edit with `reg` |

## Reduce a testcase

| Command | What it does |
|---|---|
| `pg` | Reducer orchestrator for this workdir. Creates and drives reducers on a loop |
| `pga` | Same, across every workdir |
| `sr <trial>` | Start one reducer, in screen `s<trial>` |
| `sru` | Start reducers for every trial in this workdir that has not been reduced |
| `srua` | Same, across every workdir in `results.list` |
| `mb <trial>` then `sbr <trial>` | Reduce against the plain build, to see if a feature branch caused it |
| `pge <trial>` | Refine further after a reducer finished |
| `depge <trial>` | Un-refine, to free a reducer stuck at about five lines |
| `v <trial>` | Edit `reducer<trial>.sh` |
| `o <trial>` | Show the reduced testcase |
| `check` / `count_reducers` | Sanity-check for duplicate reducers / count the running ones |
| `findr` | List the `/dev/shm` working directories of live reducers |
| `keep_trial_live <trial>` | Restart that reducer if its screen dies |

Output chain per generation: `<input>_out`, `_out_out`, `_out_out_out`. Aim for 3 or 4 lines.

`MODE` in `reducer<N>.sh` sets what counts as a reproduction:

| MODE | Target |
|---|---|
| 0 | Hang or timeout |
| 2 | Text in the client output |
| 3 | Text in the server error log (the usual one) |
| 4 | Any crash |
| 5 | MTR testcase, or a text seen a set number of times |
| 11 | Dump or binlog round-trip mismatch |

## File a bug

| Command | What it does |
|---|---|
| `b` | Full bug report for `in.sql` in this basedir. Takes 10 to 30 minutes |
| `bs` / `bm` / `bt` / `bv` / `br` | Same for UBSAN+ASAN / MSAN / TSAN / Valgrind / replication |
| `m` | Version banner to paste above each result |
| `as` / `asm` / `asn` | UniqueIDs per version after `b`: all / merged / new |
| `tcp <file>` | Tidy up a testcase before it goes in the report |
| `eb <number>` | Edit the stored SQL for MDEV-<number> or MENT-<number> |
| `jira` | File the ticket on jira.mariadb.org |

Reproduce on both Community and Enterprise before reporting.

## Find when a bug started

`/test/git-bisect/git-bisect.sh` builds and tests each bisect step. Edit these at the top:

| Setting | Value |
|---|---|
| `VERSION` | The branch, e.g. `12.3` |
| `FIRST_KNOWN_BAD_COMMIT` `LAST_KNOWN_GOOD_COMMIT` | The two endpoints |
| `TESTCASE` | `/test/in<N>.sql`. Numbered, because `/test/in.sql` gets clobbered |
| `UNIQUEID` | Compare against `t` output. Most precise. Pick one detection setting only |
| `TEXT` / `CLI_TEXT` | Match the server log / the client output instead |
| all three empty | Look for a core file instead |

Confirm the bad endpoint reproduces first. Narrow the range using the old builds in
`/data/TARS` and `/data/VARIOUS_BUILDS`.

## Screens

| Command | What it does |
|---|---|
| `s <name/pid>` | Reattach to a screen, or to a screen inside it by its PID. No name: list them in columns |
| `sn [name]` | Start a new screen and attach to it. No name given: named after the current directory, numbered |
| `sren <old> <new>` | Rename a screen. Old can be part of the name, or the PID |
| `sg <text>` | List screens matching a pattern |
| `sc` | Am I inside a screen, and in which window |

| Prefix | Owner |
|---|---|
| `pr<N>` | A pquery-run test run |
| `ge<N>` | The reducer handler for one workdir |
| `s<N>` | A reducer for trial N |
| `crc<N>` | A crash-recovery handler |

`/test/loop_screens` walks you through every reducer screen in turn, oldest first.

## Automation

| Command | What it does |
|---|---|
| `watchdog` | Start, stop or attach the monitoring and curation daemon |
| `wasabi` | Same for the build and FireWorks autorunner |
| `newbug` | Summaries of what the automation has deposited in `/data/NEWBUGS` |

## Clean up and stop

| Command | What it does |
|---|---|
| `dt <trial>` | Delete a trial. Removes the crash, the logs and the core outright |
| `ca` | Sweep every workdir and drop trials matching known bugs |
| `kill_reducers` / `kill_runs` | Stop all reducer screens / all test runs |
| `ka2` | Kill this user's server processes |
| `ka` | Kill everything: servers, screens, `/dev/shm`. Destructive, owner only |

## Naming

| Pattern | Meaning |
|---|---|
| `MD<DDMMYY>-` | Community Server build. Say "CS 13.1.0" when writing to developers |
| `EMD<DDMMYY>-` | Enterprise Server build. Say "ES 12.3.2-1" when writing to developers |
| `UBASAN_` | UBSAN plus ASAN build |
| `MSAN_` / `TSAN_` / `VAL_` | Memory / Thread sanitizer / Valgrind build |
| `MDEV-<n>_` / `MENT-<n>_` | Build of a feature or fix branch |
| `-opt` / `-dbg` | Optimised / debug |

## What is in a trial directory

| File | Holds |
|---|---|
| `data/` | The data directory as it was when the server died |
| `log/master.err` | Server error log |
| `pquery.log` | Client output |
| `<trial>.sql.failing` | The SQL that was running |
| `default.node.tld_thread-*.sql` | Per-thread SQL trace |
| `MYEXTRA` `MYINIT` `MYSAFE` | The exact server options this trial used |
| `MYBUG` | The UniqueID this trial matched |
| `core` | The crash dump, when there is one |
| `<epoch>_*` | A shareable bundle: start, run, gdb, how-to-use |
| `*_out` | The reduced testcase |

## Worth remembering

- `a` (or `anc`) before every testcase replay to get a fresh data dir/instance.
- Re-run `st` after moving or renaming a basedir. Every path is baked in.
- Use `./mtra` to run testcases on sanitizer builds, never plain `mtr`, to get filters
- `tt` or `pr` before anything else: get your UniqueID's. Also, `dt` and `ka` do not ask twice.
- `results.list` is read up to the first `return`. Older runs park below it.
- Unsure of an alias: `alias <name>` shows what it runs, `ls -la ~/<name>` where it points.
- `~/mariadb-qa/skills/README.md` lists the Claude Code skills & procedures which `linkit` installs.
