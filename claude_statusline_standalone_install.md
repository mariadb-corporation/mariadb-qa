# Claude Code status bar with the session meter: standalone install

The status bar and the session meter are part of mariadb-qa. They also work without it. This page installs them on their own, in one folder, and turns them on in the Claude Code settings.

```
~/project abc123de 235k 🟢12 5h: 25% 13:10 wk: 23% 07:00 f5: 3%    Fri o55-m ↑1.2M ↓84k ↻96% my-session 11:02
```

| Part | Looks like | What it shows |
|---|---|---|
| Folder | `~/project` | The folder of the session. |
| Session id | `abc123de` | The start of the session id. |
| Context | `235k` | The size of the context. |
| Session meter | `🟢12` | How the session is going, from 0 to 100. See [How the meter works](#how-the-meter-works). |
| Usage | `5h: 25% 13:10` | The share of the 5-hour limit in use, and the time it resets. Each band fills as the use grows, and turns yellow and then red near the limit. |
| | `wk: 23% 07:00` | The same for the weekly limit. |
| | `f5: 3%    Fri` | The weekly limit of one model, such as Fable, when the plan has one. The day at the end is the day of the weekly reset. |
| Model and effort | `o55-m` | Opus 5.5 at max effort. Green at max effort. Red below xhigh effort, or on an older model. |
| Tokens | `↑1.2M ↓84k ↻96%` | The tokens in and out, and the share of the input that came from the cache. |
| Session name | `my-session` | The name of the session, when it has one. |
| Time | `11:02` | The time. |
| Account | `t1` | The account in use, when you swap logins with [claude_accounts.md](claude_accounts.md): `t1` for `~/claude_teams1`, `ent` for `~/claude_ent`. |

The other status bar, `claude_statusline.py`, shows the cost of the session in the place of the usage bands, such as `$1.23`.

## Install with Claude Code

Paste this prompt into Claude Code:

```
Fetch https://raw.githubusercontent.com/mariadb-corporation/mariadb-qa/master/claude_statusline_standalone_install.md with curl and follow it
```

Claude runs the steps below. To install by hand, run them yourself.

## Requirements

Claude Code, Python 3.8 or later, and curl. Tested on Linux and on Windows 11 (Python 3.14). On Windows the status bars use the user name and the temp folder in place of `os.getuid()` and `/tmp`, and the meter writes UTF-8 to the console.

On Windows, `python3` may be the Microsoft Store alias, which fails when Claude Code runs the hook or the status bar. Use the full path to a real Python executable in the `command` entries of `settings.json`, for example `"C:/Users/<you>/AppData/Local/Python/.../python.exe"`.

## 1. Get the files

```bash
dir=~/claude_statusline
url=https://raw.githubusercontent.com/mariadb-corporation/mariadb-qa/master
for f in claude_statusline.py claude_statusline_teams.py claude/session_meter/README.md \
    claude/session_meter/session_meter.py claude/session_meter/session_meter_hook.py; do
  curl -fsS --create-dirs -o "$dir/$f" "$url/$f" || echo "FAILED: $f"
done
```

Each status bar script looks for the meter in `claude/session_meter` beside itself, so keep this layout. Another folder works as well, when step 3 names it too.

## 2. Pick the status bar

The two status bars differ in one part of the line:

| Script | That part shows | Use it with |
|---|---|---|
| `claude_statusline_teams.py` | The usage against the 5-hour limit and the weekly limit. | A plan that has those limits, such as the Team plan. |
| `claude_statusline.py` | The cost of the session. | Any other plan, such as the Enterprise plan. |

`claude auth status` shows the plan of the login in use, as `subscriptionType`.

## 3. Turn them on

The status bar is one entry in `~/.claude/settings.json`. `refreshInterval` redraws the bar every 30 seconds, so the time and the usage stay current while the session waits:

```json
"statusLine": {
  "type": "command",
  "command": "python3 ~/claude_statusline/claude_statusline_teams.py",
  "refreshInterval": 30
}
```

The prompt hook is optional. It shows the meter to Claude as well. Each time you send a prompt while the reading is yellow or worse, it puts one line into the session, so that Claude works more carefully:

```
session meter 41 🟠 | user corrections 12, tool errors 6 | take smaller steps, and check each claim before you state it
```

This script adds both to `~/.claude/settings.json`, and keeps all other settings. Set `bar` to the script from step 2. Set `hook` to `no` to leave the hook out. When the file has a status bar already, this one takes its place. A second run changes nothing.

```bash
bar=claude_statusline_teams.py
hook=yes
python3 - "$bar" "$hook" <<'EOF'
import json, os, sys, tempfile
bar, hook = sys.argv[1], sys.argv[2] == 'yes'
path = os.path.realpath(os.path.expanduser('~/.claude/settings.json'))
data = json.load(open(path, encoding='utf-8-sig')) if os.path.exists(path) else {}
before = json.dumps(data)
data['statusLine'] = {'type': 'command', 'command': 'python3 ~/claude_statusline/' + bar,
                      'refreshInterval': 30}
if hook:
  new = {'type': 'command',
         'command': 'python3 ~/claude_statusline/claude/session_meter/session_meter_hook.py',
         'timeout': 10, 'statusMessage': 'Reading the session meter'}
  groups = data.setdefault('hooks', {}).setdefault('UserPromptSubmit', [])
  # the hook of an earlier run, also one from another folder
  mine = [h for g in groups for h in g.get('hooks', []) if 'session_meter_hook.py' in h.get('command', '')]
  for h in mine:
    h.update(new)
  if not mine:
    groups.append({'hooks': [new]})
if json.dumps(data) != before:
  os.makedirs(os.path.dirname(path), exist_ok=True)
  fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
  with os.fdopen(fd, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
  os.replace(tmp, path)
print(json.dumps({k: data[k] for k in ('statusLine', 'hooks') if k in data}, indent=2, ensure_ascii=False))
EOF
```

Then start a new Claude Code session. The bar is at the bottom, and the meter shows as `🟢0`.

## How the meter works

A session can go off track: calls fail, the same call runs twice, you correct Claude more often, and the replies hold more apologies and filler. The meter reads the transcript of the session on your machine, counts those signs, and gives one number from 0 to 100. Recent events count most, and praise lowers the number. The bands are fitted to real sessions labeled fine, friction or failed.

| Mark | Reading | What to do |
|---|---|---|
| 🟢 | 0 to 19 | Carry on. |
| 🟡 | 20 to 34 | Read the request again before you act. |
| 🟠 | 35 to 54 | Take smaller steps, and check each claim. |
| 🔴 | 55 and up | Stop new work, write a handover file, and start a fresh session. |

A high reading does not say who or what is at fault. It says that the session takes more steering than usual, and that a fresh session may be quicker.

The report of the meter shows which parts make up the reading. Put the session id from the bar in place of `abc123de`:

```bash
python3 ~/claude_statusline/claude/session_meter/session_meter.py --report ~/.claude/projects/*/abc123de*.jsonl
```

An example, without the parts at 0:

```
session meter 24 🟡 yellow
model claude-opus-5   context 178k
median response gap 11s over the last 100

part                weighted      base   points
tool errors             0.75     17.75     1.67
shell file views        5.00     17.75     1.69
user corrections        2.25      4.25     6.75
stock phrases           0.75      4.75     1.80
verbosity               1.25      4.75     7.42
total                                     23.99
```

[claude/session_meter/README.md](claude/session_meter/README.md), also in `~/claude_statusline`, says what each part counts, and how to move the reading by hand.

## When the bar does not show

- Claude Code runs a status bar only in a folder that you trust. Answer the trust question for the folder, then start the session again.
- `disableAllHooks` in the settings turns a status bar of your own off, and so does `allowManagedHooksOnly` in settings that your organization manages.
- Run the script of your command by hand. A working script prints a line that ends with the time or the account, and a fault prints an error:

```bash
echo '{}' | python3 ~/claude_statusline/claude_statusline_teams.py
```

- When the bar shows and the meter does not, run the meter by hand. It prints the path of its settings file:

```bash
python3 ~/claude_statusline/claude/session_meter/session_meter.py --settings
```

- `claude --debug` logs what the script prints on errors.

## Your own settings

Your own words and switches for the meter go in `~/.config/mariadb-qa/session_meter.json`. The folder has that name with and without mariadb-qa. The file is optional, and "Your own settings" in the README of the meter describes it.

## What stays on your machine

The meter and `claude_statusline.py` send nothing anywhere. `claude_statusline_teams.py` asks `api.anthropic.com` for the usage of the account, at most once in 5 minutes, with the login that Claude Code keeps in `~/.claude`. That request uses no tokens.

| Place | What it holds |
|---|---|
| `~/claude_statusline/` | The scripts, and the README of the meter. |
| `~/.cache/claude-session-meter/` | The counts of the meter for each session. No message text. |
| `/tmp/.claude_tokens_io.*` | The token counts of each session. |
| `/tmp/.claude_session_ids.*` | The session id of each Claude Code process. |
| `/tmp/.claude_usage_teams.*`, `/tmp/.claude_limits_teams.*` | The usage numbers. `claude_statusline_teams.py` only. |

## Update and remove

To update, run step 1 again. To remove, take the `statusLine` entry and the hook out of `~/.claude/settings.json`, and delete the places in the table.
