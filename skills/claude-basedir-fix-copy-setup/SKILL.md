---
name: claude-basedir-fix-copy-setup
description: Copy a MariaDB basedir from /test to /tmp and re-run ~/st to rebake path-baked helpers (start, anc, kill, mtra, init_empty_port.sh, gencerts.sh), enabling autonomous standalone-server runs without disturbing the canonical basedir. Use before running ./anc / ./start / ./test or launching ad-hoc standalone server experiments against any /test/<basedir>. A plain MTR run does NOT need this - drop the .test/.result under a new name into /test/<basedir>/mariadb-test/main and run ./mtr in place.
claude: please note - this skill exists in a public repo and should only be updated with specific written signoff by the updater
---

# claude-basedir-fix-copy-setup

Copies a binary MariaDB basedir to `/tmp` and regenerates path-baked helpers so the copy can be used as a fully standalone basedir.

## When you do NOT need this (plain MTR run)

A pure MTR run does not need the copy or `~/st`. MTR manages its own vardir and does not disturb the server data, so drop the test under a new name straight into the canonical basedir's suite and run it in place:

```
cp <dir>/<testname>.{test,result} /test/<basedir>/mariadb-test/main/   # mysql-test/main on 10.6 / 10.11
cd /test/<basedir>/mariadb-test && ./mtr <testname>      # ./mtra for sanitiser builds
```

Clean up the copied `main/<testname>.*` afterwards. Use this skill only when you need a standalone server - `./anc` / `./start`, ad-hoc client probing, or running an ad-hoc bash script.

## Inputs

- `<basedir>` - name of a directory under `/test/` (e.g. `MD100426-mariadb-13.0.1-linux-x86_64-dbg`, `UBASAN_EMD220426-mariadb-12.3.1-1-linux-x86_64-opt`, `MSAN_MD050526-...`, or a freshly built `<PREFIX>-mariadb-...` from the `qa-build` skill).

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

   `~/st` (=`~/mariadb-qa/startup.sh`) rewrites: `start`, `stop`, `anc`, `wipe`, `cl`, `all`, `init`, `kill`, replication helpers, reducer wrappers, sysbench helpers, the `mariadb-test/mtra` wrapper. It also copies `init_empty_port.sh` and `gencerts.sh` into the basedir. The shell cwd resets to where `~/st` was launched - `cd` back into `/tmp/<basedir>` before the next step.

3. Use as a normal basedir:

   ```
   cd /tmp/<basedir>
   ./anc                # fresh datadir + start (./kill; rm socket.sock*; ./wipe; ./start)
   # ... interact, run tests, etc.
   ./kill               # tear down when done
   ```

   For an MTR test (auto-detect test-dir name - 10.6 / 10.11 use `mysql-test/`, 11.x+ use `mariadb-test/`):

   ```
   TESTDIR="mariadb-test"; [ ! -d "$TESTDIR" ] && TESTDIR="mysql-test"
   cp <dir>/<testname>.{test,result} "$TESTDIR/main/"
   cd "$TESTDIR"
   ./mtra <testname>    # for sanitiser builds; ./mtr otherwise
   ```

4. Cleanup when done:

   ```
   rm -rf /tmp/<basedir>
   ```

## Why /tmp

- Ephemeral; obvious cleanup boundary.
- Does not pollute the catalog the user navigates by `ls /test/` or `gendirs.sh`.
- Safe for arbitrary experiments - free of framework conventions.

## Why `~/st` is required

Every per-basedir helper bakes the basedir's absolute path into `--basedir=`, `--datadir=`, `--socket=`, `--log-error=`, etc. The `/test/<basedir>` originals point at the source path, not the new `/tmp` path. Re-running `~/st` from `/tmp/<basedir>` is the single step that needs to happen at the new path.

## Disk-space considerations

- Heavy sanitiser basedirs (`UBASAN_*`, `MSAN_*`) can be 1-3 GiB.
- `/tmp` on this host has the space, but only one or two copies at a time. Clean up between trials.

## Naming conventions to recognise

- `MD<DDMMYY>-mariadb-<x.y.z>-linux-x86_64-{dbg,opt}` - Community Server (CS) builds.
- `EMD<DDMMYY>-mariadb-<x.y.z>-<N>-linux-x86_64-{dbg,opt}` - Enterprise Server (ES) builds.
- `UBASAN_MD...`, `UBASAN_EMD...`, `MSAN_MD...` - sanitiser variants (use `./mtra`).

## When to also use `qa-build`

If the binary you need does not exist yet (e.g. a patched fix build), generate it via `qa-build` first, then copy that output basedir via this skill for the test run.

## Related skills

- `qa-build` - produces a fresh `<PREFIX>-mariadb-...` basedir that can be copied with this skill.
- `verify-fix` - orchestrates copies for fix-build + each affected version basedir.

## Notes

- A plain MTR run needs no copy - run it in place in `/test/<basedir>/mariadb-test`.
- Sanitiser basedirs (`UBASAN_*`, `MSAN_*`) need `./mtra` (applies suppressions), not `./mtr`.
- Do not run experiments directly in `gendirs.sh`-listed basedirs; copy to `/tmp` first.
