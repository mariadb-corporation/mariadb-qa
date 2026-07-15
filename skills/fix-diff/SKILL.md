---
name: fix-diff
description: Generate a fix.diff for a MariaDB code change by copying /test/<ver> to /tmp, editing the source, and running git diff. The patched /tmp source tree is KEPT (it is the git-diff workspace), not deleted. Use when a candidate fix needs to be recorded as a diff artifact in a bug/working dir.
claude: please note - this skill exists in a public repo and should only be updated with specific written signoff by the updater
---

# fix-diff

Generates `<out-dir>/fix.diff` from a source-edit cycle in a `/tmp` copy of the MariaDB source tree.

## Inputs

- `<ver>` - MariaDB source-tree version (e.g. `13.0`, `12.3`, `11.8`).
- `<out-dir>` - the dir where `fix.diff` should be written (e.g. an MDEV working dir).
- The source edits to apply (gather these from conversation context - what code change closes the bug).

If not provided in the invocation, ask the user.

## Procedure

1. Copy the source tree (preserves `.git/` so `git diff` works):

   ```
   cp -r /test/<ver> /tmp/<ver>_fix_<tag>
   ```

   `<tag>` is a short label for this fix (e.g. the MDEV number).

2. Edit the affected files inside `/tmp/<ver>_fix_<tag>` using the Edit tool. Add inline comments describing what the change does where it helps a reviewer. Keep edits minimal - only the changes that close the bug. No cosmetic whitespace/comment cleanups on unrelated lines.

3. Generate the diff:

   ```
   cd /tmp/<ver>_fix_<tag>
   git diff > <out-dir>/fix.diff
   ```

4. Self-check: read `<out-dir>/fix.diff` and scan for hunks outside the intended scope (whitespace-only changes, unrelated adjacent edits). If present, undo in the `/tmp` copy and re-run step 3.

5. KEEP the `/tmp/<ver>_fix_<tag>` tree. Do NOT delete it - it is the patched source-tree workspace used to `git diff` after the session, not a throwaway. Report its path.

## Output

`<out-dir>/fix.diff` - canonical `git diff` format with `a/path` / `b/path` and blob SHAs. This is what developers expect.

## What NOT to include

- Test files (`.test`, `.result`) - those live alongside the report (see the `mtr_testcase` skill), not inside the diff.
- Adjacent unrelated cleanups in the same source file.
- Cosmetic whitespace changes.

## Worked example

`MDEV-99999` - a missing null check in `ha_innobase::open`:

```
cp -r /test/13.0 /tmp/13.0_fix_MDEV-99999
# edit /tmp/13.0_fix_MDEV-99999/storage/innobase/handler/ha_innodb.cc: add the guard
cd /tmp/13.0_fix_MDEV-99999
git diff > ~/MDEV-99999/fix.diff
# keep /tmp/13.0_fix_MDEV-99999 - git-diff against it later
```

## Why /tmp and not in-place

- `/test/<ver>` is the canonical reference source tree. Local edits would silently affect every other build/task using the same tree.
- `/tmp` is the workspace; the patched tree is KEPT so you can `git diff` against it later. Do not delete it.
- `cp -r` preserves `.git/` so `git diff` yields the canonical format.

## Related skills

- `qa-build` - when you also need a runnable patched binary, not just a diff.
- `verify-fix` - when this is part of a full fix-verification cycle.

## Notes

- Edit via a `/tmp` source-copy, never in-place in `/test/<ver>` (the shared reference tree).
- Capture baselines with `cp` (or `git show HEAD:<path>`), not `git stash`/`checkout`/`restore`.
