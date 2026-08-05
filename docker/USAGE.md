# Usage guide

Every command below runs inside the box. Open a shell with
`./mariadb-qa --test /my/test --data /my/data` on the host.

The framework itself is documented in `~/mariadb-qa/cheatsheet.md`. Read that
file once: it lists every command, alias and directory of the framework. This
guide gives the order of the steps and the parts that matter in a container.

## The path from nothing to a filed bug

```
   check         sources        build          wire          test
 ┌──────────┐  ┌───────────┐  ┌─────────────┐ ┌───────────┐ ┌────────────┐
 │ qa-check │->│cloneall.sh│->│buildall_slow│>│startup_all│>│gomd, qa-run│
 │          │  │clone.sh   │  │buildall_san │ │qa-tools   │ │pquery-run  │
 └──────────┘  └───────────┘  └─────────────┘ └───────────┘ └────────────┘
                                                                  |
   report          reduce         analyse                         v
 ┌────────────┐  ┌────────────┐  ┌──────────────────┐    /data/<workdir>/
 │ b, m, tcp  │<-│ pg, sr     │<-│ pr, tt, i, vt    │<-  saved trials only
 │ jira       │  │ reducer<N> │  │ known bug filter │
 └────────────┘  └────────────┘  └──────────────────┘
```

`cb` does the sources box and the build box in one command.

## 1. Check the box

```bash
qa-check
```

It reports the compiler, `/dev/shm`, the core file settings, the mapped
directories and the framework state. Fix every `[fail]` line before you build.
The most common one is the host core pattern: see SETUP.md, section 1.

## 2. Get the MariaDB sources

One command clones the sources and builds them:

```bash
cb                    # Clone, then build optimised plus debug, per version
```

| Command | Builds |
|---|---|
| `cb` | Optimised plus debug |
| `cb-san` | UBSAN plus ASAN |
| `cb-msan` | MSAN, which needs `/MSAN_libs` |
| `cb-tsan` | TSAN |
| `cb-val` | Valgrind |

`cb` runs `cloneall.sh`, then `cloneall_es.sh` when `~/.git-credentials` holds
your GitHub token, then the build script. It takes hours and runs in a screen.
Step 3 explains the build part, and the version lists you edit first.

The rest of this section is the same work, step by step.

```bash
cd /test
vi cloneall.sh        # Enable the versions you want, one ./clone.sh line each
./cloneall.sh         # Clones every enabled version, in parallel
```

For a single version:

```bash
cd /test
./clone.sh 13.1       # A shallow clone with submodules, into /test/13.1
```

The tree names are plain version numbers, and `-es` marks an Enterprise branch,
for example `/test/12.3-es`.

## 3. Build the servers

Two build sets cover most work. Both start a screen and take hours.

```bash
cd /test
vi buildall_slow.sh       # Set BUILD_<version>=1 for the versions you cloned
./buildall_slow.sh        # Optimised plus debug build, per version

vi buildall_san_slow.sh   # The same version list
./buildall_san_slow.sh    # UBSAN plus ASAN build, per version
```

| Script | Result |
|---|---|
| `buildall_slow.sh` | `MD<date>-mariadb-<version>-linux-x86_64-opt` and `-dbg` |
| `buildall_san_slow.sh` | `UBASAN_MD<date>-...-opt` and `-dbg` |
| `buildall_msan_slow.sh` | `MSAN_MD<date>-...`, needs `/MSAN_libs` |
| `buildall_tsan_slow.sh` | `TSAN_MD<date>-...` |
| `buildall_val_slow.sh` | `VAL_MD<date>-...`, for Valgrind |

To build one source tree only, work from inside it and use an alias:

| Alias | Build |
|---|---|
| `ba` | Optimised plus debug |
| `bas` | UBSAN plus ASAN |
| `bam` / `bat` / `bav` | MSAN / TSAN / Valgrind |
| `bo` / `bd` | Optimised only / debug only |

A finished build is a *basedir*: a self-contained directory with its own
binaries, socket and port. Basedirs run side by side without interfering.

```bash
cd /test; ./gendirs.sh          # The plain builds
./gendirs.sh san                # The UBSAN plus ASAN builds
./gendirs.sh ALLALL             # Every build
```

## 4. Wire the builds, then the tools

```bash
cd /test
./startup_all         # Bakes the runtime scripts into every basedir
qa-tools              # Builds the generator against the newest -opt basedir
```

`startup_all` gives every basedir its own `start`, `stop`, `kill`, `wipe`, `cl`,
`test`, `all`, `all_no_cl`, `mtra` and more. Run it again after any build, and
after you move or rename a basedir, because those scripts hold absolute paths.
For a single basedir, run `st` inside it.

`qa-tools` rebuilds the testcase reducer and the two testing SQL generators. The
framework ships all three ready to run, so this step is about following the
newest source, not about getting started. The `generatorcpp` generator links
against a built basedir, which is why it waits for step 3. It is one source file
of 22 MB, so its build is heavy: 10 to 15 GB of memory, and the link step is
killed when a busy box runs out. Build it when nothing else large is running.

## 5. Work with one server

```bash
cd /test/MD220726-mariadb-13.1.0-linux-x86_64-dbg

./anc                 # Kill, wipe, start: a fresh empty server. The usual call
./all                 # The same, and it opens a client as well. Alias: a
vi in.sql             # The SQL you want to run. Alias: in
./test                # Feed in.sql to the client, output to mysql.out
./cl                  # Open a client
./kill                # Kill the server at once
./stop                # Clean shutdown
tail log/master.err   # The server error log. Alias: tl
m                     # The version banner for a bug report
```

Run `./anc` before every replay. A testcase that needs a fresh data directory is
the normal case, and `./test` on a used data directory proves nothing.

To loop a testcase until it crashes: `mu`, or `mul` for a shutdown problem, or
`mup` to drive it through pquery.

### MTR: use mtra on a sanitizer build

```bash
cd /test/<basedir>/mariadb-test
./mtr main.mytest        # A plain build
./mtra main.mytest       # A UBSAN, ASAN, TSAN or MSAN build
```

`mtra` is `mtr` with the sanitizer suppression filters of the framework applied
(`UBSAN.filter`, `ASAN.filter`, `TSAN.filter`), and with a smaller core file
setting. On a sanitizer build, plain `mtr` fails on warnings that are already
known, so `mtra` is the correct call there. On a plain build `mtra` works as
well, and adds nothing that gets in the way.

Put a new test in `mariadb-test/main/` and run it in place.

## 6. Run testing SQL

`pquery-run.sh` is the test driver. It starts a server, sends SQL to it with the
`pquery` client, watches for a crash, an assertion or a sanitizer report, gives
each failure a UniqueID, drops the failures that are already known, and saves the
rest as a trial in `/data/<workdir>/<trial>`.

Start runs with `gomd`, never by hand:

```bash
vi ~/gomd             # Set BASEDIR, CONF, RUNSOPT and RUNSDBG
gomd                  # Starts one pr<N> screen per run, plus a ge<N> handler
vr                    # Add the MON[N]=... lines that gomd prints
```

`qa-run` does the same in one line, and with no argument it shows the current
settings and the builds you can point at:

```bash
qa-run                                            # Show settings and builds
qa-run MD030826-mariadb-13.1.0-linux-x86_64-opt pquery-run-MD.conf 1 1
```

| Variable in `~/gomd` | Meaning |
|---|---|
| `BASEDIR` | The build to test. Either the `-opt` or the `-dbg` name works, the script computes the other |
| `CONF` | Which `pquery-run-*.conf` to use |
| `RUNSOPT` | Number of parallel runs against the optimised build |
| `RUNSDBG` | Number of parallel runs against the debug build |

One run takes about 0.4 to 0.8 GB of `/dev/shm`. Start with `RUNSOPT=1` and
`RUNSDBG=1`, watch the memory, then raise them.

### The configuration files

The configurations are `~/mariadb-qa/pquery-run-*.conf`, one per target. There
are about 40. `pquery-run.conf` is the base. The settings that matter most:

| Setting | Controls |
|---|---|
| `BASEDIR` | The server to test |
| `INFILE` | The SQL input file |
| `THREADS` | Client threads per trial. 1 reduces easily, more finds more races |
| `TRIALS` | How many trials to run |
| `MYEXTRA` / `MYINIT` | Extra server options, at runtime / also at data directory init |
| `MYSAFE` | Options the framework always adds, to cap memory use |
| `ADD_RANDOM_OPTIONS` | Add random server options per trial |
| `USE_GENERATOR` / `USE_REVGEN` / `USE_INFILE` / `USE_ALL_DISK_SQL` | Which SQL sources to use, see the next table |
| `ENABLE_ENCRYPTION` | Run with the file key management plugin |

### Where the SQL comes from

Turn on any set of the four sources. Each one contributes lines to one SQL file per trial, and that
file is shuffled before the trial runs, so the SQL of each source is spread over the whole file.

| Source | What it is | Turn it on with |
|---|---|---|
| `generatorcpp/generator` | SQL built from hand written templates | `USE_GENERATOR=1`, `QUERIES_PER_GENERATOR_RUN` |
| `revgen/revgen` | SQL built by walking the server yacc grammar, so it follows the version under test | `USE_REVGEN=1`, `QUERIES_PER_REVGEN_RUN` |
| `INFILE` | A fixed SQL file. The default is every distribution test suite turned into SQL | `USE_INFILE=1` |
| all SQL on the disk | A random sample of every `*.sql` file found | `USE_ALL_DISK_SQL=1`, `QUERIES_PER_ALL_DISK_RUN` |

The generator and revgen run every trial. The all-disk source collects a new pool every
`ALL_DISK_SQL_NEW_QUERIES_EVERY_X_TRIALS` trials, from a file list indexed once per run.

The share each source gets is simply its line count: `QUERIES_PER_GENERATOR_RUN`,
`QUERIES_PER_REVGEN_RUN`, `QUERIES_PER_ALL_DISK_RUN`, and the length of the `INFILE`.
`PQUERY_MAX_SQL_LINES` (5141189, the pquery maximum) caps the per-trial SQL, cutting from the
end, and the sources are joined in the order generator, revgen, `INFILE`, all-disk, so the last
source in use loses lines first. The file lands in `TRIAL_SQL_DIR`.

`REVGEN_YACC` picks the grammar that revgen walks.

The repository also holds a separate grammar based fuzzer. It is not part of this
flow. See `~/mariadb-qa/fuzzer/README`.

## 7. See what happened

```bash
pr                    # Every UniqueID of this workdir, how often, which trials
prg <text>            # Search that output
r                     # The same for every workdir in /data/results.list
i <trial>             # Details of one trial
vt <trial>            # That trial error log
t                     # The UniqueID here
tt                    # The UniqueID, the known bug lookup and ready made JIRA links
stack                 # A stack trace from the core
scanerr               # Scan every error log against the framework patterns
cur                   # The workdirs that run now
```

A UniqueID looks like `<signal or assertion>|<frame1>|<frame2>|<frame3>|<frame4>`.
It is how the framework tells one bug from another.

Run `tt` on a new crash before any cleanup. A crash without a captured UniqueID
is a lost bug.

### Known bugs

A trial is kept only when it matches a real problem and is not already known.

| File | Purpose | Alias |
|---|---|---|
| `known_bugs.strings` | UniqueIDs already reported | `kb` to edit, `kbs` to search |
| `known_bugs.strings.SAN` | The same for sanitizer reports | `kba`, `kbsa` |
| `REGEX_ERRORS_SCAN` | Error log lines that count as a problem | `rf` |
| `REGEX_ERRORS_FILTER` | Lines to ignore | `rfi` |
| `UBSAN.filter`, `ASAN.filter` | Sanitizer suppressions, also used by `mtra` | `ubf`, `asf` |

## 8. Reduce the testcase

```bash
pg                    # Reducer orchestrator for this workdir. The usual call
sr <trial>            # One reducer, in screen s<trial>
v <trial>             # Edit reducer<trial>.sh
o <trial>             # Show the reduced testcase
my                    # The reduced testcases of this workdir
cto                   # What still needs reducing, across all workdirs
```

`MODE` in `reducer<N>.sh` sets what counts as a reproduction:

| MODE | Target |
|---|---|
| 0 | A hang or a timeout |
| 2 | Text in the client output |
| 3 | Text in the server error log, the usual one |
| 4 | Any crash |
| 5 | An MTR testcase, or a text seen a set number of times |
| 11 | A dump or binary log round trip mismatch |

Aim for three or four lines. If a reducer sticks at about five lines, press
Ctrl+C three times and run `depge <trial>`, then let it run again.

## 9. Report the bug

```bash
cd /test/<basedir>
cp /data/<workdir>/<trial>/<testcase>_out in.sql
tcp in.sql            # Tidy the testcase up
./anc; ./test         # Prove it still reproduces
b                     # Full bug report for in.sql, over every build. 10 to 30 minutes
bs                    # The same against the UBSAN plus ASAN builds
m                     # The version banner
as / asm / asn        # UniqueIDs per version after b: all / merged / new
jira                  # File the ticket on jira.mariadb.org
```

Reproduce on a Community and on an Enterprise build before you report.

`jira` needs your own personal access token for jira.mariadb.org. Nothing in the
image holds a credential.

## 10. Screens

Every long job runs in a screen.

| Prefix | Owner |
|---|---|
| `pr<N>` | A test run |
| `ge<N>` | The reducer handler of one workdir |
| `s<N>` | A reducer for trial N |
| `crc<N>` | A crash recovery handler |

```bash
s <name>              # Reattach, or list the screens
sg <text>             # List the screens that match
sc                    # Am I inside a screen
```

A screen survives the exit of your shell, so a run keeps going after you close
the terminal. It does not survive a box restart.

## 11. Update the box

```bash
qa-update             # Pull mariadb-qa, run linkit, rebuild any changed tool
qa-upgrade            # Rebuild clang from source, and the MSAN libraries
qa-upgrade clang      # One part only. Also: qa-upgrade msan
```

`qa-update` is the everyday command. Run it when you want the newest framework,
or after a colleague lands a change. `linkit` is safe to run again at any time,
and it also runs at every box start.

`qa-upgrade` is the heavy one. The clang part takes about half an hour and uses
`/test` for its build, which needs 18 GB of free space there. The MSAN part
takes an hour or more, because every helper binary of those libraries runs under
MSAN while they build. Use it when a newer compiler
matters, or when the MSAN libraries have to follow a newer Ubuntu package set.

Build a new image only when the toolchain or the package set has to move. See
SETUP.md, section 5.

## 12. Clean up

```bash
dt <trial>            # Delete one trial, with its logs and its core file
ca                    # Sweep every workdir, dropping trials that match known bugs
kill_reducers         # Stop every reducer screen
kill_runs             # Stop every test run
ka2                   # Kill the server processes of this user
```

`dt` and `ka` do not ask twice. `ka` kills every server, every screen and wipes
`/dev/shm`, so use it only when you want the box empty.

## 13. Reference material

| Read | For |
|---|---|
| `~/mariadb-qa/cheatsheet.md` | Every command, alias and directory of the framework |
| `~/mariadb-qa/README.md` | What the framework is |
| `~/mariadb-qa/PQUERY-HOWTO` | Background reading, talks and blog posts |
| `~/mariadb-qa/skills/README.md` | The Claude Code skills of the framework |
| `~/mariadb-qa/fuzzer/README` | The separate grammar based fuzzer |
| `qa-guide setup` | Host settings, image build, registry |
| `qa-guide readme` | What the box is, and every command of it |

`alias <name>` shows what a shortcut runs. `ls -la ~/<name>` shows where a helper
points.

## 14. Claude Code in the box

The image holds the `claude` command. Sign in once with `claude`, and keep the
sign in between boxes by starting the box with
`--claude-home ~/.mariadb-qa-box-claude`.

`linkit` wires the framework material into `~/.claude`:

| Item | Effect |
|---|---|
| `~/.claude/skills/*` | Links to `~/mariadb-qa/skills/*`, so Claude Code loads a skill when a task matches it |
| `cheatsheet.md` | Added as an include to `~/.claude/global-memory/MEMORY.md`, so the framework commands are in context |
| Status line | `claude_statusline.py` is registered when no status line is set yet |

Your own memories are personal and are not in the image. Add them under
`~/.claude/` and map that directory to keep them.

## 15. Differences from a QA server

| Item | In the box |
|---|---|
| Kernel settings | Come from the host. `qa-check` reports them |
| Core files | Written by the host kernel, following the host core pattern |
| `rr` | Needs `--privileged`, and a host CPU that reports a performance monitoring unit |
| MSAN | The instrumented libraries are not in the image. Build them once with `qa-upgrade msan`, and map a host directory with `--msan` to keep them |
| `/dev/shm` | Sized by `--shm`, not by `/etc/fstab` |
| systemd | Not present. Nothing runs as a service |
| Oracle helper (`ora`, `oc`) | Not available. It starts a container of its own |
| Screens | Lost when the box stops |
