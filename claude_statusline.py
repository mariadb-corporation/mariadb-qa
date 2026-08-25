#!/usr/bin/env python3
# Claude Code status line: cwd | session | context used/max | session name |
# model (effort) | tokens up/down | cost
# Example output: ~/mariadb-qa | 298aa97a | 150k/1M | corlogic-cf | Fable (xhigh) | ↑1.2M ↓84k | $1.23
# Install in ~/.claude/settings.json:
#   "statusLine": { "type": "command", "command": "python3 ~/mariadb-qa/claude_statusline.py" }

import glob
import json
import os
import sys

if os.path.exists(os.path.expanduser('~/mariadb-qa/nostatusline')):
  sys.exit(0)

INP = ('input_tokens', 'cache_creation_input_tokens')
OUTP = ('output_tokens',)
HEAT = (1000000, 3000000, 7000000)  # tokens down that turn yellow, red, bright red
SCALE = 3        # tokens up are counted against those marks times this
BLUE = '\033[38;2;110;160;230m'      # the token counter at rest


def tokens(n):
  if n >= 1000000:
    return f'{n / 1000000:.1f}'.rstrip('0').rstrip('.') + 'M'
  if n >= 1000:
    return f'{round(n / 1000)}k'
  return str(n)


def spent(n):
  # the session token counter: 1000, then 10k, then 1.2M
  if n >= 1000000:
    return f'{n / 1000000:.1f}M'
  if n >= 10000:
    return f'{round(n / 1000)}k'
  return str(n)


def heat(n, scale=1):
  # blue up to the first mark, then yellow, red, and bright red
  if n >= HEAT[2] * scale:
    return '\033[1;31m'
  if n >= HEAT[1] * scale:
    return '\033[31m'
  if n >= HEAT[0] * scale:
    return '\033[33m'
  return BLUE


def counted(path, start):
  # input and output tokens in the part of a transcript that has not been counted yet,
  # and where to start next time. A half written last line is left for the next render
  try:
    with open(path, 'rb') as f:
      f.seek(start)
      raw = f.read()
  except OSError:
    return 0, 0, start
  end = raw.rfind(b'\n') + 1
  inp = outp = 0
  for line in raw[:end].splitlines():
    if b'"usage"' not in line:
      continue
    try:
      use = (json.loads(line).get('message') or {}).get('usage') or {}
    except ValueError:
      continue
    inp += sum(use.get(key) or 0 for key in INP)
    outp += sum(use.get(key) or 0 for key in OUTP)
  return inp, outp, start + end


def consumed(transcript, session):
  # every token this session and its subagents have used. Each transcript is read on
  # from where the last render stopped, so the count stays cheap on a long session
  store = f'/tmp/.claude_tokens_io.{os.getuid()}.{session[:8]}.json'
  try:
    with open(store) as f:
      seen = json.load(f)
  except (OSError, ValueError):
    seen = {}
  subs = f'{os.path.dirname(transcript)}/{session}/subagents/*.jsonl'
  total = [0, 0]
  for path in [transcript] + sorted(glob.glob(subs)):
    start, inp, outp = seen.get(path, (0, 0, 0))
    try:
      size = os.path.getsize(path)
    except OSError:
      continue
    if size < start:
      start, inp, outp = 0, 0, 0
    if size > start:
      add_in, add_out, start = counted(path, start)
      inp += add_in
      outp += add_out
    seen[path] = (start, inp, outp)
    total[0] += inp
    total[1] += outp
  try:
    tmp = store + '.tmp'
    with open(tmp, 'w') as f:
      json.dump(seen, f)
    os.replace(tmp, store)
  except OSError:
    pass
  return total


def claude_pid():
  # walk up to the claude process, which is what the session name is keyed by
  p = os.getppid()
  for _ in range(6):
    try:
      with open(f'/proc/{p}/comm') as f:
        comm = f.read().strip()
      if comm == 'claude':
        return p
      with open(f'/proc/{p}/stat') as f:
        p = int(f.read().rsplit(') ', 1)[1].split()[1])
    except (OSError, ValueError, IndexError):
      return None
    if p <= 1:
      return None
  return None


def sname():
  # the session name Claude Code shows to other sessions, e.g. corlogic-cf
  p = claude_pid()
  if p is None:
    return ''
  try:
    with open(f'{os.path.expanduser("~")}/.claude/sessions/{p}.json') as f:
      return json.load(f).get('name') or ''
  except (OSError, ValueError):
    return ''


try:
  data = json.load(sys.stdin)
except Exception:
  sys.exit(0)

parts = []

cwd = data.get('workspace', {}).get('current_dir') or data.get('cwd') or ''
home = os.path.expanduser('~')
if cwd == home:
  cwd = '~'
elif cwd.startswith(home + os.sep):
  cwd = '~' + cwd[len(home):]
if cwd:
  parts.append(cwd)

session_id = data.get('session_id') or ''
if session_id:
  parts.append(session_id[:8])

ctx = data.get('context_window') or {}
used = ctx.get('total_input_tokens')
size = ctx.get('context_window_size')
if used is not None and size:
  text = f'{tokens(used)}/{tokens(size)}'
  if used > 750000:
    text = f'\033[1;38;5;196m{text}\033[0m'  # bold red
  elif used > 500000:
    text = f'\033[38;5;196m{text}\033[0m'  # red
  elif used > 300000:
    text = f'\033[38;5;208m{text}\033[0m'  # orange
  parts.append(text)

name = sname()
if name:
  parts.append(name)

model = (data.get('model') or {}).get('display_name', '')
effort = (data.get('effort') or {}).get('level')
if model:
  parts.append(f'{model} ({effort})' if effort else model)

transcript = data.get('transcript_path') or ''
if session_id and transcript:
  inp, outp = consumed(transcript, session_id)
  parts.append(f'{heat(inp, SCALE)}\u2191{spent(inp)}\033[0m '
               f'{heat(outp)}\u2193{spent(outp)}\033[0m')

cost = (data.get('cost') or {}).get('total_cost_usd')
if cost is not None:
  parts.append(f'${cost:.2f}')

print(' | '.join(parts))
