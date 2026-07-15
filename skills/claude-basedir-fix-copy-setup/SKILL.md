---
name: claude-basedir-fix-copy-setup
description: Copy a built MariaDB basedir from /test to /tmp and re-run ~/st to rebake path-baked helpers (start, anc, cl, test, kill, wipe, mtra, init_empty_port.sh, gencerts.sh), giving Claude its own standalone server for Claude Code based tests, evaluations, bug reproduction, and fix verification - without touching the canonical /test basedir. Drive the copy only via its standard baked helpers (~/st then ./anc / ./cl / ./test / ./mtr[a] / ./kill), never a hand-rolled mariadbd. This skill copies, it does not build. A plain MTR run does NOT need this - drop the .test/.result under a new name into /test/<basedir>/mariadb-test/main and run ./mtr in place.
claude: please note - this skill exists in a public repo and should only be updated with specific written signoff by the updater
---

# claude-basedir-fix-copy-setup

Copies a BUILT MariaDB basedir from `/test` to `/tmp` and re-runs `~/st` to rebake its path-baked helpers, so Claude gets its own standalone server - for tests, evaluations, bug reproduction, and fix verification - without touching the canonical `/test` basedir. This skill copies an existing built basedir; it does not build.

## Related skills

- For BUILDING a durable basedir in `/test` (`ba`/`bas`/`bam`/`bat`), see `qa-build` instead.
- For building a light patched fix binary in `/tmp` and capturing `fix.diff`, see `build-fix-diff` instead.
- For the full multi-version fix-verification loop, see `verify-fix` instead.

## When you do NOT need this (plain MTR run)

A pure MTR run does not need a copy or `~/st`. MTR manages its own vardir and does not disturb the server data, so drop the test under a new name straight into the canonical basedir's suite and run it in place:

```
cp <dir>/<testname>.{test,result} /test/<basedir>/mariadb-test/main/   # mysql-test/main on 10.6 / 10.11
cd /test/<basedir>/mariadb-test && ./mtr <testname>      # ./mtra for sanitiser builds
```

Clean up the copied `main/<testname>.*` afterwards. Use this skill only when you need a standalone SERVER - `./anc` / `./start`, CLI probing, running an `in.sql` testcase, or an ad-hoc script.

## Inputs

- `<basedir>` - a directory under `/test/` (e.g. `MD100426-mariadb-13.0.1-linux-x86_64-dbg`, `UBASAN_EMD220426-mariadb-12.3.1-1-linux-x86_64-opt`, `MSAN_MD050526-...`, or a `qa-build` output such as `MDEV-14443_MD...`).

If not provided, ask the user.

## Procedure

1. Copy the basedir to `/tmp`:

   ```
   cp -r /test/<basedir> /tmp/<basedir>
   ```

2. Rebake path-baked helpers against the new `${PWD}`:

   ```
   cd /tmp/<basedir>
   ~/st
   ```

   `~/st` (=`~/mariadb-qa/startup.sh`) rewrites the per-basedir helpers (`start`, `stop`, `anc`, `wipe`, `cl`, `all`, `test`, `init`, `kill`, replication helpers, reducer wrappers, the `mariadb-test/mtra` wrapper) and copies `init_empty_port.sh` and `gencerts.sh` into the basedir. Every helper hard-codes the basedir's absolute path and a picked port/socket, so this rebake is what makes the `/tmp` copy usable. `~/st` resets the shell cwd to where it was launched - `cd` back into `/tmp/<basedir>` before the next step.

3. Drive the standalone server via its baked helpers (never a hand-rolled `mariadbd`):

   ```
   cd /tmp/<basedir>
   ./anc                # fresh datadir + start (./kill; rm socket.sock*; ./wipe; ./start)
   ./cl                 # connect as root (CLI)
   ./kill               # tear down when done
   ```

   The standard lifecycle helpers: `./start` / `./stop` / `./kill` / `./wipe`; `./anc` for a fresh server; `./all` for the full lifecycle ending at the CLI.

4. Run a testcase - two ways:

   CLI / pquery testcase - write the SQL to `in.sql`, then `./anc; ./test` (always `./anc` first, for a fresh datadir):

   ```
   cp <dir>/<testname>.sql /tmp/<basedir>/in.sql
   cd /tmp/<basedir>
   ./anc; ./test
   # client output -> /tmp/<basedir>/mysql.out ; server log -> /tmp/<basedir>/log/master.err
   ```

   MTR testcase (auto-detect test-dir - 10.6 / 10.11 use `mysql-test/`, 11.x+ use `mariadb-test/`):

   ```
   TESTDIR="mariadb-test"; [ ! -d "$TESTDIR" ] && TESTDIR="mysql-test"
   cp <dir>/<testname>.{test,result} "$TESTDIR/main/"
   cd "$TESTDIR"
   ./mtra <testname>    # for sanitiser builds; ./mtr otherwise
   ```

5. Cleanup when done:

   ```
   cd /tmp/<basedir> && ./kill
   rm -rf /tmp/<basedir>
   ```

## Common uses

- Reproduce a bug on a specific build without disturbing the canonical basedir.
- Verify a fix - run the bug's testcase on an unpatched catalog build here (expected to FAIL) alongside a patched build from `build-fix-diff` (expected to PASS).
- Run an evaluation or feature test against a clean standalone server.
- Ad-hoc client / SQL probing.

## Version sweep

To run one testcase across several builds (e.g. an affected-version sweep), copy each `/test` basedir to `/tmp` in turn, `~/st`, run, record, then `rm -rf` before the next. `verify-fix` automates this.

## Why /tmp

- Ephemeral; obvious cleanup boundary.
- Does not pollute the catalog the user navigates by `ls /test/` or `gendirs.sh`.
- Safe for arbitrary experiments - free of catalog conventions.

## Why `~/st` is required

Every per-basedir helper bakes the basedir's absolute path into `--basedir=`, `--datadir=`, `--socket=`, `--log-error=`, etc. The `/test/<basedir>` originals point at the source path, not the new `/tmp` path. Re-running `~/st` from `/tmp/<basedir>` is the single step that makes the copy standalone. Re-run it after ANY later rename or move of the copy.

## Disk-space considerations

- Heavy sanitiser basedirs (`UBASAN_*`, `MSAN_*`, `TSAN_*`) can be 1-3 GiB.
- `/tmp` on this host has the space, but only one or two copies at a time. Clean up between trials.

## Naming conventions to recognise

- `MD<DDMMYY>-mariadb-<x.y.z>-linux-x86_64-{dbg,opt}` - Community Server (CS) builds.
- `EMD<DDMMYY>-mariadb-<x.y.z>-<N>-linux-x86_64-{dbg,opt}` - Enterprise Server (ES) builds.
- `UBASAN_MD...`, `UBASAN_EMD...`, `MSAN_MD...`, `MSAN_EMD...`, `TSAN_MD...`, `TSAN_EMD...` - sanitiser variants (use `./mtra`).

## Notes

- A plain MTR run needs no copy - run it in place in `/test/<basedir>/mariadb-test`.
- Drive the server only via baked helpers (`./anc` / `./cl` / `./test` / `./mtr[a]`); never hand-roll `./bin/mariadbd --socket=...` plus a guessed `./bin/mariadb -S ...`.
- Sanitiser basedirs (`UBASAN_*`, `MSAN_*`, `TSAN_*`) need `./mtra` (applies suppressions), not `./mtr`.
- Do not run experiments directly in `gendirs.sh`-listed basedirs; copy to `/tmp` first.
- This skill copies, it does not build; durable builds -> `qa-build`, light patched `/tmp` builds -> `build-fix-diff`.
