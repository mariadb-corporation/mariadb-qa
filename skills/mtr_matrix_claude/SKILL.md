---
name: mtr_matrix_claude
description: Run one MTR testcase against every build that gendirs.sh lists and write a Bug Detection Matrix, using ~/mariadb-qa/claude/claude_mtr_matrix.sh. The build set comes from the gendirs.sh option - the plain CS/ES/MySQL builds, or SAN, MSAN, TSAN, VAL, GAL, MDEV, ALL. Use when a bug report or a fix needs the affected-version list, or when a testcase has to be run across all versions at once.
claude: please note - this skill exists in a public repo and should only be updated with specific written signoff by the updater. Keep skills/README.md (the skills index) in sync when any skill is added, renamed, removed, or its description changes.
---

# mtr_matrix_claude

`~/mariadb-qa/claude/claude_mtr_matrix.sh` copies one `.test` into every BASEDIR that `gendirs.sh` lists, runs it there in parallel, and prints a Bug Detection Matrix plus the testcase in `~/b` report form. The report also goes to `report.log` in the current directory.

It complements `/test/mtr_testrun.sh`: the test name may be suite-qualified, so a test in `suite/galera` or any other suite is reachable, and the builds run at the same time.

## Usage

```
~/mariadb-qa/claude/claude_mtr_matrix.sh {MTR testcase} [suite] [gendirs.sh option] [parallel jobs]
```

```
~/mariadb-qa/claude/claude_mtr_matrix.sh MDEV-12345.test                  # plain builds, main suite
~/mariadb-qa/claude/claude_mtr_matrix.sh MDEV-12345.test '' SAN           # UBASAN builds
~/mariadb-qa/claude/claude_mtr_matrix.sh MDEV-12345.test '' ALL           # everything gendirs.sh has
~/mariadb-qa/claude/claude_mtr_matrix.sh galera_ctas_partition.test galera '' 6
```

Run it with no argument for the built-in usage text.

## The gendirs.sh option, which picks the build set

| Option | Build set |
|---|---|
| (empty) | CS, ES and MySQL builds, no sanitizer, no Galera |
| `SAN` | UBASAN builds |
| `MSAN` | MSAN builds |
| `TSAN` | TSAN builds |
| `VAL` | Valgrind builds |
| `GAL` | Galera builds |
| `M` or `MDEV` | MDEV feature builds |
| `ALL` | the default set plus the sanitizer, Galera and monty builds |

Run `cd /test && bash gendirs.sh <option>` first to see which builds an option covers. An option with no builds on this box makes the script assert, which is the expected answer.

Each BASEDIR is run through its own `./mtra`, which sets the ASAN, UBSAN, MSAN and TSAN options and then calls `./mtr`. A BASEDIR without `./mtra` falls back to `./mtr`. Both come from `~/st`.

A version sweep on the plain builds already gives the affected-version list. A sanitizer sweep changes the symptom, from a crash to a report, not the set of versions. Run `SAN` when the report needs a sanitizer stack.

## What the testcase has to be

- Reverse-gated: it fails while the bug is present and passes once the bug is fixed. Without that every row reads `No`. Ref the `mtr_testcase` skill.
- Named for the bug, for example `MDEV-12345.test`, so MTR selects one test only.
- A `.result` beside it is copied to the suite's `r/` directory, and a `.cnf` beside it is copied next to the testcase.
- Set `WSREP_PROVIDER` before a galera-suite run.

## Reading the matrix

```
    Rel    o/d  Build   Commit                                    Affected
CS  12.3   opt  180826  add63991988734383c5e942de2a19c6c45f511f7  No
CS  13.1   dbg  180826  da18481158c81ca94689702073c3e04aad85a6a3  Yes (line 15)
```

- `No` - the test passed, so this build is not affected.
- `No (gate did not trigger, line N)` - the statement the gate expects to fail did not fail, so
  this build does not have the bug.
- `Yes (line N)` - the test failed on that line. A row that failed on a different line than the
  others never reached the gate, so its `Yes` says nothing about the bug; read that build by hand.
- A UniqueID, for example `SIGSEGV|...` - the run crashed or a sanitizer reported. The report then carries a stack for each distinct UniqueID, one per line item, from `stack.sh`.
- `Yes (run did not complete)` - the run did not finish and left nothing to read. Check that build by hand.

The row layout is the framework's own, from `version_chk_helper.source`, the same as the `line` script in a BASEDIR. Paste the matrix into the bug report as it stands.

## Notes

- Each BASEDIR's `mysql-test/var` (or `mariadb-test/var`) is removed before its run, as `mtr_testrun.sh` does.
- MTR picks a free port range itself, so a sweep does not collide with another MTR run on the box.
- Default parallel jobs is 48, capped at the number of BASEDIRs. Lower it when the box is busy.
- Each run has a 900 second timeout per build.
- The testcase and its `.result` stay in the BASEDIRs after the run. Remove them when the sweep was a one-off.
