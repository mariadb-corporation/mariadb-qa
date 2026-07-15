---
name: build-fix-diff
description: In a /tmp copy of a /test/<ver> source tree, iterate a candidate MariaDB fix quickly - edit the source, build a light patched binary (a single build_mdpsms_*.sh variant, default dbg), run the test, and capture the change as fix.diff via git diff. This is the /tmp fix-iteration workspace; the source copy and the patched binary both stay in /tmp (ephemeral). Use when testing or iterating a candidate fix, or when a fix.diff artifact is needed. For a durable production build in /test use qa-build; to run an existing /test build standalone in /tmp use claude-basedir-fix-copy-setup.
claude: please note - this skill exists in a public repo and should only be updated with specific written signoff by the updater. Keep skills/README.md (the skills index) in sync when any skill is added, renamed, removed, or its description changes.
---

# build-fix-diff

A `/tmp` workspace for iterating a candidate MariaDB fix and capturing it as a diff. In a `/tmp` copy of the `/test/<ver>` source tree you edit the source, build a light patched binary (one `build_mdpsms_*.sh` variant, usually `dbg`), run the bug's test, and - once the fix holds - `git diff` the copy into `fix.diff`. The source copy and the patched binary both live in `/tmp` (ephemeral, quick to throw away and rebuild).

This is the quick fix-iteration path. It is deliberately light: one variant, in `/tmp`, fast to rebuild as you refine the fix. A durable, catalogued, multi-variant build is a different job.

## Related skills

- For a durable production build in `/test` (`ba`/`bas`/`bam`/`bat`, feature/ticket renames), see `qa-build` instead.
- For running an existing `/test` build standalone in `/tmp` (no build), see `claude-basedir-fix-copy-setup` instead.
- For the full multi-version fix-verification loop, see `verify-fix` instead.

## Inputs

- `<ver>` - MariaDB source-tree version under `/test` (e.g. `13.0`, `12.3`, `11.8`).
- `<tag>` - short label for this fix (e.g. the MDEV number), used in the `/tmp` copy name.
- `<out-dir>` - where `fix.diff` should be written (e.g. an MDEV working dir).
- `<variant>` - one `build_mdpsms_*.sh` variant to build; default `dbg`.
- The source edits that close the bug (gather from conversation context), or an existing `fix.diff` to apply.

If not provided in the invocation, ask the user.

## Procedure

1. Copy the source tree to `/tmp` (preserves `.git/` so `git diff` / `git apply` work):

   ```
   cp -r /test/<ver> /tmp/<ver>_fix_<tag>
   ```

2. Apply the fix inside `/tmp/<ver>_fix_<tag>` - edit the affected files with the Edit tool, or apply an existing diff:

   ```
   cd /tmp/<ver>_fix_<tag>
   git apply <out-dir>/fix.diff        # only when starting from an existing diff
   ```

   Keep edits minimal - only what closes the bug. No cosmetic whitespace or unrelated cleanups.

3. Build the light patched binary (default `dbg`; one variant for speed):

   ```
   cd /tmp/<ver>_fix_<tag>
   ~/mariadb-qa/build_mdpsms_<variant>.sh
   ```

   The script builds in a scratch sibling (`/tmp/<ver>_fix_<tag>_<variant>`) and moves the finished basedir to the parent - so it lands at `/tmp/<PREFIX>-mariadb-<x.y.z>-linux-x86_64-<opt|dbg>`.

4. Rebake helpers on the patched binary, then run the bug's test to confirm the fix:

   ```
   cd /tmp/<PREFIX>-mariadb-<x.y.z>-linux-x86_64-<variant>
   ~/st
   cd /tmp/<PREFIX>-mariadb-<x.y.z>-linux-x86_64-<variant>    # ~/st resets cwd; cd back
   ```

   CLI testcase - write the SQL to `in.sql`, then `./anc; ./test` (`./anc` gives a fresh datadir; client output goes to `mysql.out`, server log to `log/master.err`):

   ```
   cp <out-dir>/<testname>.sql in.sql
   ./anc; ./test
   ```

   MTR testcase (auto-detect test-dir - 10.6 / 10.11 use `mysql-test/`, 11.x+ use `mariadb-test/`):

   ```
   TESTDIR="mariadb-test"; [ ! -d "$TESTDIR" ] && TESTDIR="mysql-test"
   cp <out-dir>/<testname>.{test,result} "$TESTDIR/main/"
   cd "$TESTDIR" && ./mtra <testname>    # ./mtr for non-sanitiser builds
   ```

   Not fixed yet? Re-edit (step 2), rebuild (step 3), re-run (step 4). The `/tmp` build is light, so this loop is quick.

5. Capture the fix once it holds:

   ```
   cd /tmp/<ver>_fix_<tag>
   git diff > <out-dir>/fix.diff
   ```

6. Self-check: read `<out-dir>/fix.diff` and scan for hunks outside the intended scope (whitespace-only, unrelated adjacent edits). If present, undo in the `/tmp` copy and re-run step 5.

7. Cleanup. KEEP the `/tmp/<ver>_fix_<tag>` source copy (the `git diff` workspace) and the patched binary basedir (re-runnable) until the fix is verified; remove the build scratch:

   ```
   rm -rf /tmp/<ver>_fix_<tag>_<variant>    # build-script scratch (disposable)
   # when finished with the fix:
   cd /tmp/<PREFIX>-mariadb-<x.y.z>-linux-x86_64-<variant> && ./kill   # if a server is running
   rm -rf /tmp/<ver>_fix_<tag> /tmp/<PREFIX>-mariadb-<x.y.z>-linux-x86_64-<variant>
   ```

   State remaining `/tmp/` dirs at end-of-turn for the user to decide retention.

## Output

- `<out-dir>/fix.diff` - canonical `git diff` (with `a/path` / `b/path` and blob SHAs), the format developers expect.
- A `/tmp` patched binary basedir for continued standalone testing.

## What NOT to include in fix.diff

- Test files (`.test`, `.result`) - those live alongside the report (see `mtr_testcase`), not inside the diff.
- Adjacent unrelated cleanups in the same source file.
- Cosmetic whitespace changes.

## Galera builds

For a galera variant, symlink the Galera source into the copy first (`/test/galera_4x`; clone with `/test/clone_galera.sh` if absent):

```
cd /tmp/<ver>_fix_<tag> && ln -s /test/galera_4x .
```

## Notes

- Edit via the `/tmp` source-copy, never in-place in `/test/<ver>` (the shared reference tree).
- Capture baselines with `cp` (or `git show HEAD:<path>`), not `git stash` / `checkout` / `restore`.
- `cp -r` preserves `.git/`, so `git diff` yields the canonical format and `git apply` works.
- Sanitiser builds (`_san`, `_msan`) need `./mtra` for test runs, not `./mtr`.
- Keep it light - one variant in `/tmp`. Durable multi-variant builds go through `qa-build`.
