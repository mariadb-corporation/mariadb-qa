#!/usr/bin/env python3
# Claude Code status line: cwd, session, context, cost, model, tokens,
# session name, clock. The same line as claude_statusline_teams.py, with the session cost
# in the place of its usage bands
# Example: ~/mariadb-qa abc123de 235k $1.23 o55-m ↑1.2M ↓84k ↻96% corlogic-cf 11:02
# Install in ~/.claude/settings.json:
#   "statusLine": { "type": "command", "refreshInterval": 30,
#                   "command": "python3 ~/mariadb-qa/claude_statusline.py" }

import glob
import json
import os
import subprocess
import sys
from datetime import datetime

CWD = 19        # width the current directory is cut back to
NAME = 16       # width the session name is cut back to
FAMILY = {'opus': 'o', 'sonnet': 's', 'haiku': 'h', 'fable': 'f', 'mythos': 'm'}
EFFORT = {'low': 'l', 'medium': 'me', 'high': 'h', 'xhigh': 'xh', 'max': 'm'}
TOP = ('fable', 'mythos')    # model lines that are current at any version
DROPPED = ('l', 'me', 'h')   # effort levels below xhigh
INP = ('input_tokens', 'cache_creation_input_tokens')
OUTP = ('output_tokens',)
READ = ('cache_read_input_tokens',)
HEAT = (1000000, 3000000, 7000000)  # tokens down that turn yellow, red, bright red
SCALE = 3        # tokens up are counted against those marks times this

BOLD = '\033[1m'                     # the cut marker on a shortened field
BLUE = '\033[38;2;110;160;230m'      # the token counter at rest
SESS = '\033[38;5;73m'               # the session id
LINE = '\033[38;2;145;145;145m'      # line text
GREEN = '\033[38;5;34m'              # the model field at max effort
RED = '\033[38;5;160m'               # the model field on an older model line, or below xhigh effort
RESET = '\033[0m'


def tokens(n):
  if n >= 1000000:
    return f'{n / 1000000:.1f}'.rstrip('0').rstrip('.') + 'M'
  if n >= 1000:
    return f'{round(n / 1000)}k'
  return str(n)


def spent(n):
  # the session token counter: 999, then 1k, then 1.2M
  if n >= 1000000:
    return f'{n / 1000000:.1f}M'
  if n >= 1000:
    return f'{round(n / 1000)}k'
  return str(n)


def share(pct, seen):
  # how much of the input came out of the cache: green is good, red is not. With no
  # input counted yet the 0% stands for nothing, so it is drawn as plain line text
  if not seen:
    return LINE
  if pct >= 90:
    return '\033[32m'
  if pct >= 70:
    return '\033[33m'
  return '\033[31m'


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
  # input, output and cache-read tokens in the part of a transcript that has not been
  # counted yet, and where to start next time. A half written last line is left over
  try:
    with open(path, 'rb') as f:
      f.seek(start)
      raw = f.read()
  except OSError:
    return 0, 0, 0, start
  end = raw.rfind(b'\n') + 1
  inp = outp = red = 0
  for line in raw[:end].splitlines():
    if b'"usage"' not in line:
      continue
    try:
      use = (json.loads(line).get('message') or {}).get('usage') or {}
    except ValueError:
      continue
    inp += sum(use.get(key) or 0 for key in INP)
    outp += sum(use.get(key) or 0 for key in OUTP)
    red += sum(use.get(key) or 0 for key in READ)
  return inp, outp, red, start + end


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
  total = [0, 0, 0]
  for path in [transcript] + sorted(glob.glob(subs)):
    kept = seen.get(path)
    start, inp, outp, red = (kept if isinstance(kept, list) and len(kept) == 4
                             else (0, 0, 0, 0))
    try:
      size = os.path.getsize(path)
    except OSError:
      continue
    if size < start:
      start, inp, outp, red = 0, 0, 0, 0
    if size > start:
      add_in, add_out, add_red, start = counted(path, start)
      inp += add_in
      outp += add_out
      red += add_red
    seen[path] = (start, inp, outp, red)
    total[0] += inp
    total[1] += outp
    total[2] += red
  try:
    tmp = store + '.tmp'
    with open(tmp, 'w') as f:
      json.dump(seen, f)
    os.replace(tmp, store)
  except OSError:
    pass
  return total


def short(name):
  # the model in two or three characters: Opus 5 -> o5, Sonnet 4.6 -> s46, Haiku 4.5 ->
  # h45. The context window is already on the line, so a 1M note is dropped here
  word = name.split(' (')[0].split()
  if not word:
    return ''
  return (FAMILY.get(word[0].lower(), word[0][:1].lower())
          + ''.join(word[1:]).replace('.', ''))


def dated(name):
  # true for a model line that is not current: an Opus below 5, and Sonnet or Haiku
  word = name.split(' (')[0].split()
  family = word[0].lower() if word else ''
  if family in TOP:
    return False
  if family != 'opus' or len(word) < 2:
    return True
  try:
    return float(word[1]) < 5
  except ValueError:
    return True


def claude_pid():
  # walk up to the claude process, which is what both the map file and the name are keyed by
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


def tty_of(p):
  # the terminal a process runs on, as pts-<n>, empty when it has none
  try:
    with open(f'/proc/{p}/stat') as f:
      nr = int(f.read().rsplit(') ', 1)[1].split()[4])
  except (OSError, ValueError, IndexError):
    return ''
  if (nr >> 8) & 0xfff != 136:
    return ''
  return f'pts-{(nr & 0xff) | ((nr >> 12) & 0xfff00)}'


def record(session):
  # pid -> session id map file for the screen lister, keyed by the claude process.
  # The same id is kept under tty/, so the lister can still name the session that
  # ran in a screen window once it has ended
  p = claude_pid()
  if p is None:
    return
  d = f'/tmp/.claude_session_ids.{os.getuid()}'
  t = tty_of(p)
  try:
    os.makedirs(f'{d}/tty' if t else d, exist_ok=True)
    tmp = f'{d}/.{p}.tmp'
    with open(tmp, 'w') as f:
      f.write(session)
    os.replace(tmp, f'{d}/{p}')
    if t:
      with open(tmp, 'w') as f:
        f.write(session)
      os.replace(tmp, f'{d}/tty/{t}')
  except OSError:
    return


if os.path.exists(os.path.expanduser('~/mariadb-qa/nostatusline')):
  sys.exit(0)

try:
  data = json.load(sys.stdin)
except Exception:
  sys.exit(0)

def clip(text, width):
  # keep the head of an over-long field and mark the cut
  return text if len(text) <= width else f'{text[:width]}{BOLD}>{RESET}'


parts = []

cwd = data.get('workspace', {}).get('current_dir') or data.get('cwd') or ''
home = os.path.expanduser('~')
if cwd == home:
  cwd = '~'
elif cwd.startswith(home + os.sep):
  cwd = '~' + cwd[len(home):]
if cwd:
  parts.append(f'{LINE}{clip(cwd, CWD)}{RESET}')

session_id = data.get('session_id') or ''
session = session_id[:8]
if session:
  parts.append(f'{SESS}{session}{RESET}')
  record(session_id)

ctx = data.get('context_window') or {}
used = ctx.get('total_input_tokens')
size = ctx.get('context_window_size')
if used is not None:
  if used > 750000:
    color = '\033[1;31m'
  elif used > 500000:
    color = '\033[31m'
  elif used > 300000:
    color = '\033[33m'
  else:
    color = LINE
  # the window size is shown only when it is not the 1M one this box runs on
  room = '' if not size or size >= 1000000 else f'/{tokens(size)}'
  parts.append(f'{color}{tokens(used)}{room}{RESET}')

check = os.path.expanduser('~/.claude/sanity_check.py')
if os.path.exists(check):
  try:
    said = subprocess.run([sys.executable, check, '--segment'], input=json.dumps(data),
                          capture_output=True, text=True, timeout=3).stdout.strip()
  except Exception:
    said = ''
  if said:
    parts.append(f'{LINE}{said}{RESET}')

cost = (data.get('cost') or {}).get('total_cost_usd')
if cost is not None:
  parts.append(f'{LINE}${cost:.2f}{RESET}')

named = (data.get('model') or {}).get('display_name') or ''
model = short(named)
effort = EFFORT.get((data.get('effort') or {}).get('level'), '')
if model:
  if effort in DROPPED or dated(named):
    tint = RED
  elif effort == 'm' or named.split()[0].lower() in TOP:
    tint = GREEN
  else:
    tint = LINE
  parts.append(f'{tint}{model}-{effort}{RESET}' if effort else f'{tint}{model}{RESET}')

transcript = data.get('transcript_path') or ''
if session_id and transcript:
  inp, outp, red = consumed(transcript, session_id)
  hit = round(100 * red / (red + inp)) if red + inp else 0
  parts.append(f'{heat(inp, SCALE)}\u2191{spent(inp)}{RESET} '
               f'{heat(outp)}\u2193{spent(outp)}{RESET} '
               f'{BOLD}{LINE}\u21bb{RESET}{share(hit, red + inp)}{hit}%{RESET}')

name = sname()
if name:
  parts.append(f'{LINE}{clip(name, NAME)}{RESET}')

parts.append(f'{LINE}{datetime.now().strftime("%H:%M")}{RESET}')

print(' '.join(parts))
