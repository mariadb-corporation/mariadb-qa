---
name: build-scripts-version-updates
description: Bring the clone and build scripts up to date when MariaDB trunk moves to a new version or a new branch appears - clone.sh, cloneall.sh, the buildall_*.sh set, clone_all_full_for_bisect.sh and git-bisect.sh, and the ES scripts when a new X.Y-enterprise branch exists. Reads the live branch list first, makes each edit in the same form as the earlier version steps, proves the edits with a dry run that clones and builds nothing, then copies the tested files into place. Use for "trunk is now X.Y", "the clone and build scripts are outdated", "add X.Y to the build scripts", "/build-scripts-version-updates".
claude: please note - this skill exists in a public repo and should only be updated with specific written signoff by the updater. Keep skills/README.md (the skills index) in sync when any skill is added, renamed, removed, or its description changes.
---

# build-scripts-version-updates

The clone and build scripts hold fixed version lists. When trunk (`main`) moves to a new version, the
old trunk becomes a branch, and each list needs every new version. The scripts live in
`~/mariadb-qa/mariadb-build-qa/` and `~/mariadb-qa/`, and `linkit` links them into `/test` and
`/test/git-bisect`. Edit the files in `~/mariadb-qa`, never the links.

The examples below use the step from trunk 13.1 to trunk 13.3: 13.1 and 13.2 became branches, and
13.2 and 13.3 were added.

## 1. Get the facts

```
git ls-remote --heads https://github.com/MariaDB/server.git | grep -E 'refs/heads/(main|1[0-9]\.[0-9]+)$'
curl -s https://raw.githubusercontent.com/MariaDB/server/main/VERSION
git ls-remote --heads https://github.com/mariadb-corporation/MariaDBEnterprise.git | grep -- '-enterprise$'
curl -s https://endoflife.date/api/mariadb.json
grep -n 'Trunk is' ~/mariadb-qa/mariadb-build-qa/clone.sh ~/mariadb-qa/mariadb-build-qa/cloneall.sh
```

- The new trunk is MAJOR.MINOR from the `VERSION` file of `main`.
- The new versions are the branches newer than the newest version in the scripts, plus the new trunk.
- The ES command needs `~/.git-credentials`. Change the ES scripts only when a new `X.Y-enterprise`
  branch exists.
- Ask the user which versions are EOL. The Jira version names (`X.Y(EOL)`) and endoflife.date can
  lag behind.

## 2. Check that no script runs

```
ps -eo pid,args | grep -E 'buildall_|clone(all)?(_es)?\.sh|clone_all_full|git-bisect\.sh' | grep -v grep
```

Bash reads a script while it runs, so an edit under a live run can break that run. Wait until it ends.

## 3. The edits

| File | Change |
|---|---|
| `mariadb-build-qa/clone.sh` | The `if [ "${1}" == "<old trunk>" ]` test and its `# Trunk is currently` comment name the new trunk |
| `mariadb-build-qa/cloneall.sh` | A `./clone.sh X.Y &` line per new branch, the old trunk included, after the last one. The last line clones `main` into the new trunk dir, with the comment updated |
| `buildall_{dbg,opt}.sh` and `buildall_{dbg,opt}_{san,msan,tsan,val}.sh` (10 files) | A copy of the newest `cd ${DIR}/X.Y && ...` line per new version, directly after it |
| `buildall_slow.sh`, `buildall_san_slow.sh`, `buildall_val_slow.sh` | `BUILD_X_Y=1` per new version after the newest one. A copy of the newest `if [ ${BUILD_X_Y} -eq 1 ]` block per new version at the top of `buildall()`, newest first. `buildall_slow.sh` also needs `USE_EXTRA_A_OPT_X_Y=1` |
| `buildall_msan_slow.sh`, `buildall_tsan_slow.sh` | `BUILD_X_Y=1` per new version. A `[ ${BUILD_X_Y} -eq 1 ]   && build_ver X.Y` line per new version at the top of `buildall()`, newest first. The `(<old trunk> -> main)` comment in `build_ver()` names the new trunk |
| `~/mariadb-qa/clone_all_full_for_bisect.sh` | The old trunk line gets `--branch=` and loses its comment. One `--branch=` line per new branch. A last line clones `main` into the new trunk dir, `# Trunk is X.Y atm` |
| `~/mariadb-qa/git-bisect.sh` | `LATEST_MARIADB_CS_VERSION=<new trunk>`. Leave the other user variables alone: they belong to the bisect in progress |
| `mariadb-build-qa/d1`, `o1`, `u1`, `uo1` | The version in the `ls -d` pattern names the new trunk. Until a build of it exists in `/test`, the `d`, `o`, `ds` and `os` aliases land in the home dir |

These `sed` commands make the line copies for the 13.1 to 13.3 step. Adapt the versions:

```
cd new/mariadb-build-qa   # The scratch copy of step 4
sed -i '/^cd \${DIR}\/13\.1 /{p;s/13\.1/13.2/;p;s/13\.2/13.3/}' buildall_dbg.sh
sed -i '/^BUILD_13_1=1$/{p;s/13_1/13_2/;p;s/13_2/13_3/}' buildall_slow.sh
sed -i '/^  \[ \${BUILD_13_1} -eq 1 \]   && build_ver 13\.1$/{s/13_1/13_3/;s/13\.1/13.3/;p;s/13_3/13_2/;s/13\.3/13.2/;p;s/13_2/13_1/;s/13\.2/13.1/}' buildall_msan_slow.sh
```

Keep the order of each list: oldest first in the parallel scripts, newest first in `buildall()` of
the slow scripts. Write variable names with an underscore, as `BUILD_13_3`. A dot, as in
`${BUILD_12.3}`, is a bash error.

When a script has changed shape, look at how the previous version went in:
`git -C ~/mariadb-qa log -p -S'<previous trunk>' -- mariadb-build-qa/<script>`.

Other cases:

- A new ES branch: `clone_es.sh` (an `elif` for a new major), `cloneall_es.sh`, `buildall_es.sh`,
  `buildall_es_san.sh`, the `if [ -d ${DIR}/X.Y-es ]` line of the 10 parallel scripts, the
  `rm -Rf X.Y-es_dbg` / `_opt` lines, and `BUILD_ES_X_Y` with its block in the slow scripts.
- A new major, such as 14.0: each `1[0-3]` glob in an `rm -Rf` line becomes `1[0-4]`, and the major
  test in `clone.sh` gets `|| "${1}" == "14."*`. The `build_mdpsms_*.sh` scripts test the major
  against `^1[0-5]$`, so check that test from 16.0 on.
- An EOL version: comment its lines out (`#cd`, `#./clone.sh`, `#rm -Rf ...; git clone`) and set its
  `BUILD_X_Y=0`.
- The Galera and MySQL (`_ms`) scripts keep their own lists. Change them only when asked.

## 4. Edit a copy, prove it, then apply

1. Copy `~/mariadb-qa/mariadb-build-qa/` (under 1 MB), `clone_all_full_for_bisect.sh` and
   `git-bisect.sh` twice into a scratch dir, as `old/` and `new/`. Make the edits in `new/` and run
   `bash -n` on each changed file. `diff -rq old new` lists the changed files.
2. Dry run both sets and compare:

```
DR=~/mariadb-qa/skills/build-scripts-version-updates/dry_run.sh
diff <(${DR} old/mariadb-build-qa old/clone_all_full_for_bisect.sh) <(${DR} new/mariadb-build-qa new/clone_all_full_for_bisect.sh)
```

   `dry_run.sh` clones and builds nothing. It runs each script in a fake test dir and a fake home
   with stub build scripts, and it stubs `git`, `sudo`, `screen`, `sync` and `sleep`. Each clone or
   build call prints one line. Each run header must show `(exit 0)`. The only differences must be
   the new build and clone lines, and the `order:` lines of the slow scripts, which must now start
   with the newest version.
3. Check with `cmp` that the originals did not change since the copy. Copy each changed file over its
   original (the original keeps its mode), then check with `cmp` and `bash -n` again.
4. Run `${DR} ~/mariadb-qa/mariadb-build-qa ~/mariadb-qa/clone_all_full_for_bisect.sh` and compare
   it with the output of `new/`. The two must be the same. The dry run does not cover
   `git-bisect.sh`, whose change is one value. Test `d1`, `o1`, `u1` and `uo1` in a scratch dir that
   holds a copy of `/test/REGEX_EXCLUDE` and empty basedirs of the old and new trunk: source each one
   there and check that it lands in the new trunk basedir.
5. Remove the scratch dir.

## 5. Report

- The changed files: `git -C ~/mariadb-qa diff --stat`, and the command for the full diff. The user
  runs `git add` and `git commit`.
- The `/test/<X.Y>` source trees that hold the wrong version. Check with
  `grep -E 'MAJOR|MINOR' /test/<X.Y>/VERSION`. A tree cloned from `main` before trunk moved holds the
  new trunk under the old name. Do not clone or build: the user runs `cloneall.sh` and the buildall
  scripts.
- Any gap found on the way, such as a version missing from one list, as a short line.
