---
name: verify-fix
description: End-to-end verification of a candidate fix for a MariaDB bug. Five-step loop - draft fix.diff, build the fix binary, copy basedirs to /tmp, run the bug's MTR test against each affected version, log PASS/FAIL in versions_affected.txt, then cleanup. Use when a fix needs full verification across all affected versions.
claude: please note - this skill exists in a public repo and should only be updated with specific written signoff by the updater
---

# verify-fix

Five-step autonomous loop for verifying a bug's fix end-to-end. Orchestrates `fix-diff`, `qa-build`, and `claude-basedir-fix-copy-setup`.

## Inputs

- `<bug-dir>` - the working dir for this bug (holds `fix.diff`, the MTR test, and `versions_affected.txt`).
- `<ver>` - source-tree version to patch (e.g. `13.0`).
- The candidate fix (source edits) - gather from conversation context or from an existing `<bug-dir>/fix.diff`.
- List of basedirs to sweep - derive at runtime from `gendirs.sh`: `cd /test && bash gendirs.sh | grep -E '^(MD|EMD).*-opt$'`. Per-build results land in `<bug-dir>/versions_affected.txt`.

If any are missing, ask the user.

## Procedure

### Step 1 - Draft `fix.diff`

If `<bug-dir>/fix.diff` does not already exist, run the `fix-diff` skill:

- `cp -r /test/<ver> /tmp/<ver>_fix_<tag>`
- edit the affected files in the /tmp copy
- `cd /tmp/<ver>_fix_<tag> && git diff > <bug-dir>/fix.diff`

### Step 2 - Build the fix binary (exactly ONE version)

Build only the version specified in `<ver>` - typically the newest CS major (e.g. `13.0`). Do not build all affected majors. One fix-build is sufficient to verify that the patch closes the bug; the same MTR test then sweeps across every catalog basedir in step 4 to prove the bug is present pre-fix on each.

Run the `qa-build` skill. Source-tree copy AND output basedir both live in `/tmp/` - never under `/test/` (that's the curated catalog):

- `cp -r /test/<ver> /tmp/<ver>_fix_<tag>`
- `cd /tmp/<ver>_fix_<tag> && git apply <bug-dir>/fix.diff`
- `~/mariadb-qa/build_mdpsms_dbg.sh` (or the variant matching the affected basedir family - `_san` for UBASAN, `_msan` for MSAN, `_galera` for Galera)
- output: `/tmp/<PREFIX>-mariadb-<x.y.z>-linux-x86_64-<variant>`

### Step 3 - Verify on the fix build

The output basedir is already in `/tmp/`, so it's ready to use directly. Rebake helpers and run the MTR test:

```
cd /tmp/<PREFIX>-mariadb-<x.y.z>-linux-x86_64-<variant> && ~/st
# Auto-detect test-dir: 10.6 / 10.11 use mysql-test/, 11.x+ use mariadb-test/.
TESTDIR="mariadb-test"; [ ! -d "$TESTDIR" ] && TESTDIR="mysql-test"
cp <bug-dir>/<testname>.{test,result} "$TESTDIR/main/"
cd "$TESTDIR"
./mtra <testname>    # or ./mtr for non-sanitiser builds
```

Expected: PASS on the fix build (the test asserts the bug no longer fires).

### Step 4 - Re-verify on each affected catalog basedir

For every basedir flagged in the bug's sweep, repeat Step 3 against a `/tmp` copy of that catalog basedir. Expected: FAIL (bug observed) on each unpatched build.

For each basedir:

```
cp -r /test/<affected-basedir> /tmp/<affected-basedir>
cd /tmp/<affected-basedir> && ~/st
TESTDIR="mariadb-test"; [ ! -d "$TESTDIR" ] && TESTDIR="mysql-test"
cp <bug-dir>/<testname>.{test,result} "$TESTDIR/main/"
cd "$TESTDIR"
./mtra <testname>    # or ./mtr
# record PASS/FAIL
rm -rf /tmp/<affected-basedir>
```

Log results in `<bug-dir>/versions_affected.txt`. Columns typically: MTR | Verdict | full basedir name | one-line marker. Use full version strings, not parenthetical shorthand.

### Step 5 - Cleanup

KEEP the patched source tree and the patched binary basedir. Remove only the genuinely disposable pieces:

```
# KEEP: /tmp/<ver>_fix_<tag>                                     # source tree - git-diff it
# KEEP: /tmp/<PREFIX>-mariadb-<x.y.z>-linux-x86_64-<variant>     # patched binary basedir
rm -rf /tmp/<ver>_fix_<tag>_<dbg|opt>                            # build-script internal copy (disposable)
rm -rf /tmp/<affected-basedir>                                   # throwaway sweep /tmp copies
```

Tear down any running server instances (`./kill`) but leave the patched source tree and binary basedir in place. State remaining `/tmp/` dirs at end-of-turn so the user can decide retention.

## Variant selection

Match the build variant to the affected basedir family:

| Affected basedir prefix | Build variant |
|---|---|
| `MD...`, `EMD...` (no sanitiser) | `dbg` or `opt` |
| `UBASAN_MD...`, `UBASAN_EMD...` | `dbg_san` or `opt_san` |
| `MSAN_MD...`, `MSAN_EMD...` | `dbg_msan` or `opt_msan` |
| any `*galera*` | `dbg_galera` or `opt_galera` |

The cheapest verification is usually a `dbg` build - that's what catches the bug most clearly. Sanitiser builds are needed only when the bug was discovered via UBASAN/MSAN or when it requires sanitiser visibility (leaks, OOB reads).

## Default - do not re-ask

Routine fix-verification is in-scope. Do not end a turn asking "should I build the fix?" or "should I copy to /tmp?" - start the loop, surface results, flag only genuine judgment calls (fix scope, cross-version implications).

## Reporting at end-of-turn

- Per-version PASS/FAIL summary (mirroring `versions_affected.txt`).
- Path to `<bug-dir>/fix.diff`.
- Outstanding `/test/` and `/tmp/` dirs the user may want to keep or delete.

## Related skills

- `fix-diff` - Step 1 component.
- `qa-build` - Step 2 component.
- `claude-basedir-fix-copy-setup` - Steps 3 and 4 component.

## Notes

- Verification must cover ES + CS builds (ES = `EMD`/`UBASAN_EMD` prefix).
- Sanitiser builds need `./mtra` (applies suppressions); plain `./mtr` for non-sanitiser.
- Per-version results go in `versions_affected.txt`, not the report body; use full version strings, no parenthetical shorthand.
