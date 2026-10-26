---
name: mtr-failure-create-bug
description: Given an MTR test name (e.g. binlog.binlog_check_constraint_checks_flag), pull its buildbot failure history with build_mtr_test_failures_report.py, filter to rows whose failure_text is textually similar (default 60%) to a reference failure text, restrict to real release branches (VERSION_REGEX ^(((10|11|12|13)\.\d+)|main)$), dedupe to one representative row per branch, check jira.mariadb.org for an existing open ticket (phrase-quoted JQL, not the noisy tokenized default), and - only after explicit user confirmation of the exact summary/description - file or update the MDEV bug via ~/jira. Use when asked to check whether a failing MTR test already has a Jira bug, or to file one for a test failure seen in buildbot.
claude: please note - this skill exists in a public repo and should only be updated with specific written signoff by the updater. Keep skills/README.md (the skills index) in sync when any skill is added, renamed, removed, or its description changes.
---

# mtr-failure-create-bug

Turns a buildbot MTR test failure into a dedup-checked, jira.mariadb.org MDEV bug report. AI-driven: the similarity threshold, the release-branch filter, and the summary/description wording all need judgement, not a fixed script - but the data pull and the filing both go through the same two tools every time.

## Inputs

- `<test-name>` - suite-qualified MTR test, e.g. `binlog.binlog_check_constraint_checks_flag`. Required.
- `<reference failure text>` - the exact failure text to match against (usually pasted by the user, or copied from a buildbot log). If the user gives none, use the most common `failure_text` the report returns for that test.
- `<similarity threshold>` - defaults to 60% if the user does not say otherwise.
- A date window - defaults to the last 7 days (`--from-date <today>`, `--until-date <today-7>`) if the user gives none.

## Pre-flight - Jira PAT

The Jira check and any filing need a Personal Access Token for jira.mariadb.org, read from `$JIRA_PAT` or `~/.config/mariadb-qa/jira.pat` (this is `~/jira`'s / `log_jira_ticket.sh`'s own convention - do not use a different env var or path).

```bash
[ -n "$JIRA_PAT" ] || [ -s ~/.config/mariadb-qa/jira.pat ] || echo "NO PAT"
```

If missing, STOP and tell the user: log in to https://jira.mariadb.org -> avatar (top right) -> Profile -> Personal Access Tokens -> Create token -> copy it (shown once), then:

```bash
mkdir -p ~/.config/mariadb-qa && (umask 077; printf '%s\n' '<token>' > ~/.config/mariadb-qa/jira.pat)
```

Verify with `~/jira --whoami`.

**Do not use the Atlassian MCP connector for this.** It only reaches whichever Cloud site (`mariadbcorp.atlassian.net` / `ggsystems.atlassian.net`) it is bound to - never `jira.mariadb.org`, which is a separate Server/DC instance. Always talk to jira.mariadb.org with `~/jira` or a direct `curl` against `https://jira.mariadb.org/rest/api/2/...` using the PAT as a Bearer token.

## Tools used

| Tool | Role |
|---|---|
| `~/mariadb-qa/build_mtr_test_failures_report.py` | pulls buildbot failure rows for one test name, paging backwards through the cross-reference API |
| `~/jira` (`log_jira_ticket.sh`) | files the MDEV ticket (`-s`/`-d`/`--affects-version`, repeatable), `--whoami`, `--createmeta`; no summary/description edit on an existing issue (see Step 5b) |
| direct `curl` to `https://jira.mariadb.org/rest/api/2` | the dedup search (`/search?jql=...`) and, when needed, a description/summary `PUT` after filing |

## Step 1 - Pull the failure data

```bash
cd ~/mariadb-qa
python3 ./build_mtr_test_failures_report.py \
  --test-name '<test-name>' \
  --from-date <newest-date> --until-date <oldest-date> \
  --format json
```

This prints a short summary to stdout and writes the full per-run rows to `test_failures_<test-name>_<until-date>.json` in the cwd (each row: `dt`, `builder_name`, `commit`, `branch`, `test_name`, `test_variant`, `info_text`, `failure_text`). Read that JSON file, not the stdout summary - the stdout block only shows one sample `failure_text` per branch, and the goal here is every row.

Do not hand-roll a buildbot API call - this script already pages backwards in 200-row chunks and is the framework's one way to pull this data.

## Step 2 - Filter by similarity to the reference text

Use Python's stdlib `difflib.SequenceMatcher` ratio (not a fuzzy library, not a hand-rolled diff) between each row's stripped `failure_text` and the stripped reference text; keep rows at or above the threshold (default 0.60):

```python
from difflib import SequenceMatcher
def sim(a, b):
    return SequenceMatcher(None, a.strip(), b.strip()).ratio()
```

If the user gave no reference text, pick the single most frequent `failure_text` string in the pulled rows and use that as the reference (say so).

Report the match rate (`N of M rows matched`) and how many *distinct* failure_text strings survived the filter - a single distinct string surviving across many rows is a strong signal it is one root cause, not several unrelated failures that happen to share a keyword.

## Step 3 - Restrict to release branches

Buildbot branch names include PR heads (`refs/pull/NNNN/head`), preview/bb-* one-off branches, and real release branches. Unless the user asks to keep every branch, filter to real release branches with:

```python
import re
VERSION_REGEX = re.compile(r"^(((10|11|12|13)\.\d+)|main)$")
```

Apply this AFTER the similarity filter (Step 2), on the surviving rows' `branch` field. Note in the summary which branches were excluded (PR/preview/bb-*) and why.

## Step 4 - One representative row per branch

Per branch, keep only the row with the latest `dt` (most recent occurrence). Carry: `branch`, `builder_name`, `dt`, `commit`, `test_variant`. This is the table that goes into the ticket - never dump all matching rows into a Jira description, one clean row per branch is the deliverable.

**Default to one row per branch.** If asked for something else (a single overall branch, every raw row, etc.) do that instead - always echo back what scope you understood before building the draft.

## Step 5 - Check jira.mariadb.org for an existing ticket

**JQL's `text ~` operator tokenizes on underscores and dots, then behaves like an OR across the tokens** - `text ~ "binlog_check_constraint_checks_flag"` (no inner quotes) returns dozens of unrelated tickets that merely share a common word (`check`, `flag`, `constraint`, ...). This is a recurring trap: never trust an unquoted or single-quoted `text ~` search as evidence of "no existing ticket".

The reliable form is an **exact-phrase** query - wrap the term in escaped double quotes so JQL performs a phrase match instead of a token OR:

```bash
PAT="$(cat ~/.config/mariadb-qa/jira.pat 2>/dev/null || echo "$JIRA_PAT")"
curl -s -G 'https://jira.mariadb.org/rest/api/2/search' \
  --data-urlencode 'jql=text ~ "\"<test-name>\""' \
  --data-urlencode 'fields=summary,status,resolution,created' \
  --data-urlencode 'maxResults=50' \
  --header "Authorization: Bearer $PAT"
```

Run this for:
1. The exact test name (`binlog.binlog_check_constraint_checks_flag`), and again without the suite prefix if the first returns nothing.
2. A short, distinctive fragment of the reference failure text (e.g. `SERVER_MYPORT_2` or the specific error string), phrase-quoted the same way - some failures get reported without the test name typed literally.

A `total` of 0 across both is authoritative: no ticket currently mentions this test/error as literal text. Any hit found this way should still be read (fetch the issue, compare its description/error text to the reference with the Step 2 similarity function) before calling it a duplicate - a shared fragment is not automatically the same bug.

**If a live (non-closed) match is found:** stop, report it, and do not file a new ticket. Follow `jira-ticket`'s duplicate-handling menu (comment / extend versions / skip) if the user wants to act on it.

**If nothing is found:** proceed to Step 6.

## Step 6 - Draft the ticket

- **Summary**: name the test and the symptom only - no branch names, no builder names (both go in the description table). E.g. `<test-name> fails: <short symptom, e.g. the distinctive line from failure_text>`.
- **Affects Version/s**: the release branches from Step 4, as exact version names (validate each exists first: `GET /rest/api/2/issue/createmeta?projectKeys=MDEV&issuetypeNames=Bug&expand=projects.issuetypes.fields`, read `fields.versions.allowedValues`; mainline `X.Y` form, e.g. `10.11`, `11.4`, `11.8` - not `10.11.x`).
- **Component/s**: always `Tests, MTR` (the single MDEV component covering test failures - note the literal comma in its name; there is no separate "Tests" and "MTR" component, so pass it as one `--component` value, not two).
- **Description** (Jira wiki markup, per `~/mariadb-qa/skills/_shared/jira_markup.md`):
  - One sentence stating the test and which release branches it fails on.
  - `h3. Build Run Info` - just the `||Branch||Builder name||Date||Commit||Variant||` table, one row per branch from Step 4. No lead-in line naming the invocation/filters.
  - `h3. Failure text` - the `{noformat}` block, verbatim, noting if it is identical across all rows.
  - `h3. Analysis` - one paragraph. If every matching row shares a single builder, say so explicitly and flag it as a likely builder/environment-level issue rather than a per-branch code regression (a real code regression would not spare every other builder testing the same branches). If multiple builders are affected, say that instead - it points at the branch/test itself.
  - End with `Created via the mtr-failure-create-bug skill.`

**Never file before the user has approved the exact summary, description, Affects Version list, and Component/s.** Show the full draft (use `AskUserQuestion` with the rendered description in the preview) and wait for confirmation, exactly as for any other Jira filing in this repo. Re-show the draft after every requested edit - do not guess at what "fix this" means without echoing the new draft back first.

## Step 7 - File it

```bash
~/jira -p MDEV -t Bug \
  -s '<approved summary>' \
  -d '<approved description>' \
  --affects-version <branch1> [--affects-version <branch2> ...] \
  --component 'Tests, MTR'
```

Read back the printed key + URL. `~/jira` handles the MDEV create-screen quirks (e.g. `reporter` is not on that screen and must not be set) - do not reimplement the POST by hand for a first filing.

### Step 7a - Editing after filing

`~/jira --edit <KEY>` only adds Affects/Fix versions and labels - it does **not** change summary or description. If the user asks for a summary/description change on an already-filed ticket (rare - get it right in Step 6 instead), that needs a direct `PUT`:

```bash
PAT="$(cat ~/.config/mariadb-qa/jira.pat 2>/dev/null || echo "$JIRA_PAT")"
curl -s --show-error -X PUT \
  --header "Authorization: Bearer $PAT" \
  --header 'Content-Type: application/json' \
  --data @body.json \
  "https://jira.mariadb.org/rest/api/2/issue/<KEY>" -w '\nHTTP_STATUS=%{http_code}\n'
```

`body.json` is `{"fields": {"summary": "...", "description": "...", "versions": [{"name": "10.11"}, ...]}}` - re-fetch the live issue first if the user may have hand-edited it since filing, so the PUT does not clobber their edit.

## Worked example

MDEV-41308: `binlog.binlog_check_constraint_checks_flag` was failing in buildbot with `include/master-slave.inc\nBug in test case: '$SERVER_MYPORT_2' not initialized. Check the test's .cnf file.`. The report pulled 195 rows in the window; all 195 matched the reference text at 100% similarity (one distinct string); restricting to release branches (`VERSION_REGEX`) cut that to 10.11/11.4/11.8, all on builder `amd64-msan-clang-22`; the phrase-quoted Jira search found nothing existing; the filed ticket named the symptom in the summary, carried a `||Branch||Builder name||Date||Commit||Variant||` table, and set Affects Version/s to 10.11/11.4/11.8 - with the single-builder concentration called out in the Analysis section as pointing at an environment issue rather than a per-branch regression.
