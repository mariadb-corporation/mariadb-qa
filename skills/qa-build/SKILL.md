---
name: qa-build
description: Build a patched MariaDB server binary by copying /test/<ver> to /tmp/<ver>_<purpose> and running the appropriate ~/mariadb-qa/build_mdpsms_*.sh variant (dbg, opt, san, msan, galera, valgrind). The build script lands the output basedir in /tmp/ next to the source-tree copy - both stay ephemeral. Use when verifying a bug fix requires running the patched server (not just generating a diff), or when a custom debug/sanitiser build is needed.
claude: please note - this skill exists in a public repo and should only be updated with specific written signoff by the updater
---

# qa-build

Builds a patched MariaDB binary from a `/tmp` copy of `/test/<ver>` using one of the `~/mariadb-qa/build_mdpsms_*.sh` variants. Source-tree copy and output basedir BOTH live in `/tmp/` - they are ephemeral by design. Do NOT place builds under `/test/` (that's the curated catalog).

NEVER hand-roll `cmake`/`make` with bespoke flags. Use `ba`/`bas` (both opt+dbg) or a single `build_mdpsms_*.sh` (one variant). If a build script fails, fix the INPUTS - use a clean full `cp -r` of `/test/<ver>` (keep `.git/`; do not rsync-exclude `build*`, which wipes `cmake/build_configurations/`) - do not substitute a manual cmake/make. The script's final `scripts/make_binary_distribution` is what yields a real basedir (with `bin/`) that `~/st`+`./all`+`./cl` can drive; an in-source `make` alone does not.

## Inputs

- `<ver>` - source-tree version (e.g. `13.0`, `12.3`, `11.8`).
- `<purpose>` - short suffix for the source-tree copy dir (e.g. `fix_MDEV-99999`, `test`).
- `<variant>` - one of: `dbg`, `opt`, `dbg_san`, `opt_san`, `dbg_msan`, `opt_msan`, `dbg_galera`, `opt_galera`, `dbg_valgrind`, `opt_valgrind`. Default to `dbg` if unspecified.
- The source edits to apply (or an existing fix.diff to apply).

If not provided in the invocation, ask the user.

## Procedure

1. Copy the source tree to `/tmp` (preserves `.git/` for `git apply`):

   ```
   cp -r /test/<ver> /tmp/<ver>_<purpose>
   ```

2. Apply edits inside `/tmp/<ver>_<purpose>` - either via the Edit tool, or by applying an existing fix.diff:

   ```
   cd /tmp/<ver>_<purpose>
   git apply <bug-dir>/fix.diff
   ```

3. Run the build script from the source-tree root:

   ```
   cd /tmp/<ver>_<purpose>
   ~/mariadb-qa/build_mdpsms_<variant>.sh
   ```

   The script:
   - Reads `VERSION` and constructs `PREFIX=MD<DATE>` (CS) or `EMD<DATE>` (ES, when `support-files/rpm/*enterprise*` is present).
   - Internally copies the source tree to `<source>_dbg/` (or `_opt/`) and builds there.
   - Runs `cmake` + `make` + `scripts/make_binary_distribution`.
   - Renames the tarball + extracted dir to `<PREFIX>-mariadb-<x.y.z>-linux-x86_64-<dbg|opt>`.
   - Moves both to the parent of the source tree - so with source under `/tmp/<ver>_<purpose>`, the output lands at `/tmp/<PREFIX>-mariadb-<x.y.z>-linux-x86_64-<dbg|opt>`.
   - Writes `git_revision.txt` and `BUILD_CMD_CMAKE` into the output basedir.

4. Locate the output basedir:

   ```
   ls -dt /tmp/[ME]MD$(date +%d%m%y)-mariadb-*-linux-x86_64-*  | head
   ```

5. Cleanup. KEEP the patched source tree (the user `git diff`s it) and the patched output basedir (it may be re-run). Remove only the build-script internal copy:

   ```
   # KEEP: /tmp/<ver>_<purpose>                                  # source tree - user git-diffs it
   # KEEP: /tmp/<PREFIX>-mariadb-<x.y.z>-linux-x86_64-<dbg|opt>  # patched output basedir
   rm -rf /tmp/<ver>_<purpose>_<dbg|opt>                         # build-script internal copy (disposable)
   ```

   State remaining `/tmp/` dirs at end-of-turn for the user to decide retention.

## Why /tmp, not /test

- `/test/` is the curated catalog of stock and reference builds. The `gendirs.sh` enumerator drives audit-wide sweeps off it; injecting an ad-hoc patched build pollutes that namespace and can be picked up by unrelated tooling.
- `/tmp/` is ephemeral. The OS reclaims it; cleanup boundaries are obvious; collisions across concurrent sessions are unlikely with the `<ver>_<purpose>` naming.
- The build script's `mv ../` behaviour places output alongside the source-tree copy. So as long as the source-tree copy is in `/tmp`, the output is too.

## Build-script variants

| Script | Output |
|---|---|
| `build_mdpsms_dbg.sh` | Debug (`-DCMAKE_BUILD_TYPE=Debug`, `-O1`) |
| `build_mdpsms_opt.sh` | Optimised (release-equivalent, `-O2`) |
| `build_mdpsms_dbg_san.sh` | Debug + UBSAN + ASAN (the `UBASAN` prefix in output dir name) |
| `build_mdpsms_opt_san.sh` | Optimised + UBSAN + ASAN |
| `build_mdpsms_dbg_msan.sh` | Debug + MSAN (needs MSAN-instrumented libs) |
| `build_mdpsms_opt_msan.sh` | Optimised + MSAN |
| `build_mdpsms_dbg_galera.sh` | Debug + Galera (links `libgalera_smm.so`) |
| `build_mdpsms_opt_galera.sh` | Optimised + Galera |
| `build_mdpsms_dbg_valgrind.sh` | Debug + Valgrind-compatible flags |
| `build_mdpsms_opt_valgrind.sh` | Optimised + Valgrind-compatible flags |

## Bulk build via ba / bas (parallel screens)

For building multiple variants of one source tree at once, two `~/.bashrc` aliases launch detached `screen` sessions that build in place:

| Alias | Screen session | Builds (sequentially, second starts after 70s) |
|---|---|---|
| `ba` | `opt_and_dbg_build` | `build_mdpsms_opt.sh` then `build_mdpsms_dbg.sh` |
| `bas` | `opt_and_dbg_san_build` | `build_mdpsms_opt_san.sh` then `build_mdpsms_dbg_san.sh` |

Run them from the source-tree root (e.g. `/test/<ver>` or `/test/<TICKET>`). Each `build_mdpsms_*.sh` first copies the tree to its own sibling (`<dir>_opt`, `<dir>_dbg`, `<dir>_opt_san`, `<dir>_dbg_san`) and builds there, so the four builds do NOT collide and `ba` + `bas` run in parallel safely.

Outputs (tarball + extracted basedir) land in the PARENT dir:
- `ba` -> `MD<DDMMYY>-mariadb-<x.y.z>-linux-x86_64-{opt,dbg}` (+ matching `.tar.gz`).
- `bas` -> `UBASAN_MD<DDMMYY>-mariadb-<x.y.z>-linux-x86_64-{opt,dbg}` (+ `.tar.gz`).

So one `ba` + `bas` pair yields 4 dirs + 4 tars, all dated today; tell variants apart by the `MD`/`UBASAN_MD` prefix and the date.

**Same-day collision check (do this BEFORE building).** The output name is keyed on today's date and the `VERSION` file, NOT on the source dir name, and the build OVERWRITES any same-name dir in the parent when it moves output there. A feature branch shares its version with mainline (e.g. `MDEV-14443` is `13.1.0`, same as mainline `13.1`), so running `ba` in `/test/<TICKET>` clobbers an existing same-day mainline `MD<date>-mariadb-13.1.0-...` build. First check:

```
ls -d /test/{MD,EMD,UBASAN_MD,MSAN_MD}$(date +%d%m%y)-mariadb-<x.y.z>-* 2>/dev/null   # match the prefix(es) you will build
```

- None exist -> safe to run `ba`/`bas` in `/test/<source>`; rename outputs to `<KEY>_MD...` afterwards.
- Same-name dirs exist -> do NOT build in `/test/<source>`. Put the source in a subdir - clone/copy to `/test/<tmpdir>/<clone>` - and run `ba` there so output lands in `/test/<tmpdir>/`. Then rename the output to `<KEY>_MD<date>-...` (unique), move it to `/test`, and `rm -rf /test/<tmpdir>`. Rename-before-move guarantees no collision on the move. Recover a clobbered build by re-extracting its tar from `/data/TARS`.

The alias body ends with an interactive `screen -d -r` reattach. When launching non-interactively (e.g. from a tool), run only the `screen -admS "<session>" bash -c "..."` portion and drop the reattach.

Locate the outputs (today's date):

```
ls -dt /test/{MD,UBASAN_MD}$(date +%d%m%y)-mariadb-*-linux-x86_64-* | head
```

### Tie outputs to a ticket (rename convention)

When a build belongs to a specific Jira ticket, prepend the ticket key (and an underscore) to BOTH the output dir and its `.tar.gz`, keeping the build's own `MD`/`EMD`/`UBASAN_` prefix that follows:

- CS (MariaDB Server) tickets -> `MDEV-<NNNNN>_`
- ES (Enterprise) tickets -> `MENT-<NNNN>_`

```
# CS ticket, ba + bas outputs:
MDEV-14443_MD110626-mariadb-13.1.0-linux-x86_64-opt
MDEV-14443_MD110626-mariadb-13.1.0-linux-x86_64-dbg
MDEV-14443_UBASAN_MD110626-mariadb-13.1.0-linux-x86_64-opt
MDEV-14443_UBASAN_MD110626-mariadb-13.1.0-linux-x86_64-dbg
# (+ the four matching .tar.gz)

# ES ticket: MENT-<NNNN>_EMD... / MENT-<NNNN>_UBASAN_EMD...
```

Handle the dir and its tar together, every variant: rename the basedir (keep it in `/test`) AND rename the matching `.tar.gz` the same way, then move the tar to `/data/TARS` (tarballs live there for re-extraction; they do not stay in `/test`). Do this for ALL outputs of the run, not just some - each `build_mdpsms_*.sh` emits one `.tar.gz` per basedir, so a `ba`+`bas` pair leaves 4 tars to relocate.

After renaming, verify nothing was missed:

```
ls -l /test/{MD,EMD,UBASAN_MD,MSAN_MD,TSAN_MD}$(date +%d%m%y)*.tar.gz 2>/dev/null   # MUST be empty
```

A stray date-stamped `<PREFIX><DDMMYY>-...-<variant>.tar.gz` in `/test` is an unfinished cleanup: rename it with the ticket prefix and move it to `/data/TARS`. This keeps all artifacts for one ticket grouped and identifiable; distinguish builds from the same day by the `MD`/`EMD` vs `UBASAN_` prefix.

## Galera builds

Galera builds expect `./galera_4x` as a subdir of the source tree. `/test/galera_4x` is the canonical Galera source tree (separate from the MariaDB server source).

Before running a galera variant, either:

```
cd /test/<ver>_<purpose>
ln -s /test/galera_4x .
```

or rsync `/test/galera_4x` into place. The build script then compiles galera and copies `libgalera_smm.so` from `galera_4x_dbg/` into the output basedir's `lib/`.

## Source-tree naming convention

- `/test/<ver>_fix_<tag>` - for fix verification (mirrors the `/tmp/<ver>_fix_<tag>` pattern used by `fix-diff`).
- `/test/<ver>_<ticket-id>` - when tied to a specific Jira ticket.
- `/test/<ver>_test` - ephemeral experimentation.

Do not overwrite user-managed reference trees: `/test/13.0`, `/test/13.0_dbg`, `/test/13.0_fixed`, `/test/13.0_fixed_dbg`.

## Cleanup checklist

- Source-tree copy (`/test/<ver>_<purpose>`): remove after build success and verification.
- Built basedir (`/test/<PREFIX>-mariadb-...`): keep if relevant to a filed finding; otherwise remove.

State what `/test/` dirs remain at end-of-turn so the user can decide retention.

## Related skills

- `fix-diff` - generate the diff before running this skill, if no fix.diff exists yet.
- `claude-basedir-fix-copy-setup` - after the binary builds, copy the output basedir to `/tmp` for autonomous test runs.
- `verify-fix` - full fix-verification loop (orchestrates fix-diff -> qa-build -> claude-basedir-fix-copy-setup -> version sweep).

## Notes

- Never hand-roll `cmake`/`make`; use the `build_mdpsms_*.sh` variants (the final `make_binary_distribution` is what yields a runnable basedir).
- Source-tree copy and output basedir both live in `/tmp/` (ephemeral), never under `/test/`.
- Sanitiser basedirs (`UBASAN_*`, `MSAN_*`) require `./mtra` for test runs, not `./mtr`.
