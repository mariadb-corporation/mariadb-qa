# Claude Code status bar with the session meter: standalone install

The status bar and the session meter are part of mariadb-qa. They also work without it. This page installs them on their own: four Python files in one folder, and one entry in the Claude Code settings.

```
~/project abc123de 235k 🟢12 5h: 25% 13:10 wk: 23% 07:00 Fri o55-m ↑1.2M ↓84k ↻96% my-session 11:02
```

From left to right, the bar shows the folder, the session id, the context size, the session meter, the usage against the 5-hour limit and the weekly limit with their reset times, the model and the effort, the tokens in and out with the share of the input that came from the cache, the session name and the time. When you swap logins with [claude_accounts.md](claude_accounts.md), the account in use follows the time: `t1` for `~/claude_teams1`, `ent` for `~/claude_ent`.

The session meter is one number for how the session is going: 0 is a smooth session, 100 is a rough one. [claude/session_meter/README.md](claude/session_meter/README.md) describes what it counts and what the marks mean.

## Requirements

Claude Code, Python 3.8 or later, and curl. Tested on Linux only. Both status bar scripts use calls that Python offers on Unix only, so they do not run under Python for Windows.

## 1. Get the files

```bash
dir=~/claude_statusline
url=https://raw.githubusercontent.com/mariadb-corporation/mariadb-qa/master
for f in claude_statusline.py claude_statusline_teams.py \
    claude/session_meter/session_meter.py claude/session_meter/session_meter_hook.py; do
  curl -fsS --create-dirs -o "$dir/$f" "$url/$f" || echo "FAILED: $f"
done
```

Another folder works as well. Keep the layout: each status bar script looks for the meter in `claude/session_meter` beside itself.

## 2. Turn the status bar on

There are two status bars. They differ in one part of the line:

| Script | That part shows | Use it with |
|---|---|---|
| `claude_statusline_teams.py` | The usage against the 5-hour limit and the weekly limit. | A plan that has those limits, such as the Team plan. |
| `claude_statusline.py` | The cost of the session. | Any other plan, such as the Enterprise plan. |

Add one of them to `~/.claude/settings.json`. When the file holds other settings, put the `statusLine` entry beside them:

```json
{
  "statusLine": {
    "type": "command",
    "command": "python3 ~/claude_statusline/claude_statusline_teams.py",
    "refreshInterval": 30
  }
}
```

For the other status bar, change the script name in the command. Then start a new Claude Code session. The bar is at the bottom, and the meter shows as `🟢0`.

## 3. Turn the prompt hook on

This step is optional. The hook shows the meter to Claude as well: each time you send a prompt while the reading is yellow or worse, it puts one line into the session, so that Claude works more carefully. Add it to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 ~/claude_statusline/claude/session_meter/session_meter_hook.py",
            "timeout": 10,
            "statusMessage": "Reading the session meter"
          }
        ]
      }
    ]
  }
}
```

## When the bar does not show

- Claude Code runs a status bar only in a folder that you trust. Answer the trust question for the folder, then start the session again.
- Run the script of your command by hand. A working script prints a line that ends with the time or the account, and a fault prints an error:

```bash
echo '{}' | python3 ~/claude_statusline/claude_statusline_teams.py
```

- When the bar shows and the meter does not, run the meter by hand. It prints the path of its settings file:

```bash
python3 ~/claude_statusline/claude/session_meter/session_meter.py --settings
```

## Your own settings

Your own words and switches for the meter go in `~/.config/mariadb-qa/session_meter.json`. The folder has that name with and without mariadb-qa. The file is optional, and "Your own settings" in the README of the meter describes it.

## What stays on your machine

The meter and `claude_statusline.py` send nothing anywhere. `claude_statusline_teams.py` asks `api.anthropic.com` for the usage of the account, at most once in 5 minutes, with the login that Claude Code keeps in `~/.claude`. That request uses no tokens.

| Place | What it holds |
|---|---|
| `~/claude_statusline/` | The scripts. |
| `~/.cache/claude-session-meter/` | The counts of the meter for each session. No message text. |
| `/tmp/.claude_tokens_io.*` | The token counts of each session. |
| `/tmp/.claude_session_ids.*` | The session id of each Claude Code process. |
| `/tmp/.claude_usage_teams.*`, `/tmp/.claude_limits_teams.*` | The usage numbers. `claude_statusline_teams.py` only. |

## Update and remove

To update, run step 1 again. To remove, take the `statusLine` entry and the hook out of `~/.claude/settings.json`, and delete the places in the table.
