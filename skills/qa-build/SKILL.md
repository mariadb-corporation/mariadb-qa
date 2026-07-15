---
name: qa-build
description: Build MariaDB server basedirs from a /test source tree in place, using the ba / bas / bam / bat aliases (opt+dbg, UBASAN opt+dbg, MSAN opt+dbg, TSAN opt+dbg) or a single build_mdpsms_*.sh variant. Output basedirs and tarballs land in /test alongside the source. Two uses - (1) a plain re-build of a released version tree (e.g. /test/13.1), and (2) a feature or ticket tree (/test/MDEV-... or /test/MENT-...) whose outputs get the MDEV-<n>_ / MENT-<n>_ prefix. Tarballs move to /data/TARS. This skill never touches /tmp - to run a built basedir standalone in /tmp without touching the original, copy it there with claude-basedir-fix-copy-setup (that skill copies, it does not build).
claude: please note - this skill exists in a public repo and should only be updated with specific written signoff by the updater. Keep skills/README.md (the skills index) in sync when any skill is added, renamed, removed, or its description changes.
---

# qa-build

Builds MariaDB server basedirs from a source tree under `/test`, in place, so the output basedirs and tarballs land in `/test` (the curated catalog). Two uses:

1. Plain re-build of a released version tree - e.g. `/test/13.1`. Output basedirs keep their generated catalog names.
2. Feature or ticket tree - `/test/MDEV-<n>...` or `/test/MENT-<n>...` - whose output basedirs are renamed with the ticket prefix.

This skill builds durable catalog basedirs in `/test` and never touches `/tmp`. To run a built basedir standalone in `/tmp` for Claude's own tests, evaluations, or fix verification - without touching the original - copy it there with `claude-basedir-fix-copy-setup` (that skill copies a built basedir, it does not build).

NEVER hand-roll `cmake`/`make`. Use the `ba` / `bas` / `bam` / `bat` aliases (each builds an opt+dbg pair) or a single `build_mdpsms_*.sh` variant. The build script's final `scripts/make_binary_distribution` is what yields a runnable basedir (with `bin/`) that `~/st` + `./anc` + `./cl` can drive; an in-source `make` alone does not. If a build fails, fix the INPUTS - use a clean full source tree (keep `.git/`; do not rsync-exclude `build*`, which wipes `cmake/build_configurations/`) - do not substitute a manual cmake/make.

## Related skills

- For a light patched fix build in `/tmp` (+ `fix.diff`), see `build-fix-diff` instead.
- For running a built basedir standalone in `/tmp` without touching the original, see `claude-basedir-fix-copy-setup` instead.
- For the full multi-version fix-verification loop, see `verify-fix` instead.

## Inputs

- `<source>` - the source tree under `/test` to build. A released version tree (`/test/13.1`, `/test/12.3`) or a feature/ticket tree (`/test/MDEV-14443`, `/test/MENT-1234`).
- `<variants>` - which builds to produce: `ba` (opt+dbg), `bas` (UBASAN opt+dbg), `bam` (MSAN opt+dbg), `bat` (TSAN opt+dbg), or a single `build_mdpsms_*.sh`. Default to `ba` if unspecified.
- For a feature/ticket tree: the ticket key for the output rename (`MDEV-<NNNNN>` or `MENT-<NNNN>`) - derive from the source dir name.

If not provided in the invocation, ask the user.

## Build aliases (ba / bas / bam / bat)

Four `~/.bashrc` aliases each launch a detached `screen` session that builds an opt+dbg pair in parallel (the second starts 70s after the first):

| Alias | Screen session | Scripts | Output prefix |
|---|---|---|---|
| `ba` | `opt_and_dbg_build` | `build_mdpsms_opt.sh` + `build_mdpsms_dbg.sh` | `MD<DDMMYY>` (CS) / `EMD<DDMMYY>` (ES) |
| `bas` | `opt_and_dbg_san_build` | `build_mdpsms_opt_san.sh` + `build_mdpsms_dbg_san.sh` | `UBASAN_MD` / `UBASAN_EMD` |
| `bam` | `opt_and_dbg_msan_build` | `build_mdpsms_opt_msan.sh` + `build_mdpsms_dbg_msan.sh` | `MSAN_MD` / `MSAN_EMD` |
| `bat` | `opt_and_dbg_tsan_build` | `USE_TSAN=1 build_mdpsms_opt_san.sh` + `USE_TSAN=1 build_mdpsms_dbg_san.sh` | `TSAN_MD` / `TSAN_EMD` |

`bam` (MSAN) requires clang-20 and instrumented libraries under `/MSAN_libs` (setup: `msan.instrumentedlibs_ubuntu2404.sh`). `bat` (TSAN) is the `_san` scripts with the `USE_TSAN=1` environment variable set - that switches them to `-DWITH_TSAN=ON` and a `TSAN_` prefix instead of `UBASAN_`. Sanitiser basedirs (`UBASAN_*`, `MSAN_*`, `TSAN_*`) need `./mtra` for test runs, not `./mtr`.

Each `build_mdpsms_*.sh` first copies the source to its own sibling scratch dir (`<source>_opt`, `<source>_dbg`, `<source>_opt_san`, `<source>_dbg_san`, `<source>_opt_msan`, `<source>_dbg_msan`) and builds there, so the pairs do not collide and `ba` + `bas` + `bam` can run in parallel. `bat` reuses the `_opt_san`/`_dbg_san` scratch (it is the `_san` build with `USE_TSAN=1`), so do NOT run `bat` and `bas` at the same time - run those two one after the other. Each emits a tarball plus an extracted basedir, renames both to the full `<PREFIX>-mariadb-<x.y.z>-linux-x86_64-<opt|dbg>` name, and moves both to the PARENT of the source tree - so building in `/test/<source>` lands the output in `/test`.

The alias body ends with an interactive `screen -d -r` reattach. When launching non-interactively (e.g. from a tool), run only the `screen -admS "<session>" bash -c "..."` portion and drop the reattach. Monitor with `screen -ls` and by watching for the output basedirs to appear.

## Procedure

1. `cd /test/<source>`.

2. Same-day collision check (do this BEFORE building) - see below. Skip only for a plain re-build you intend to replace.

3. Launch the build(s): `ba` and/or `bas` and/or `bam` and/or `bat` (or a single `build_mdpsms_<variant>.sh` for one variant; TSAN = `USE_TSAN=1 build_mdpsms_<dbg|opt>_san.sh`). Builds run in detached screens; wait for completion. Do not run `bas` and `bat` concurrently (shared `_san` scratch).

4. Locate the outputs (today's date):

   ```
   ls -dt /test/{MD,EMD,UBASAN_MD,UBASAN_EMD,MSAN_MD,MSAN_EMD,TSAN_MD,TSAN_EMD}$(date +%d%m%y)-mariadb-*-linux-x86_64-* 2>/dev/null | head
   ```

5. Plain re-build - the `MD<date>-...` / `EMD<date>-...` names ARE the catalog names; leave the basedirs in place. Feature/ticket tree - rename each output basedir (and its `.tar.gz`) with the ticket prefix (see below).

6. Move every tarball to `/data/TARS` (tarballs live there for re-extraction; they do not stay in `/test`).

7. Remove the build-scratch sibling dirs (`<source>_{opt,dbg,opt_san,dbg_san,opt_msan,dbg_msan}`) once outputs are in place; keep the source tree and the output basedirs.

## Same-day collision check

The output name is keyed on today's date and the source's `VERSION` file, NOT on the source dir name, and the build OVERWRITES any same-name dir in the parent when it moves output there. A feature branch shares its version with mainline (e.g. `MDEV-14443` is `13.1.0`, same as mainline `13.1`), so running `ba` in `/test/MDEV-14443` would clobber an existing same-day mainline `MD<date>-mariadb-13.1.0-...` build. First check:

```
ls -d /test/{MD,EMD,UBASAN_MD,UBASAN_EMD,MSAN_MD,MSAN_EMD,TSAN_MD,TSAN_EMD}$(date +%d%m%y)-mariadb-<x.y.z>-* 2>/dev/null   # match the prefix(es) you will build
```

- None exist -> safe to build in `/test/<source>`; rename outputs afterwards.
- Same-name dirs exist and you must NOT overwrite them (e.g. a feature tree colliding with mainline) -> do NOT build in `/test/<source>`. Put the source in a subdir - clone/copy to `/test/<tmpdir>/<clone>` - and build there so output lands in `/test/<tmpdir>/`. Then rename the output to `<KEY>_MD<date>-...` (unique), move it to `/test`, and `rm -rf /test/<tmpdir>`. Rename-before-move guarantees no collision on the move. Recover a clobbered build by re-extracting its tar from `/data/TARS`.

## Feature/ticket tree - rename convention

When a build belongs to a specific Jira ticket, prepend the ticket key (and an underscore) to BOTH the output basedir and its `.tar.gz`, keeping the build's own `MD`/`EMD`/`UBASAN_`/`MSAN_`/`TSAN_` prefix that follows:

- CS (MariaDB Server) tickets -> `MDEV-<NNNNN>_`
- ES (Enterprise) tickets -> `MENT-<NNNN>_`

```
# CS ticket, ba + bas + bam + bat outputs:
MDEV-14443_MD110626-mariadb-13.1.0-linux-x86_64-opt
MDEV-14443_MD110626-mariadb-13.1.0-linux-x86_64-dbg
MDEV-14443_UBASAN_MD110626-mariadb-13.1.0-linux-x86_64-opt
MDEV-14443_UBASAN_MD110626-mariadb-13.1.0-linux-x86_64-dbg
MDEV-14443_MSAN_MD110626-mariadb-13.1.0-linux-x86_64-opt
MDEV-14443_MSAN_MD110626-mariadb-13.1.0-linux-x86_64-dbg
MDEV-14443_TSAN_MD110626-mariadb-13.1.0-linux-x86_64-opt
MDEV-14443_TSAN_MD110626-mariadb-13.1.0-linux-x86_64-dbg
# (+ the matching .tar.gz for each)

# ES ticket: MENT-<NNNN>_EMD... / MENT-<NNNN>_UBASAN_EMD... / MENT-<NNNN>_MSAN_EMD... / MENT-<NNNN>_TSAN_EMD...
```

Rename the basedir (keep it in `/test`) AND the matching `.tar.gz` the same way, then move the tar to `/data/TARS`. Do this for ALL outputs of the run - a `ba`+`bas`+`bam`+`bat` set leaves eight basedirs and eight tars.

After renaming, verify nothing was missed:

```
ls -l /test/{MD,EMD,UBASAN_MD,UBASAN_EMD,MSAN_MD,MSAN_EMD,TSAN_MD,TSAN_EMD}$(date +%d%m%y)*.tar.gz 2>/dev/null   # MUST be empty
```

A stray date-stamped `<PREFIX><DDMMYY>-...-<variant>.tar.gz` in `/test` is an unfinished cleanup: rename it with the ticket prefix (if ticket-tied) and move it to `/data/TARS`.

## Single-variant build (build_mdpsms_*.sh)

For one variant only, run the matching script from the source-tree root instead of an alias:

| Script | Output |
|---|---|
| `build_mdpsms_dbg.sh` | Debug (`-DWITH_DEBUG=ON`, `O_LEVEL=1`) |
| `build_mdpsms_opt.sh` | Optimised (`RelWithDebInfo`, `O_LEVEL=2`) |
| `build_mdpsms_dbg_san.sh` / `build_mdpsms_opt_san.sh` | UBSAN + ASAN (`UBASAN_` prefix) |
| `USE_TSAN=1 build_mdpsms_dbg_san.sh` / `USE_TSAN=1 build_mdpsms_opt_san.sh` | TSAN (`TSAN_` prefix; the `_san` scripts with the `USE_TSAN=1` env var) |
| `build_mdpsms_dbg_msan.sh` / `build_mdpsms_opt_msan.sh` | MSAN (`MSAN_` prefix; needs clang-20 + `/MSAN_libs`) |
| `build_mdpsms_dbg_galera.sh` / `build_mdpsms_opt_galera.sh` | Galera (`GAL_` prefix; links `libgalera_smm.so`) |
| `build_mdpsms_dbg_valgrind.sh` / `build_mdpsms_opt_valgrind.sh` | Valgrind-compatible flags |

Fan-out across many source trees uses the `buildall_*.sh` wrappers (`buildall_dbg.sh`, `buildall_san_slow.sh`, `buildall_msan_slow.sh`, ...).

## Galera builds

Galera builds expect `./galera_4x` as a subdir of the source tree. `/test/galera_4x` is the canonical Galera source tree (separate from the MariaDB server source); clone it with `/test/clone_galera.sh` if absent. Before a galera variant:

```
cd /test/<source>
ln -s /test/galera_4x .
```

The build script then compiles galera and symlinks `libgalera_smm.so` from `galera_4x_dbg/` (opt build: `galera_4x_opt/`) into the output basedir's `lib/`.

## Why /test, not /tmp

- `/test/` is the curated catalog. `gendirs.sh` enumerates it and the per-basedir helpers (`~/st`, `./anc`, `./cl`, `~/d0..d9`) drive it. Durable re-builds and feature/ticket builds belong here so the rest of the framework can pick them up.
- The build script moves output to the PARENT of the source tree - so building in `/test/<source>` lands output in `/test` with no extra move.
- `/tmp` is only for standalone Claude test runs against a COPY of a basedir - that is `claude-basedir-fix-copy-setup`'s job (it copies a built basedir, it does not build).

## Notes

- Never hand-roll `cmake`/`make`; use `ba`/`bas`/`bam`/`bat` or a `build_mdpsms_*.sh` variant (the final `make_binary_distribution` is what yields a runnable basedir).
- Output basedirs and tars land in `/test` (parent of the source tree); tars then move to `/data/TARS`.
- This skill never uses `/tmp`.
- Sanitiser basedirs (`UBASAN_*`, `MSAN_*`, `TSAN_*`) require `./mtra` for test runs, not `./mtr`.
