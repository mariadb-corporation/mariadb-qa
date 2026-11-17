# Session meter for Claude Code

The session meter gives one number for how a Claude Code session is going: 0 is a smooth session, 100 is a rough one. The status bar shows it, and an optional prompt hook shows the same number to Claude, so that it works more carefully when a session gets rough.

The meter reads the session transcript on your machine and counts signs of friction: tool calls that fail, the same call made twice, corrections and reminders that you type, and apologies and filler in the replies. Recent events count most. Thanks and praise lower the number.

A high reading does not say who or what is at fault. It says that the session takes more steering than usual, and that a fresh session may be the quicker way forward.

Nothing is sent anywhere. The transcript is read where it is. The cache in `~/.cache/claude-session-meter` holds counts and the place where the last read stopped, and no message text.

## Requirements

Claude Code, and Python 3.8 or later. Tested on Linux.

## The status bar

`claude_statusline.py` and `claude_statusline_teams.py`, in the top directory of this repository, show the reading after the context size:

    ~/mariadb-qa abc123de 235k 🟢12 ...

| Mark | Reading | What it means |
|---|---|---|
| 🟢 | 0 to 19 | The session runs well. |
| 🟡 | 20 to 34 | Some friction. Check that the request is followed. |
| 🟠 | 35 to 54 | Clear friction. Smaller steps and more review help. |
| 🔴 | 55 to 100 | A rough session. A fresh session is advised. |

No setup is needed: each status bar script finds the meter by its place in the repository. `⋯` shows for a short time while a long transcript is read for the first time.

## The prompt hook

The hook is optional. Each time you send a prompt while the reading is yellow or worse, it puts one line into the session, where Claude reads it:

    session meter 41 🟠 | user corrections 12, tool errors 6 | take smaller steps, and check each claim before you state it

The line holds the reading, the two largest parts of it, and what to do:

| Mark | Line to Claude |
|---|---|
| 🟡 | re-read the request before you act |
| 🟠 | take smaller steps, and check each claim before you state it |
| 🔴 | stop new work, write a handover file (open tasks, findings, how to run) in the working folder, and tell the user that a fresh session is advised |

To turn the hook on, add it to `~/.claude/settings.json`:

    {
      "hooks": {
        "UserPromptSubmit": [
          {
            "hooks": [
              {
                "type": "command",
                "command": "python3 ~/mariadb-qa/claude/session_meter/session_meter_hook.py",
                "timeout": 10,
                "statusMessage": "Reading the session meter"
              }
            ]
          }
        ]
      }
    }

To have Claude act in another way on a mark, say so in your `CLAUDE.md`, and name the mark.

## What is counted

| Part | What counts |
|---|---|
| tool errors | The share of tool calls that fail. |
| edit errors | The share of file edits that fail. |
| error streaks | Three failed calls in a row, and more for a longer run. |
| repeated calls | The same call with the same input, again within three calls. |
| shell file views | A file shown with `cat`, `head`, `tail` or the like through the shell. |
| user corrections | A prompt that corrects, in three strengths: "no", "that is wrong", "you missed". |
| user nudges | A prompt that asks to go on, or asks where things are: "continue", "any update". |
| interrupts | A reply or a tool call that you stopped. |
| self corrections | An apology or a correction in a reply: "sorry", "I misread". |
| stock phrases | Filler and sales wording in a reply: "great question", "in summary", "seamless". |
| verbosity | Many long replies, and long sentences. |
| api errors | A request to the API that failed. |
| praise | Lowers the reading: "thanks", "great", "that works". |

The window holds the last 70 events, and the newest count most. Each part has a ceiling, so no one part fills the scale. The shown number walks towards the count a step at a time, and it stays low over the first 35 events of a session, while there is little to go on.

A message over 2000 characters is taken as a paste: it counts as a message, and its words are not read. The work of subagents is not read.

## Moving the reading by hand

Type `meter +10` or `meter -10` at the start of a line in a prompt. The reading moves by that number at once, by 25 at most, and the move fades over the next 35 events.

## Commands

    session_meter.py --report <transcript.jsonl>    the full table for one session
    session_meter.py --json <transcript.jsonl>      the same, machine readable
    session_meter.py --replay <transcript.jsonl>    the reading after every event
    session_meter.py --settings                     the settings file as it was read
    session_meter.py --calibrate [labels.json]      how the bands split labelled sessions

Claude Code keeps the transcripts in `~/.claude/projects/<project>/<session id>.jsonl`.

## Your own settings

The word lists in the script are general English. Your own words go in `~/.config/mariadb-qa/session_meter.json`. The file is optional and stays on your machine, and the script stays as the repository has it.

    {
      "_note": "A key that starts with an underscore is a note.",
      "words": {
        "corrections_severe": ["\\brubbish\\b"],
        "corrections_plain": ["\\bniet goed\\b", "\\bpas correct\\b"],
        "nudges": ["\\bga door\\b"],
        "praise_medium": ["\\bdank je\\b", "\\bmerci\\b"],
        "stock_phrases": ["\\bmoving forward\\b"]
      },
      "hand_marks": ["🙂"],
      "count_em_dashes": true,
      "count_he_him": true,
      "context_zone": [150000, 200000]
    }

| Key | What it does |
|---|---|
| `words` | Adds Python regular expressions to the built-in list of the same name. |
| `hand_marks` | More marks for a move by hand, next to `meter`. A word counts at the start of a line, a symbol anywhere in the prompt. |
| `count_em_dashes` | Counts each em-dash in a reply. For those who ask Claude to write without them. |
| `count_he_him` | Counts "he" and "him" in a reply. For those who ask Claude for neutral pronouns. |
| `context_zone` | A range of context sizes, in tokens. The status bar adds `⚠` to the reading while the context is in that range. |

The word lists, and the points one match gives:

| List | Read in | Points |
|---|---|---|
| `corrections_severe`, `corrections_heavy`, `corrections_plain` | your prompts | 5, 3, 1 for a prompt; the strongest list wins |
| `nudges` | your prompts | 1 for a prompt |
| `praise_high`, `praise_medium`, `praise_low` | your prompts | 2, 1.5, 1 for a prompt; the strongest list wins |
| `self_severe`, `self_heavy`, `self_plain` | the replies | 5, 3, 1 for a reply; the strongest list wins |
| `stock_phrases` | the replies | 1 for each match |

A pattern of your own ignores case. Put `(?-i:...)` around a part that has to match case, such as a short form in capitals.

`session_meter.py --settings` shows what was read, and names each item that was left out. A fault in the file leaves that one item out, and the rest stays in use. After a change to the file, each session reads its transcript once more from the start.

## Calibration

`CALIBRATION` in the script maps the count onto the 0 to 100 scale. It is fitted to labelled sessions, so that yellow, orange and red start where friction, clear friction and failed sessions start.

To see how the bands fit your own sessions, label some of them. The key is the start of a session id, which is the name of the transcript file. The value is 0 for a session that went fine, 1 for one with friction, and 2 for one that failed:

    {
      "labels": {"1a2b3c4d": 2, "5e6f7a8b": 1, "9c0d1e2f": 0}
    }

Save the file as `~/.config/mariadb-qa/session_meter_labels.json`, or give its path to `--calibrate`. The output gives the median peak reading for each label. For the orange and the red mark, it gives how many failed sessions reached the mark, and how many fine sessions did. An example:

    fine      n=40   median peak  12.0
    friction  n=15   median peak  38.5
    failed    n=12   median peak  61.0

    cut 35: caught 11 of 12 failed, 4 of 40 fine raised it
    cut 55: caught 8 of 12 failed, 1 of 40 fine raised it

Judge a session on its peak reading, not on its last one. A session that recovers ends low, whatever happened in the middle.

## Tests

    python3 session_meter_test.py

## Files

| File | Purpose |
|---|---|
| `session_meter.py` | The meter: the status bar reading, the reports and the calibration. |
| `session_meter_hook.py` | The prompt hook. |
| `session_meter_test.py` | The tests for both. |
