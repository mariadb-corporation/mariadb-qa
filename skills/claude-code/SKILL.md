---
name: claude-code
description: How to get authoritative information about Claude Code itself (the CLI, headless/print mode, SDK, settings, hooks, slash commands, MCP) and how to run it non-interactively from cron. Two sources of truth - the internal claude-code-guide agent and the online docs at code.claude.com/docs - plus a verified headless quick-reference. Use when a task needs Claude Code feature details, when automating Claude Code from a script/cron, or before answering any "can Claude Code ..." question (do not answer those from memory).
claude: please note - this skill exists in a public repo and should only be updated with specific written signoff by the updater
---

# claude-code

Reference for getting correct Claude Code information and for running Claude Code headless (e.g. from cron). Do NOT answer Claude Code feature questions from memory - the CLI changes fast. Use the two sources below, and verify flags against the local binary.

## 1. Authoritative sources (use these, not memory)

- Internal `claude-code-guide` agent - the primary source. It can read the local install and the live docs. Invoke via the Agent tool:
  - `Agent(subagent_type="claude-code-guide", prompt="<specific question>")`
  - Best for: feature questions, flag behavior, SDK usage, "how do I ...".
- Online docs - canonical host is `code.claude.com/docs/en/` (`docs.claude.com/...` 301-redirects here):
  - Index of all pages (machine-readable): `https://code.claude.com/docs/llms.txt`
  - Overview: `https://code.claude.com/docs/en/overview`
  - Headless / programmatic (`-p`): `https://code.claude.com/docs/en/headless.md`
  - CLI reference (all flags): `https://code.claude.com/docs/en/cli-reference`
  - Settings / config: `https://code.claude.com/docs/en/settings`
  - Permission modes: `https://code.claude.com/docs/en/permission-modes`
  - Hooks: `https://code.claude.com/docs/en/hooks`
  - Skills: `https://code.claude.com/docs/en/skills`
  - Agent SDK (Python/TS): `https://platform.claude.com/docs/en/agent-sdk/overview`
  - Fetch a `.md` page with WebFetch when you need current detail.

## 2. Always verify flags locally

Flags and choices drift by version. Confirm before relying on them:

```bash
claude --version          # this box: see local install at ~/.local/bin/claude
claude --help | grep -- --<flag>
```

Verified on the local install (`claude 2.1.197`): `-p/--print`, `--bare`, `--output-format` (`text` default | `json` | `stream-json`), `--allowedTools`/`--allowed-tools`, `--permission-mode` (`acceptEdits|auto|bypassPermissions|default`), `--model`, `--append-system-prompt[-file]`, `--settings`, `--dangerously-skip-permissions`, `--continue`, `--resume`. There is no `--max-turns` in this version.

## 3. Headless / cron quick-reference

```bash
claude -p "<prompt>"                         # non-interactive, prints result and exits
claude --bare -p "<prompt>" --allowedTools "Read,Bash"   # CI/cron: skip auto-discovery, pre-approve tools
claude -p "<prompt>" --output-format json | jq -r '.result'   # extract just the text result
```

- `--bare` skips hooks, skills, plugins, MCP, auto-memory, and CLAUDE.md - predictable for scripts. Recommended for cron (will become the `-p` default).
- `--allowedTools "Read,Bash"` pre-approves tools so the run never blocks on a prompt. Uses permission-rule syntax, e.g. `Bash(git diff *)`.
- `--output-format json` payload includes `total_cost_usd` and a per-model cost breakdown; the text answer is in `.result`.
- User skills work in `-p`: put `/skill-name` in the prompt string (NOT available with `--bare`, which skips skill discovery). Interactive commands (`/login`, `/config` dialogs) do not work in `-p`.

### Auth in headless (no interactive login)

- `ANTHROPIC_API_KEY` env var - required when using `--bare` (bare mode skips OAuth and keychain reads). API key from `https://platform.claude.com`.
- `CLAUDE_CODE_OAUTH_TOKEN` - long-lived token from running `claude setup-token` once interactively; works WITHOUT `--bare` (cannot be combined with `--bare`).
- `apiKeyHelper` in `--settings` JSON - for rotating credentials.

### Cron environment (cron has a minimal env)

```cron
# minute hour day month weekday
0 4 * * 1,3,5  /home/youruser/path/to/task.sh >> /tmp/task.log 2>&1
```

```bash
#!/bin/bash
set -euo pipefail
export PATH="/home/youruser/.local/bin:/usr/local/bin:/usr/bin:/bin"
export HOME="/home/youruser"
export ANTHROPIC_API_KEY="..."        # or CLAUDE_CODE_OAUTH_TOKEN without --bare
out=$(claude --bare -p "<prompt>" --allowedTools "Read,Bash" --output-format json)
summary=$(printf '%s' "$out" | jq -r '.result')
# deliver, e.g. via the /email skill:
python3 ~/.claude/skills/email/send_email.py --to you@example.com --subject "..." --body "$summary"
```

- Set `PATH` (cron strips it; the binary is at `~/.local/bin/claude`), `HOME`, and the auth env var explicitly.
- Background Bash tasks Claude starts are killed ~5s after the result; background subagents/workflows are waited on (capped at 10 min, tune with `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS`).
- Piped stdin is capped at 10 MB; for larger input, write a file and reference its path.

## Note

Most cron tasks need NO AI call - deterministic scripts (curl/jq/python) are cheaper and cannot hallucinate. Reach for headless `claude -p` only when the task genuinely needs natural-language generation or judgement.
