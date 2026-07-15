---
name: jira-ticket
description: Turn a reduced pquery trial under /data/<workdir>/<trial> into a filed public MariaDB bug. Pick the most-reduced testcase, hand-reduce it further and prettify with ~/tcp against the version where it reproduces, dedup-check EARLY against jira.mariadb.org (and present a decision menu if a duplicate is found), generate the bug report via ~/b (and ~/bs / ~/br as warranted), splice any SAN stacks/Setup/matrix into the body, build and verify an MTR testcase (CLI/MTR compatible note, or dual CLI+MTR blocks), derive Affects+Fix versions / components / labels / priority, write a paste-ready overview to log_jira_ticket.txt for approval, file the MDEV ticket via ~/jira, then register it (eb testcase + kb/kba UniqueIDs) and clean matching workdirs (ca). Public generic crash / assert / UB / ASAN bugs only - security-class findings are out of scope.
claude: please note - this skill exists in a public repo and should only be updated with specific written signoff by the updater
---

# jira-ticket

Files one public MariaDB server bug (project MDEV) from a reduced pquery trial. AI-driven: the reduction, dedup judgement, title synthesis, field inference, and SAN merge all need reasoning, not a fixed script.

## Inputs

- `<trial-dir>` - a pquery trial dir, e.g. `/data/someworkdir/sometrial`.

## Pre-flight - Jira PAT

Steps 3, 7, and 9 authenticate against jira.mariadb.org with a Personal Access Token, read from `$JIRA_PAT` or `~/.config/mariadb-qa/jira.pat`. Check before starting:

```bash
[ -n "$JIRA_PAT" ] || [ -s ~/.config/mariadb-qa/jira.pat ] || echo "NO PAT"
```

If no PAT is in place, STOP and tell the user how to get one: log in to https://jira.mariadb.org, click your avatar (top right) -> Profile -> Personal Access Tokens -> Create token (pick a name; an expiry is optional), copy the token (shown once), then save it:

```bash
mkdir -p ~/.config/mariadb-qa && (umask 077; printf '%s\n' '<token>' > ~/.config/mariadb-qa/jira.pat)
```

Verify with `~/jira --whoami`.

## Hard rules (read first)

- NEVER submit before explicit user approval of `log_jira_ticket.txt` (step 8). The user said so directly.
- Dedup BEFORE the expensive work (step 3, before `~/b`/MTR). If it is a duplicate, do not burn a full version sweep - present the decision menu.
- Dedup uses `~/tt`'s emitted Search URLs **verbatim**: extract the `?jql=` from `tt`'s actual output and run that exact string. NEVER hand-build, re-frame, re-quote, or add/drop terms - `tt` owns frame selection and exact-phrase quoting; improvising the query is a defect. Run `~/tt` in the SAME basedir whose stack you will report (UniqueID frames are build-dependent). This no-improvisation rule applies to every framework tool: use its real output, do not reconstruct it from memory.
- Scope = public generic bugs (crash / assert / UB / ASAN) in project **MDEV**. If the trial is a security-class finding (auth/ACL/escalation/RCE/disclosure primitive), STOP and route to the security flow (`~/mariadb-qa/security/`); do not file it here.
- The Jira body IS the `~/b` report block, near-verbatim. Do not re-prose it. Match the existing house style - it is already encoded in `b`/`bs`/`br`.
- Every testcase SQL statement stays on ONE unbroken line - in `log_jira_ticket.body`, the eb file, the `.test`, AND in any chat display. Wrapping/splitting a line breaks pquery/reducer/MTR replay. When presenting CLI + MTR testcases, stack them as separate full-width blocks; never side-by-side (it wraps lines).
- NEVER post a comment (`~/jira --comment`) on the user's behalf without BOTH (a) the user's explicit instruction to comment AND (b) the user's review and approval of the EXACT, literal comment text. Comments are outward-facing - draft it, show the verbatim text, wait for sign-off; never auto-post.
- All deliverable prose is timeless and literal (CLAUDE.md). No "fixed in", "re-scored", build-internal paths, or `MD<DDMMYY>`/`EMD` shorthand in the Jira body - use CS/ES + version.

## Tools used

| Tool | Role |
|---|---|
| `~/jira` (`log_jira_ticket.sh`) | files the MDEV ticket; also `--comment <KEY>`, `--link <KEY> --relates <KEY>`, `--edit <KEY>` (additively add Affects/Fix versions to an existing issue), `--createmeta`, `--whoami`; 3x-confirm (`-y` to skip for a directly-instructed edit) |
| `~/b` / `~/bs` / `~/br` | bug report (regular / SAN / replication); run inside a basedir; tees to `report.log` |
| `~/tcp` (`testcase_prettify.sh`) | prettify testcase; converts `--sql_mode=` header to `SET sql_mode='';` |
| `~/t` / `~/tt` | UniqueID; UniqueID + known-bugs scan + Jira search URLs |
| `~/st` / `./anc` / `./all` / `./test` / `./multirun_loop` | basedir setup + repro loop |
| `~/i <trialnum>` | trial info (run from the workdir); the `BASEDIR`/`REPLICATION` lines |
| `~/dt <trialnum>` | delete a trial in a workdir |
| `~/eb` / `~/kb` / `~/kba` / `ca` | register testcase / known UniqueID / SAN UniqueID / clean known trials |
| `cd /test && bash gendirs.sh` | enumerate available basedirs/versions |

---

## Step 1 - Locate and gate the reduced testcase

`cd <trial-dir>`. Reduced output files are named `<N>.sql_out`, `<N>.sql_out_out`, … - more `_out` = more reduced. Select the deepest-reduced file:

```bash
ls -1 *.sql_out* 2>/dev/null | grep -v '\.prev$' | awk '{n=gsub(/_out/,"_out"); print n, $0}' | sort -rn -k1,1 | head -n1 | cut -d' ' -f2-
```

**Gate:** a reduced testcase must exist. If only a raw `<N>.sql` (no `_out`) is present, STOP - the trial has not been reduced; tell the user to reduce it first (`~/sr <N>`). Read the chosen file; note its first line if it is `# mysqld options required for replay: <opts>`.

**Non-issue pre-check (do this first, it's the fastest exit).** Read the trial's `MYBUG` UID and grep `~/mariadb-qa/known_bugs.strings`(`.SAN`) and `~/mariadb-qa/REGEX_ERRORS_FILTER.info` for the error/UID. If it is tagged a documented **non-issue** (e.g. `## SPECIAL-NN (non-issue)`, or a `Presumed non-issue` note - like `INSERT after DISCARD TABLESPACE` = SPECIAL-33), STOP: it is expected behaviour, not a bug. Skip it (`ca`/clean already disposes of matching trials). Do not reduce/report/file.

## Step 2 - Reduce further by hand, then prettify (and verify repro)

Reduce against the version where it reproduces, so `~/b` later carries a real backtrace and step 3 can compute the UniqueID.

1. **Find the basedir.** The trial dir is `<workdir>/<trialnum>`; from the workdir run `~/i <trialnum> | grep -E 'BASEDIR|REPLICATION'` (do NOT grep `reducer<N>.sh` - its `BASEDIR=` is a `<set_below…>` placeholder; and `~/i` must run from the workdir, not inside the trial dir). The reproducing basedir is often a `UBASAN_`/`MSAN_` build - for the regular `~/b` report strip that prefix to its non-SAN sibling of the same version (`UBASAN_MD050626-…-13.1.0-…-dbg` → `MD050626-…-13.1.0-…-dbg`); keep the SAN basedir for step 5 (`~/bs`). If the wanted basedir is gone, pick the closest version from `cd /test && bash gendirs.sh`. Prefer the **dbg** basedir of the reproducing version (asserts/SIGABRT and clean frames come from dbg). Replication trials show `MASTER_EXTRA`/`SLAVE_EXTRA`/`REPL_EXTRA` lines in `~/i <trialnum>` - treat those as REPLICATION=1.
2. **Prepare it (fallback).** Gendirs basedirs are normally already prepared. If the chosen basedir lacks `./all`/`./test` etc. (e.g. a freshly-built newest version), run `~/st` once to generate them.
3. **Carry the header options.** The `# mysqld options required for replay: <opts>` line is a marker, NOT auto-applied by `./start`. Pass `<opts>` as the `MYEXTRA` arg to `./all_no_cl`. Reducer often leaves these even when unneeded (it did not reach stage 8) - test repro both WITH and WITHOUT them and keep only what is load-bearing. `--sql_mode=` and `--bin-log`/`--log_bin` are common keepers; `--sql_mode=` belongs in the testcase as `SET sql_mode='';` (tcp converts it).
4. **Repro loop** (manual cycle): `./all_no_cl <opts>` (fresh datadir) → `./test` (replays `in.sql`) → check `ls ./data/core*`. Core present → run `~/t`, compare its UniqueID to the trial's original (the assert + top frame should match; lower frames may differ by build). Same bug = still reproduces. For sporadic bugs use `./multirun_loop` with `export BUG='<UniqueID>'` (or `export ELBUG='<errlog string>'` for non-core error-log bugs). A loop ≥90s is treated as a hang.
5. **Hand-reduce, re-checking the UniqueID after EVERY cut.** Write the candidate into `in.sql` (overwrite is fine). Cut statements/clauses/values one at a time; after each cut re-run the loop AND run `~/t` (or `~/tt`) to read the UniqueID. Keep a cut ONLY if the UniqueID still matches the target - "still crashes" is not enough; a changed UniqueID means you have reduced into a DIFFERENT bug, so revert that cut. Target the minimal testcase (typically a handful of lines); preserve required `SET` statements (e.g. `sql_mode`). Normalize identifiers to generic minimal names: a single table is `t` (its single column `c`; multiple columns `c1`,`c2`,…); multiple tables are `t1`,`t2`,…; drop index/constraint names. Re-verify the UniqueID after renaming. **The reducer `_out` file is a STARTING point, NOT the final testcase** - it is frequently still padded with scaffolding. **Scaffolding that only builds state is removable:** a second table, a trigger, a loop, or an `INSERT…SELECT` whose only job is to POPULATE the crashing table is not load-bearing in itself - trace the crashing table's final rows (values AND NULLs) and reproduce them with direct `INSERT`s, then drop the helper table/trigger and re-verify the UniqueID. Likewise drop any column the crash query never reads, and any row count above the minimum that still fires. Always ATTEMPT to remove or simplify an `INSERT DELAYED` (try plain `INSERT`, or drop it) - the delayed-insert worker is sometimes load-bearing (its THD participates in the crash), so keep it ONLY if removal/simplification breaks the UID. **Final-pass idiom cuts:** once the testcase is otherwise minimal, do a last pass trying to drop each reducer "wrapper" idiom and re-verify the UID after each: `SET sql_mode='';` (often a no-longer-needed artifact once values are clean), `CREATE OR REPLACE TABLE` -> plain `CREATE TABLE`, `INSERT DELAYED` -> `INSERT`, explicit `ENGINE=InnoDB` -> default engine. Keep each only if its removal breaks repro. See [[feedback_sql_mode_removable_after_reduction]]. If the testcase still contains a table, trigger, column, or option the crash path does not touch, it is NOT minimal - keep cutting. **Engine/plugin red herring:** under `SET sql_mode=''` an `ENGINE=<X>` for an unloaded engine silently substitutes the default engine (a warning, not an error), so `ENGINE=CONNECT` may actually be an InnoDB table - confirm the real engine with `SELECT ENGINE FROM information_schema.tables WHERE table_name='…'` and reduce to the engine that genuinely triggers it. The same substitution makes a build look "clean" only because the engine differs there (plugin not loaded), so confirm the same engine is in effect when comparing builds. **Is InnoDB load-bearing?** If the testcase carries `ENGINE=InnoDB`, re-test on the default engine (drop the explicit `ENGINE=`). If it still reproduces, InnoDB is NOT required - leave the table `ENGINE`-less so the MTR testcase needs no `--source include/have_innodb.inc`. Keep `ENGINE=InnoDB` (and the `have_innodb.inc` guard) ONLY when the bug is genuinely InnoDB-specific - and then add `Storage Engine - InnoDB` to the components (step 5). Same rule for any engine guard (`have_partition.inc`, `have_rocksdb.inc`, …): require the include only when that engine is load-bearing, and reflect a load-bearing engine in the components.
6. **Prettify.** Run `~/tcp in.sql` and adopt its output (strips backticks, normalises spacing/case, converts the `--sql_mode=` header to `SET sql_mode='';`). tcp is beta: it can break repro, AND it sometimes gets things clearly wrong (observed: lowercasing a function name, inserting a space before `(` e.g. `char_length (c)`). Re-run the loop on the prettified testcase to confirm it still fires, and hand-fix anything tcp clearly mangled (restore correct function casing, remove stray spaces). If you spot a clear, general `~/tcp` improvement, propose it to the user as a question - do not silently patch `~/tcp`.

**Gate:** `~/tcp` has been run; the testcase is truly minimal and re-verified to reproduce; you have the UniqueID and a core in the basedir.

## Step 3 - Duplicate check (do this EARLY, before `~/b`)

With a reproducing basedir (core present), run the dedup now - a duplicate must not cost a full version sweep. Dedup needs ONLY `~/tt`'s output (the String Scan + the dedup URLs). Do NOT extract or analyse the gdb backtrace / "debug section" to do dedup - `~/tt`'s URL already encodes the significant frames and yields the same result. (The backtrace is captured later, in step 4, for the report body only.)

1. **Known-bugs scan** - `~/tt` in the basedir prints `----- String Scan -----`: `BUG NOT FOUND IN KNOWN BUGS LIST!` (new), `ALREADY KNOWN BUG! ## MDEV-xxxxx` (live duplicate), or `ALREADY KNOWN *PREVIOUSLY FIXED*… ## MDEV-xxxxx` (fixed - check for re-emergence/regression). **Read the ENTIRE String Scan, not just its first line.** When it reports `BUG NOT FOUND (IDENTICALLY)` it then prints `HOWEVER A PARTIAL MATCH BASED ON THE Nth FRAME … :` FOLLOWED BY the matching known_bugs lines, each tagged `## MDEV-xxxxx` - those listed lines ARE the candidate duplicate(s). NEVER `grep`/`head` the String Scan down to its header (that discards the `## MDEV` lines and is exactly how a real dup gets missed). A `## MDEV-xxxxx` partial-frame match on the same function/file is very likely THAT MDEV: one ticket covers ALL frame/operation variants its `## MDEV`-tagged lines carry, so do NOT promote it to "new/distinct site" on a different frame, file line, or the ticket's SUMMARY wording - that judgement belongs to step 3.3 (testcase-SQL comparison), not to a line/operator diff. Two local cross-checks confirm the same dup with no web search: `grep` `~/mariadb-qa/known_bugs.strings`(`.SAN`) for the crashing FUNCTION (not only the exact UID), and read `~/mariadb-qa/BUGS/MDEV-<key>.sql` (`eb <key>`) for its registered testcases.
2. **Authenticated JQL search - use `tt`'s EXACT emitted URLs; never hand-build the query.** `~/tt` prints up to two `----- Search URL … -----` lines (a 3-frame URL always; an assert-message URL for asserts). `tt` owns the frame selection and the exact-phrase quoting - do NOT re-pick frames, re-quote, or add/drop terms. Show the user the URLs verbatim, and run each URL's encoded `?jql=` UNCHANGED through the REST search:

  ```bash
  cd <reproducing-basedir>          # frames are build-dependent: run tt where the reported stack came from
  PAT="$(< ~/.config/mariadb-qa/jira.pat)"
  TTOUT="$(~/tt 2>/dev/null)"
  printf '%s\n' "$TTOUT" | grep -A1 'Search URL' | grep '^https'   # the URLs, verbatim, for the user to click
  while IFS= read -r U; do
    JQL="${U#*\?jql=}"              # already-encoded jql, used UNCHANGED
    echo "== $U"
    curl -sS -H "Authorization: Bearer $PAT" -H 'Accept: application/json' \
      "https://jira.mariadb.org/rest/api/2/search?jql=${JQL}&fields=key,summary,status,resolution&maxResults=25" \
      | jq -r '.issues[]? | "\(.key)\t\(.fields.status.name)\t\(.fields.resolution.name // "-")\t\(.fields.summary)"'
  done < <(printf '%s\n' "$TTOUT" | grep -A1 'Search URL' | grep '^https')
  ```

  Report what `tt`'s URLs actually return - do not substitute your own frame choice or "which frames matter" judgement for `tt`'s.

3. **Evaluate the testcase SQL against each candidate (gate).** The candidate set is EXACTLY what `tt`'s URLs return - primarily the first (3-frame) URL. NEVER introduce tickets from elsewhere, from the broad assert-message family, or from your own recall; that sprawl is the failure mode to avoid. For each `tt` hit, open its testcase/description and compare the SQL features actually used - `TRIGGER`, partitioning, virtual columns, system versioning, engine, optimizer switches, the specific clause. Reject any candidate carrying a distinguishing feature ours lacks (or vice-versa): e.g. `ALTER … TRANSACTIONAL=1` (MDEV-35310), `SET optimizer_switch='mrr=on'` (MDEV-36241), or a required `TRIGGER` - none of which match a testcase without them. Treat as a duplicate only when the crash signature AND the testcase shape align. If EVERY `tt` hit is rejected, the bug is NEW - file it; do NOT manufacture a duplicate.

**Decision:**

- **Clearly new** (no live match) → proceed to step 4.
- **Likely duplicate, or fixed-but-reproduces** → STOP, do NOT file a new ticket, and present the user a short menu. For a duplicate the DEFAULT is to register (not delete):

  | Option | Action |
  |---|---|
  | Register + eb (almost always do all three) | (1) Add the UniqueID to `kb` (crash/error) and/or `kba` (SAN) tagged `## <KEY>` (col-176, step 11) - other runs hit this bug and must be recognised/filtered. (2) `eb` OUR testcase into `BUGS/<KEY>.sql` as a distinct testcase - if a testcase is already there (e.g. a non-framework reporter's you derived, or another variant), leave ONE blank line before ours; `git add`. eb collects ALL testcases for the bug locally, regardless of whether we also comment. (3) `ca` to clean matching trials. |
  | Comment to the ticket (post for a stack variant or a substantially different testcase) | Post a note when EITHER our testcase SUBSTANTIALLY differs from the dup's (different SQL structure, even if the UID is identical) OR ours is a **stack variant** of the dup (a different UID / frames / call path into the SAME bug) - a variant stack tells the dev the bug is reachable another way, so a variant USUALLY warrants a short note even when the SQL is similar. Intro `Ran into this one also. CLI testcase:` (label `CLI testcase` unless you have verified it in MTR) + the testcase (`{code:sql}`) + the UniqueID wrapped in `{noformat:title=<run `~/myver` in the basedir - NOT `~/m`, which opens vi>}` … `{noformat}` so the version it hit is clear (e.g. title `CS 13.1.0 <sha> (Debug, UBASAN, Clang …) Build DD/MM/YYYY`). UID-alone is fine ONLY if the full stack is already in the issue; otherwise include the full stack; escalate to the full stack / Bug Detection Matrix when warranted; if the STACK/UID itself differs, frame the intro as `Additional testcase with slight stack variation:`. ALWAYS end the comment with the line `Please also test any fixes with this testcase.` (so the dev validates the fix against this variant too). "Substantially differs" is judged against ALL existing testcases in the issue - the description AND every comment (some may be the user's own); read them first, and post only when this testcase adds a genuinely new path/index/version (e.g. DESC vs ASC, skip_nulls vs next_min, a newer regression range). Present the LITERAL text for approval, then `~/jira --comment <KEY> --description-file <file> -y`; NEVER auto-post (hard rule). Minor diffs only → skip the comment (the eb-append already captured it). |
  | Extend the dup's versions | When our repro confirms the bug live on a NEWER mainline GA than the issue lists (e.g. it lists up to `12.1(EOL)` but crashes on `13.0`/`13.1` builds), ADD those versions to the existing issue rather than commenting the same testcase: `~/jira --edit <KEY> --affects-version 13.0 --affects-version 13.1 --fix-version 13.0` (additive PUT, never replaces; **mainline X.Y names only - `13.0`, NOT `13.0.1`**; Fix excludes the newest branch, which gets the fix by up-merge). `-y` to skip the 3x prompt for this directly-instructed edit. Validate each name exists via `/rest/api/2/project/MDEV/versions` first. Prefer this over a comment when the testcase/mechanism is the SAME and only the affected range differs. |
  | File as a new/distinct bug | Only if genuinely distinct, or a real regression of a fixed one → proceed to step 4. |
  | Skip / delete the trial | Rare: `~/dt <trialnum>` is almost never used here - registering + `ca` already disposes of matching trials. Skip/delete only if not even worth registering. |

  Lead with the closest existing key and your same-root-cause assessment so the choice is informed.

**Reporter / logging origin (check this for a duplicate).** Whether the dup's UniqueID is already in `kb`/`kba` depends on who logged it and how:

- **Framework-logged** (loggers who use `b`/`br`/`bs` - Roel, Ramesh and Saahil are the main ones, plus various others; the tell is a bug-report-style body: `{code:sql}` testcase + version build-tag `{noformat}` blocks + a Bug Detection Version Matrix): their UniqueID is already registered in `kb`/`kba`, so `tt`'s String Scan will recognise it.
- **Non-framework reporters** (e.g. Elena Stepanova / `elenst`; free-form testcase, no UID): their bug's UniqueID is NOT in `kb`/`kba`. So `tt`'s String Scan may say "NOT FOUND" even when it IS a known bug. For these: RUN the reporter's testcase (CLI - drop `--source`/cleanup - or MTR) on a matching build to derive its UID, register it (`kb`/`kba`, col-176), and `eb` a CLI version to `BUGS/<KEY>.sql` (`git add`). Then compare THEIR UID to ours: an identical UID means ours is the SAME bug (not a "stack variation" - no comment); only a genuinely different stack makes ours a variation worth a comment.

**Gate:** the new-vs-duplicate call is grounded in `tt`'s actual URL hits AND a testcase-SQL comparison (step 3.3) - never frames/assert alone. For a dup logged by a non-framework reporter, also derive+register its UID (above).  Also capture any same-family-but-not-duplicate `tt` hit (e.g. an adjacent assert / code-path sibling like MDEV-35310 for a vcol `marked_for_read` bug) as a **related** issue, to propose for linking in step 10.

## Step 4 - Generate the bug report

Copy the minimal testcase into the matching mainline basedir as `in.sql` and run the report there. Basedir naming (`gendirs.sh`): `MD`=CS, `EMD`=ES, `MS`=MySQL; the 6 digits are the build date; `mariadb-X.Y.Z` gives the version; `-dbg`/`-opt` is the build type.

- Run `~/b` from the reproducing **dbg** basedir (so the in-block stack is a real `gdb bt`; an opt-only basedir prints "DID NOT CRASH"). `~/b` sweeps every gendirs version and builds the Bug Detection Matrix.
- **The CWD basedir MUST be a `gendirs.sh` entry** or `~/b` asserts ("the current directory ... is not included in gendirs.sh"). A trial's recorded `BASEDIR` is often a NON-gendirs build (e.g. `MD100426-13.0.1` when gendirs' 13.0 is the newer `MD210526-13.0.1`). In that case copy the testcase to the gendirs **dbg** basedir of the reproducing version (`cd /test && bash gendirs.sh | grep -E '^(MD|EMD).*<ver>.*-dbg$'`), verify it still crashes there, then run `~/b`.
- Run `~/br` **as well** only if the bug is replication-related (replication trial, or needs `--bin-log`).
- The SAN check is step 5; run it as `~/b SAN` (the `~/bs`/`~/br`/`~/bm` shell aliases are not callable from a non-interactive shell - invoke `~/b SAN` / `~/b REPL` / `~/b MSAN`).
- **Options**: `~/b` does NOT take mysqld options as CLI args (it errors `set: --: invalid option` and aborts). Pass them via the in.sql FIRST-LINE header `# mysqld options required for replay: --opt1 --opt2`; `~/b` parses that header and applies it to every sweep server (and so does the SAN/REPL variant). `--log_bin` is the common one (RESET MASTER / binlog-path bugs); keep the header line in `testcase.sql` too.

`~/b` tees to `report.log`. The Jira body is the block between these literal markers:

```
-------------------- BUG REPORT --------------------
   {code:sql} … testcase … {code}
   Leads to:
   {noformat:title=<CS/ES version build tag>} … gdb bt / assert line … {noformat}
   {noformat:title=Bug Detection Matrix} … per-version rows … {noformat}
-------------------- /BUG REPORT --------------------
```

```bash
sed -n '/^-------------------- BUG REPORT --------------------$/,/^-------------------- \/BUG REPORT --------------------$/p' report.log | sed '1d;$d'
```

**Prose paragraphs must be a single unwrapped line.** `~/b` hard-wraps the explanatory prose; un-wrap each prose paragraph to one line (only `{code}`/`{noformat}` blocks keep their line structure). **Never clobber the user's edits on a filed ticket:** there is no `~/jira` description-edit, so a description change needs a raw `PUT .../rest/api/2/issue/KEY` with `{fields:{description:...}}` (jq `-Rs` to encode the body) - before any full re-PUT, re-fetch the live description and carry forward any manual edits the user made, then sync the local `log_jira_ticket.body`/`.txt`. See [[feedback_jira_desc_prose_unwrapped_no_clobber]].

**Gate:** a well-formed report with a real stack (not "DID NOT CRASH") and a Bug Detection Matrix that shows the bug present in at least one row.

**Pre-file gate - reconcile the matrix against commit / up-merge status (CRITICAL).** The matrix is a snapshot of specific build COMMITS. A build's version STRING or date does NOT prove the fix is present: a build labelled `12.3.2` but cut before the `12.3.2` fix commit still crashes, and a clean cell can mean "already fixed in that build", not "unaffected". MariaDB lands a fix in the earliest affected GA branch and up-merges OLDEST→NEWEST in stages ([[reference_mariadb_upmerge_flow]]), giving two traps:

- **Newest clean, older crash - investigate, never assume "fixed".** A newer-branch-only difference does NOT by itself prove a fix: the newest branch may simply behave DIFFERENTLY (divergent code) while the older branches stay genuinely affected. Treat it only as a TRIGGER to check fix status; the verdict comes from the fixing commit, not the cross-build behaviour. (1) Identify the `Closed/Fixed` MDEV for this crash - match on the crash FUNCTION + signal, since UniqueID frames vary by optimizer plan (`multi_update::do_updates` vs `Sql_cmd_update::update_single_table` are one `evaluate_update_default_function` root cause); `~/tt`'s SAN UID may already carry `## MDEV-xxxxx` even when the dbg crash UID reads "NEW". (2) Read which BRANCH it was fixed in (its fixVersion). Up-merge is OLD→NEW (10.6 → 11.4 → … → 13.0 → 13.1): a fix in branch X is in X and ALL NEWER branches' current source, so a bug fixed in 12.3 is fixed in 12.3/13.0/13.1, and any older-dated build of those branches that still crashes is STALE (pre-fix). A stale pre-fix build crashing proves nothing. (3) For a variant (different frames), confirm the fix actually COVERS this path - read the fix commit (is the guard at the shared crash point, or only the other caller?) or re-test on a build of the affected branch that POST-DATES the fix commit. If the bug is fixed in its branch and that fix up-merges to every branch the matrix flagged, it is a DUPLICATE - do NOT file; register the variant UID under that MDEV (step 11) so stale-build occurrences are recognised, and report it.
- **Fix on the way (old branches clean, newest crashes).** A fix may already be in an older branch (e.g. 10.6) but not yet up-merged to the newest (e.g. 13.1) - up-merge is staged. Here the bug IS live + fileable on the newest, but a clean OLD cell means "already fixed there", not "unaffected".

Only when a build that POST-DATES any candidate fix STILL reproduces is it a live, fileable bug. Set Affects = branches affected AND not-yet-fixed in current source, Fix = branches where the fix has/will land; never infer fix presence from a version string or build date alone.

### Step 4a - Feature-only variant (no mainline match)

If the bug reproduces only on a feature-branch build excluded from `gendirs.sh` (e.g. GTT / `MDEV-35915*`), there is no mainline matrix. The feature ships ~4 builds - `MDEV-…_MD…-opt`, `…-dbg`, `MDEV-…UBASAN…-opt`, `…-dbg` (or similar). Test the testcase against each; include only the stacks that fire:

- dbg crash → `gdb bt`; opt crash → opt stack.
- dbg / opt SAN → the SAN extract from the error log (the `{noformat:title=… UBASAN …}` block; see `~/bs` output / past SAN bugs).
- No SAN issue → omit SAN. No crash on a build → omit it.

Result: **no Bug Detection Matrix, just 2-4 stacks**. Affects/Fix come from the feature build's version; the description references the feature MDEV.

## Step 5 - SAN check and merge into the body

(Before the approval gate, so the comment the user approves in step 8 is final.) After `~/b`, read the `----- *SAN Execution of the testcase -----` mini-report (after `/BUG REPORT`). If a real `ASAN|…`/`UBSAN|…`/`MSAN|…` UniqueID appears (not "No SAN issue detected"):

1. Run `~/bs` with the same `in.sql` in the matching `UBASAN_…`/`MSAN_…` **dbg** basedir.
2. From that `bs` BUG REPORT block, take, in order: the **SAN stack** (`{noformat:title=… UBASAN …}` … `==…==ABORTING` `{noformat}`); the **`Setup:`** block (`Setup:` + `{noformat}` … `{noformat}`); the **`{noformat:title=SAN Bug Detection Matrix}`** … `{noformat}` block.
3. Splice all three **directly under the crash stack** in the main body, above the regular Bug Detection Matrix. Keep the blocks verbatim.

If SAN-only (no core), the SAN stack is the primary stack. If no SAN issue fired, skip and do not mention SAN.

## Step 6 - MTR testcase

Follow the **[[mtr_testcase]]** skill for the full craft (engine guards InnoDB/partition/RocksDB/Spider, Mroonga-via-INSTALL, replication setup, default-engine difference, `--error` coverage, server options, reverse-gating, run-in-place + `./mtra` for SAN, failure-signature fixes). The essentials below are the report-specific bits.

Every report needs an MTR testcase alongside the CLI one. If the exact CLI SQL runs in MTR and reproduces the same failure, it is "CLI/MTR compatible" - note that, keep one block. Otherwise craft a separate MTR version and include both. Idioms:

- Default engine: standalone CLI defaults to InnoDB; the MTR main suite does not. If the bug needs InnoDB, add `--source include/have_innodb.inc` (and/or explicit `ENGINE=InnoDB`).
- Expected errors: gate any statement that legitimately errors with `--error <ER_NAME|errno>` so mtr does not abort early.
- Server options: a `# mysqld options required for replay: <opt>` header becomes inline `SET` where possible (`--sql_mode=` → `SET sql_mode='';`), else a `<name>.opt`/`.cnf`, `--mysqld=--<opt>`, or `$restart_parameters`.
- One SQL statement per line. Plain `test` db is fine for a functional crash repro (the dedicated-db rule is security-only).

Reproduce the SAME failure as the CLI testcase (fail / inverse gate): a crash kills the server; an error-message bug is gated with `--error`. Do NOT `--record` buggy output. Verify in place (no /tmp copy): drop `<name>.test` into the reproducing dbg basedir's `mariadb-test/main/` and run `./mtr <name>` there. **`~/tt` works INSIDE `mariadb-test/`**: after the run, `cd mariadb-test && ~/tt` and confirm the UniqueID equals the original - a different UniqueID means the MTR test hits a DIFFERENT bug (fix the test, do not ship it). See [[feedback_mtr_run_in_place]], [[feedback_reverse_gate_tests]], [[feedback_mtr_sql_one_line]].

Fold into the body's testcase section, replacing the single `{code:sql}` block:

- Compatible: keep one `{code:sql}` block + the plain line `Testcase is CLI/MTR compatible`.
- Not compatible: two blocks under plain-text labels (NOT Jira headers):

  ```
  CLI Testcase:
  {code:sql}
  <cli testcase>
  {code}

  MTR Testcase:
  {code:sql}
  <mtr testcase>
  {code}
  ```

**Gate:** the MTR testcase reproduces AND `~/tt` (run in `mariadb-test/`) returns the SAME UniqueID as the original; folded into the body.

## Step 7 - Derive the Jira fields

- **Title** (synthesize - the report has none). House style: `<assert text | SIGNAL> in <function> on <SQL op>`; SAN leads with the tool (`ASAN <class> in <fn> on <op>`, `UBSAN: <message> in <fn> on <op>`). Source the signal/assert + frames from the UniqueID, the function from frame 1-2, the op from the triggering statement. **Keep it SHORT** - favour a terse op + the single load-bearing modifier over a verbose descriptive clause, and abbreviate (`w/`, `vcol`). E.g. prefer `... in Item_func_connection_id::val_int on INSERT w/ TRIGGER` over `... on INSERT into a table with a CONNECTION_ID() virtual column`. Sentence case, no terminal period.
- **Versions - THREE fields, all from the Bug Detection Matrix** (rows whose UniqueID column is not "No bug found"; ignore MS rows; `Rel` is already `X.Y`). MDEV tracks CS and ES affects SEPARATELY:

  ```bash
  curl -sS -H "Authorization: Bearer $PAT" -H 'Accept: application/json' \
    'https://jira.mariadb.org/rest/api/2/project/MDEV/versions' | jq -r '.[].name'
  ```

  - **Affects Version/s** (`--affects-version`) = the **CS** rows. Map each `X.Y` to a real Jira version: `X.Y`, else `X.Y(EOL)`, else drop + note (validate against the list above).
  - **Affects ES Version/s** (`--es-version` → `customfield_13204`, a labels field) = the **ES** rows, as bare `X.Y` tokens (no version validation - it is free-text labels). This is a DISTINCT field from CS Affects; populate it whenever the matrix has ES rows, otherwise it defaults to "Unknown". (There is no separate ES Fix field.)
  - **Fix Version/s** (`--fix-version`) = the CS-affected set minus the single newest branch (highest `X.Y`, currently `13.1`) - it lands by up-merge. Real Jira names only.
  - Surface all three in the overview for adjustment.
  - A clean (`No bug found`) cell can mean *already fixed in that build*, not *unaffected* (step 4 up-merge gate); a crashing older-dated cell can be *stale* (predates an up-merged fix). Reconcile each Affects/Fix entry against the fix-commit status; never set them from build version strings/dates alone.
- **Components** (1-3) - infer from the crashing subsystem/frames + SQL: `Optimizer`, `Optimizer - Window functions`, `Storage Engine - InnoDB`, `Replication`, `Parser`, `Server`, `GIS`, `Character Sets`, `Partitioning`, `Data Definition - Temporary`, `Data Manipulation - Insert`, `Stored routines`, `Triggers`, `Views`, `Virtual Columns`, `Storage Engine - <Engine>`. Component names are case- and spelling-EXACT - `~/jira` create 400s on a bad one (`Component name '<X>' is not valid`). Common traps: `Stored routines` (lowercase r), DML is split into separate `Data Manipulation - Insert` / `- Update` / `- Delete` / `- Subquery` (no combined name). Validate every `-c` against the live list before filing: `curl -sS -H "Authorization: Bearer $(< ~/.config/mariadb-qa/jira.pat)" 'https://jira.mariadb.org/rest/api/2/project/MDEV/components' | jq -r '.[].name'`. Full map + gotchas: [[reference_mdev_component_names]]. Add an engine component (`Storage Engine - InnoDB`, `Partitioning`, `Storage Engine - <X>`) ONLY when that engine is load-bearing for the repro (per the step-2 engine test) - not merely because the reduced testcase happens to use it. If InnoDB is NOT load-bearing, drop `ENGINE=InnoDB` from the testcase instead (no `have_innodb.inc` needed).
- **Labels** - pick from in-use labels, validate each via `https://jira.mariadb.org/rest/api/1.0/labels/suggest?query=<label>`; never invent one. **NEVER post `crash` or `assertion`** as labels - they exist in Jira but are not used as tags (the crash/assert nature is already clear from the title and the body stack/assert message). Use specific class/context labels instead: `regression` + `regression-X.Y` (e.g. `regression-10.6`), `ASAN`/`UBSAN`/`MSAN` (the tool), the SAN class, `debug` (debug-only - opt shows "No bug found"), `optimizer_trace`, `affects-tests` (when it genuinely affects testing). A plain crash with no regression/SAN/feature angle may carry NO labels.

  For an ASAN/UBSAN/MSAN bug, derive the SAN class label from the `SUMMARY:` line of the SAN log - `SUMMARY: <AddressSanitizer|UndefinedBehaviorSanitizer|MemorySanitizer>: <class> <file>:<line>` - take the `<class>` token (e.g. `null-pointer-use`, `heap-use-after-free`, `heap-buffer-overflow`, `stack-buffer-overflow`, `dynamic-stack-buffer-overflow`, `use-after-poison`, `use-of-uninitialized-value`). The SAME bug often emits DIFFERENT wording across builds at the SAME `file:line` (e.g. dbg `load of null pointer` vs opt `member access within null pointer`; both are null-pointer-use). EVERY such applicable variant the matrix sweep produced for this bug IS part of the bug - capture ALL of them for the kb/kba registration (step 11), and use the primary class as the label. (Only a SUMMARY at a genuinely DIFFERENT `file:line` belongs to a different bug.) Validate the label token before use.
- **Priority** - `Major` for a typical crash/assert; `Critical` for a high-impact bug or a regression present for some time; `Blocker` for a recent regression. Never below `Major`.
- **Assignee** - derive the default from [[reference_mdev_default_assignees]] by the subsystem owning the bug's ROOT cause (the feature fundamentally involved, not the surface symptom). A virtual-column bug goes to Virtual columns (Aleksey Midenkov / midenok) even when it surfaces via the optimizer's filesort. A sibling's assignee (from dedup) is only a weak hint, and only if it is TRULY the same bug - do NOT override the map from a loosely-related sibling. Resolve the display name to a Jira username via `https://jira.mariadb.org/rest/api/2/user/search?username=<prefix>` (the param is `username`, NOT `query`), set with `--assignee <username>`, and surface it (Display Name + username) in the overview for signoff.

**Username casing (gotcha).** A Jira username/account `key` is lowercase - use it in JQL (`reporter = <username>`, `assignee = <username>`), `--assignee`, `[~handle]` mentions, and `user/search?username=`. The current user's own identity comes from their PAT: `~/jira --whoami` prints it, and `curl -sS -H "Authorization: Bearer $PAT" https://jira.mariadb.org/rest/api/2/myself | jq -r .key` gives the exact lowercase key. But a comment's `author.name` can be CAPITALISED and `author.displayName` is the full display name. When matching comment authorship programmatically (e.g. "find comments by the current user"), compare `author.key` (lowercase) or case-insensitively - NEVER `author.name`, which can silently match nothing.
- **Issue type** - `Bug`.

## Step 8 - Assemble the overview and get approval

ALWAYS produce and present the full overview, **irrespective of disposition** - file, comment-on-existing, duplicate (open or closed), refuted, or any no-action outcome all get one. Never skip or shorten it because the verdict is "duplicate, do not file"; a duplicate needs as clear a paper trail (crash/UID, assert+line, trigger, reduced testcase, dedup verdict + evidence chain, matrix, explicit disposition) as a filing, and it is persisted in the dir even when nothing is filed. **Reproduce the overview IN the chat response, in full, every time - including the CLI and MTR testcase blocks inline.** Do not reference "presented earlier", do not just persist it to a file, and never drop the testcase or point at the file instead of showing it (the recurring miss). See [[feedback_always_present_overview]].

Write two files into `<trial-dir>`:

- `log_jira_ticket.body` - the exact Jira description to submit (spliced body from steps 4 + 5 + 6).
- `log_jira_ticket.txt` - the human-review overview:

  ```
  Title       : <synthesized title>
  Project     : MDEV
  Issue type  : Bug
  Priority    : <priority>
  Affects     : <CS v1, v2, …>
  Affects ES  : <ES v1, v2, …>
  Fix Version : <v1, v2, …>   (newest branch dropped)
  Components  : <c1, c2>
  Labels      : <l1, l2>
  Assignee    : <Display Name> / <username> (<one-line reason: owning subsystem, or the precedent - e.g. "fixed the identical MDEV-NNNNN">)
  Related     : <https://jira.mariadb.org/browse/MDEV-…>, …   (link as "Relates" - your signoff, step 10)

  Duplicate check (step 3):
    String Scan : <verdict + any MDEV key>
    JQL hits    : <https://jira.mariadb.org/browse/MDEV-…   status   resolution   summary> … (or "none")
    Assessment  : <new | likely dup of https://jira.mariadb.org/browse/MDEV-xxxxx (why) | regression of fixed MDEV-xxxxx>

  ----- description (log_jira_ticket.body) -----
  <full body>
  ```

Present the overview to the user in this canonical layout (keep identical across sessions): a fields table (Title | Project/Type/Priority | Affects | Fix Version | Components | Labels), then the CLI and MTR testcases as separate full-width blocks (never side-by-side - it wraps lines), then the dedup verdict and the related-issues-to-signoff, then the two decisions: "approve to file?" and "which related links?". Render every referenced MDEV/MENT key (dedup hits, related candidates) as a full clickable `https://jira.mariadb.org/browse/<KEY>` URL, not a bare key, so the approver can click through. The Assignee line is presented as `Display Name / username (reason)` - the reason in parentheses is the owning subsystem OR the precedent (e.g. "fixed the identical MDEV-NNNNN"; prefer the latter when dedup found a truly-same-path issue, as its assignee/owner is the strongest signal). Never `(none)`, `suggest`, or a `signoff` qualifier; the signoff is the overall approval, not a per-line hedge. After filing, show the new ticket's URL the same way. Ask for approval. If ANYTHING changes after a presentation (further reduction, a version/label/component/assignee fix, a testcase or body edit), RE-PRESENT THE FULL overview from scratch - the complete fields table + both testcases + dedup + body summary - never just the delta or the fixed line. The approver must always see the entire current report in one place before approving.

**Gate:** explicit user approval.

## Step 9 - Submit

`~/jira` = `~/mariadb-qa/log_jira_ticket.sh`. Do NOT re-read the script to learn its flags - they are fixed and listed here.

**Modes:** default = create; `--whoami` (auth check); `--createmeta -p MDEV -t Bug` (required fields); `--comment KEY` (body via `-d`/`--description-file`); `--link KEY --relates OTHER [--link-type Relates|Duplicate|Blocks]`; `--edit KEY --affects-version X.Y …` (ADDITIVE version add to an existing issue, never replaces - use mainline X.Y).

**Create flags:** `-p MDEV` / `-t Bug` / `-s "<summary>"` / `--description-file <file>` (Jira wiki markup) / `--affects-version V` (CS Affects, repeatable) / `--es-version V` (Enterprise Affects -> `customfield_13204`, repeatable, SEPARATE from CS) / `--fix-version V` (repeatable) / `-c NAME` (component, repeatable) / `-l NAME` (label, repeatable) / `--priority NAME` / `--assignee USER` (Jira username, e.g. `psergei`) / `--dry-run` / `-y`.

**Auth:** PAT from `$JIRA_PAT` then `~/.config/mariadb-qa/jira.pat` (already set up). **Output on success:** `Created: MDEV-xxxxx` + URL - relay both. On HTTP error it prints Jira's `errors` block; fix the field and re-run.

**Confirmation - this is the gotcha:** after printing the payload the script reads `Enter` 3x from **`/dev/tty`** (NOT stdin), so it cannot be satisfied by a pipe. In an interactive terminal a human presses Enter 3x. In a non-interactive/agent shell there is no `/dev/tty`, so:
1. First run with `--dry-run` (no auth, no POST) and verify the payload (versions, fixVersions, `customfield_13204` ES, components, labels, priority).
2. Then submit with `-y` (skips the tty confirm). The user's explicit in-conversation approval of `log_jira_ticket.txt` (the Step 8 gate) IS the confirmation the tty prompt would otherwise capture - `-y` is correct ONLY after that approval, never before.

```bash
# 1) validate
~/jira -p MDEV -t Bug -s "<title>" --description-file <dir>/log_jira_ticket.body \
  --affects-version <v1> … --es-version <esv1> … --fix-version <v1> … \
  -c "<component>" -l "<label1>" -l "<label2>" --priority "<priority>" --assignee <username> --dry-run
# 2) submit (only after user approval; -y because no /dev/tty in an agent shell)
~/jira -p MDEV -t Bug -s "<title>" --description-file <dir>/log_jira_ticket.body \
  --affects-version <v1> … --es-version <esv1> … --fix-version <v1> … \
  -c "<component>" -l "<label1>" -l "<label2>" --priority "<priority>" --assignee <username> -y
```

Always pass `--assignee <username>` matching the `Assignee` shown in the approved `log_jira_ticket.txt` overview - the sign-off INCLUDES the assignee, so the filing must match it (do NOT file unassigned when an assignee was shown and approved). Resolve/confirm the username via `https://jira.mariadb.org/rest/api/2/user/search?username=<prefix>` before submit.

## Step 10 - Link related bugs (always propose for signoff)

The dedup (step 3) usually surfaces same-family issues that are NOT strict duplicates (same assert / adjacent code path, different feature). These are RELATED, not dups. ALWAYS propose the related set to the user for signoff first (it appears in the step 8 overview's `Related:` line) - never auto-link. Apply only the signed-off ones via the script (3x-confirm):

```bash
~/jira --link MDEV-xxxxx --relates MDEV-aaaaa --relates MDEV-bbbbb   # type defaults to "Relates"
```

`--link-type` can be `Relates` (default), `Duplicate`, `Blocks`, `PartOf`, etc. A confirmed duplicate would have been actioned in step 3 (not filed), so here the type is almost always `Relates`.

**Tracking-TODO link (do for every ticket filed in a session):** also link each filed ticket as **part of** the session's tracking TODO. ASK the user for the TODO key at the start of a filing session; do not assume it across sessions. Use `PartOf` (inward "is part of" / outward "includes"). DIRECTION (verified, counter-intuitive): the script sets `inwardIssue = --link key`, `outwardIssue = --relates`; the issue on `--relates` ends up "is part of" the issue on `--link`. So to get "MDEV is part of TODO" put the **TODO on `--link`** and the **MDEV on `--relates`** (NOT the reverse):

```bash
~/jira --link TODO-NNNN --relates MDEV-xxxxx --link-type PartOf -y   # "MDEV-xxxxx is part of TODO-NNNN"
```

Verify after: `GET /issue/MDEV-xxxxx?fields=issuelinks` - the PartOf link must show `inwardIssue=TODO-NNNN` (if it shows `outwardIssue=TODO-NNNN`, the direction is reversed - delete it via `DELETE /rest/api/2/issueLink/<id>` and recreate with TODO on `--link`).

## Step 11 - Register the bug and clean workdirs

With the `MDEV-xxxxx` key, register so the framework recognises future occurrences, then purge matching trials:

1. **`eb`** - write the CLI testcase (incl. any `# mysqld options required for replay:` header) to `~/mariadb-qa/BUGS/MDEV-xxxxx.sql`, one unbroken line per statement, THEN `git add` it - the vi-based `eb` can't run unattended, but its key effect is staging the testcase into the repo, so replicate that: `cd ~/mariadb-qa/BUGS && git add MDEV-xxxxx.sql` (`git add` is allowed; only `git commit`/`push`/`rm` are denied). Do not write the file and leave it untracked. For an **error-message** bug (not crash/assert/SAN), append after each testcase variant the observed result: `#CLI: <client-visible error or output>` and `#ERR: <error-log line, or "- (no error)">` (see `~/mariadb-qa/BUGS/MDEV-34936.sql`). Crash/assert/SAN bugs need no `#CLI`/`#ERR`.
2. **`kb`** - INSERT each non-SAN crash/error UniqueID into `~/mariadb-qa/known_bugs.strings` **at the correct section, NOT appended at EOF** (the file ENDS with the `###### FIXED BUGS ######` section; appending there hides the entry from the active filters - a recurring mistake). Placement by class:
   - **crash/assert** UniqueIDs (`SIGSEGV|…` / `<assert>|SIGABRT|…`, pipe-delimited) → immediately AFTER the `##### CURRENT BUGS (Search key: Mac) #####` header (grep `'Mac'`); newest go right behind that line.
   - **typed error-string** entries → their own top section, NOT the Mac section: `GOT_ERROR|…` in the GOT_ERROR block, `INNODB_ERROR|…` in the INNODB_ERROR block, `MARIADB_ERROR_CODE|…` in the MARIADB_ERROR_CODE block, `GOT_FATAL_ERROR|…` by the GOT_FATAL line.

   One per line; `## MDEV-xxxxx` marker **column-aligned so `##` starts at char 176** (pad the UniqueID to width 175; if ≥175 chars use a single space before `##`). No leading `#` (that marks a fixed/filtered entry); the parser keys on `## MDEV-`. (NB: `UID` is a readonly shell var - use another name.)

   `known_bugs.strings` / `.SAN` are load-bearing framework files - edit them with CARE and STABILITY: always back up, generate into a SEPARATE file, VERIFY, and swap only on pass. Never blind `>>` append, never edit in place. These files are git-tracked, so the definitive final check is **`git diff known_bugs.strings`** (or `.SAN`): confirm the diff is EXACTLY the intended change - only added (`+`) lines for an insert, or matched `-`/`+` lines at the old/new spots for a relocation - and nothing else moved or reformatted. If `git diff` shows anything unexpected, restore from the backup and retry.

   ```bash
   U='<UniqueID>'; F=~/mariadb-qa/known_bugs.strings
   cp "$F" "$F.bak.$$"                                     # 1) back up first
   if [ ${#U} -lt 175 ]; then L=$(printf '%-175s## MDEV-xxxxx' "$U"); else L="$U ## MDEV-xxxxx"; fi
   # 2) build the new file FROM THE BACKUP into a new name (crash/assert -> after the Mac header;
   #    for a typed-error entry change the anchor to the GOT_ERROR / INNODB_ERROR / MARIADB_ERROR_CODE block)
   awk -v l="$L" '{print} /##### CURRENT BUGS \(Search key: Mac\) #####/{print l}' "$F.bak.$$" > "$F.new.$$"
   # 3) VERIFY before swap: exactly +1 line, nothing removed/changed, entry present
   ok=1
   [ "$(wc -l <"$F.new.$$")" -eq "$(( $(wc -l <"$F.bak.$$") + 1 ))" ] || ok=0
   diff <(sort "$F.bak.$$") <(sort "$F.new.$$") | grep -q '^< ' && ok=0   # any removed/changed line -> abort
   grep -qF "$L" "$F.new.$$" || ok=0
   # 4) swap ONLY on pass; else leave F untouched and keep .new for inspection
   if [ "$ok" = 1 ]; then mv "$F.new.$$" "$F"; echo "OK: inserted"; else echo "ABORT: verify failed; $F unchanged"; fi
   ```
3. **`kba`** - INSERT each SAN UniqueID (`ASAN|…` / `UBSAN|…` / `MSAN|…`) into `~/mariadb-qa/known_bugs.strings.SAN` AFTER its own `##### CURRENT BUGS (Search key: Mac) #####` header (same anchor, same column-176 `##` alignment; `F=~/mariadb-qa/known_bugs.strings.SAN`), NEVER at EOF (its tail is the FIXED BUGS section too). Use kb and/or kba per which UniqueID classes the bug produced.
4. **`ca`** - clean all workdirs of now-known trials (after kb/kba):

   ```bash
   screen -dmS clean_all bash -c 'cd /data && ./clean_all'
   ```

**Gate:** `eb` written AND `git add`ed, `kb` and/or `kba` updated (with the `## MDEV` marker column-aligned - see below), `ca` launched. The testcase is staged automatically (eb behavior); surface the staged `BUGS/MDEV-xxxxx.sql` and the modified `known_bugs.strings`/`.SAN` for the user to commit - never `git commit`/`push` yourself.

## End-of-turn report (tickboxes)

```
✅ most-reduced testcase selected + gated
✅ hand-reduced + tcp, repro re-verified (UniqueID <…>)
✅ dedup early (String Scan + frame + assert searches) → new | dup-menu shown
✅ ~/b report generated (+ ~/bs / ~/br as applicable)
✅ SAN stacks/Setup/matrix spliced into body  (or: no SAN issue)
✅ MTR testcase verified + folded in (or: CLI/MTR compatible)
✅ Affects/Fix/components/labels/priority derived + validated
✅ related issues captured + proposed for signoff (step 10)
✅ log_jira_ticket.txt written, approval requested
⏳ submit pending approval   (or: ✅ filed MDEV-xxxxx <url>)
   then: ✅ related links applied, eb + kb/kba registered, ca clean screen launched
```

## Related

- `~/mariadb-qa/log_jira_ticket.sh` - the filing/commenting script (PAT auth, 3x confirm). See `[[reference_log_jira_ticket]]`.
- House style and framework references live in ambient memory (Jira markup, MTR, reducer `_out` chain, gendirs sweep).
