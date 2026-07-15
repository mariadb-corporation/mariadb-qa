# mariadb-qa skills

Claude Code skills used in day-to-day MariaDB QA work. Each skill is a directory with a
`SKILL.md` (name, description, and procedure). Claude Code loads a skill on demand when a
task matches its description.

## Skills

- `claude-basedir-fix-copy-setup` - copy a `/test` basedir to `/tmp` and re-bake the
  path-baked helpers so the copy runs as a standalone server without touching the original.
- `claude-code` - how to get authoritative Claude Code information and how to run Claude
  Code headless (for example from cron).
- `email` - send a plain-text email from this box via direct-to-MX SMTP, no local MTA or
  credentials.
- `fix-diff` - generate a `fix.diff` for a code change from an edit cycle in a `/tmp` copy
  of the source tree.
- `jira-comment` - draft a short, paste-ready Jira comment for a MariaDB ticket in Jira
  wiki markup.
- `jira-ticket` - file a reduced pquery trial as a public MariaDB bug: reduce further,
  dedup against Jira, generate the report, craft the MTR testcase, derive the fields, and
  file after approval.
- `loop-screens-cleanup` - sweep the reducer screens and end the finished ones, reaping
  each ended trial's processes and its `/dev/shm` workdir; leave screens still reducing.
- `mtr_testcase` - craft and verify a `.test` from a CLI/pquery repro: engine guards,
  `--error` coverage, reverse-gating, and run-in-place verification.
- `qa-build` - build a patched MariaDB binary from a `/tmp` copy of the source tree using
  the `build_mdpsms_*.sh` variants.
- `verify-fix` - end-to-end fix verification: draft the diff, build the fix, run the test
  across each affected version, record the results.

## Shared and support files

- `_shared/jira_markup.md` - Jira wiki-markup rules shared by the Jira-bound skills.
- `_check/public_safety_scan.sh` - blocks generic secrets and private paths from reaching
  this public repo. `linkit` wires it in via the repo's `hooks/` dir (`core.hooksPath`):
  `pre-commit` scans the staged files, `pre-push` re-scans the files in the commits being
  pushed. Run it by hand with `bash skills/_check/public_safety_scan.sh` (staged files) or
  pass paths. Private, box-specific patterns belong in
  `~/.config/mariadb-qa/public_safety_denylist` (seeded by `linkit`, never committed).

## Install

Place this repo at `~/mariadb-qa` - the framework tooling and the skills' cross-references
assume that location. Run `~/mariadb-qa/linkit`: when `~/.claude` exists it symlinks every
skill directory here (each directory with a `SKILL.md`) into `~/.claude/skills/`, where
Claude Code discovers personal skills, and it prunes broken links from renamed or removed
skills. It never touches skill directories it does not manage. Rerun `linkit` after adding
a skill.

`_shared` and `_check` are not skills (no `SKILL.md`), so `linkit` skips them; skills read
them from their repo path (`~/mariadb-qa/skills/_shared/...`).

## Prerequisites

The build, test, and reducer skills (`qa-build`, `verify-fix`, `fix-diff`,
`claude-basedir-fix-copy-setup`, `mtr_testcase`, `loop-screens-cleanup`, `jira-ticket`)
assume the mariadb-qa framework is installed:

- source trees under `/test/<ver>` and built basedirs under `/test/`,
- `~/st` (`startup.sh`) to bake the per-basedir helpers,
- `build_mdpsms_*.sh` build scripts and the `ba` / `bas` bashrc aliases,
- `gendirs.sh` to enumerate basedirs,
- `/data/TARS` for tarball storage,
- the reducer stack (`reducercpp`, `~/loop_screens*`, `~/sr`, `/data/<workdir>` trials) for
  `loop-screens-cleanup`,
- a jira.mariadb.org Personal Access Token for `jira-ticket` (`$JIRA_PAT` or
  `~/.config/mariadb-qa/jira.pat`; the skill explains how to get one).

The `email`, `claude-code`, and `jira-comment` skills are standalone and need none of the
above.
