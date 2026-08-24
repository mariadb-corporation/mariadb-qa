#!/usr/bin/env python3
# Claude Code status line: cwd, session, context, usage bands, session name, model, clock
# Example: ~/mariadb-qa  abc123de  235k/1M  5h: 25% 13:10  wk: 23% 07:00  f5: 3%   Fri  corlogic-cf  Opus 5 max  11:02:32
# The 5h and weekly numbers arrive with every render, in the JSON Claude Code feeds
# this script, so they cost nothing and are always current. The Fable weekly number
# is not in that JSON. It is read from GET /api/oauth/usage by a detached background
# copy of this script and cached. That call spends no tokens, and it is paced because
# the endpoint is rate limited.
# Install in ~/.claude/settings.json:
#   "statusLine": { "type": "command", "refreshInterval": 30,
#                   "command": "python3 ~/mariadb-qa/claude_statusline_teams.py" }

import json
import os
import subprocess
import sys
import time
import urllib.request
from datetime import datetime

CACHE = f'/tmp/.claude_usage_teams.{os.getuid()}.json'
MARK = CACHE + '.pending'
CREDS = os.path.expanduser('~/.claude/.credentials.json')
USAGE_URL = 'https://api.anthropic.com/api/oauth/usage'
POLL = 300      # seconds between Fable-number reads
STALE = 900     # seconds before the Fable number is drawn dimmed
BACKOFF = 1800  # seconds to wait after a read fails, so a rate limit is not hammered
BAR = 13        # width of a usage band, the same for all of them
LIMITS = (('5h', 'five_hour'), ('wk', 'seven_day'))
SHORT = {'fable': 'f5', 'opus': 'op', 'sonnet': 'so'}

LINE = '\033[38;2;145;145;145m'      # line text
INBAR = '\033[38;2;120;120;120m'     # text inside a band
FADED = '\033[38;2;80;80;80m'        # text inside a stale band
BARBG = '\033[48;2;28;28;28m'        # unfilled part of a band
RESET = '\033[0m'


def tokens(n):
  if n >= 1000000:
    return f'{n / 1000000:.1f}'.rstrip('0').rstrip('.') + 'M'
  if n >= 1000:
    return f'{round(n / 1000)}k'
  return str(n)


def fill(pct):
  if pct > 90.0:
    return '\033[48;2;55;0;0m'
  if pct > 77.5:
    return '\033[48;2;55;55;0m'
  v = round(34 + 28 * min(pct, 77.5) / 77.5)
  return f'\033[48;2;{v};{v};{v}m'


def clock(epoch):
  if not epoch:
    return '', ''
  t = datetime.fromtimestamp(epoch)
  return t.strftime('%H:%M'), '' if t.date() == datetime.now().date() else t.strftime('%a')


def band(label, pct, hhmm, stale):
  head = f'{label}: {round(pct)}%'
  text = head + ' ' * (BAR - len(head) - len(hhmm)) + hhmm
  n = max(0, min(BAR, round(BAR * pct / 100)))
  return f'{FADED if stale else INBAR}{fill(pct)}{text[:n]}{BARBG}{text[n:]}{RESET}'


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


def record(session):
  # pid -> session id map file for the screen lister, keyed by the claude process
  p = claude_pid()
  if p is None:
    return
  d = f'/tmp/.claude_session_ids.{os.getuid()}'
  try:
    os.makedirs(d, exist_ok=True)
    tmp = f'{d}/.{p}.tmp'
    with open(tmp, 'w') as f:
      f.write(session)
    os.replace(tmp, f'{d}/{p}')
  except OSError:
    return


def cached():
  try:
    age = time.time() - os.path.getmtime(CACHE)
    with open(CACHE) as f:
      return json.load(f), age
  except (OSError, ValueError):
    return None, None


def spawn():
  try:
    if time.time() - os.path.getmtime(MARK) < POLL:
      return
  except OSError:
    pass
  open(MARK, 'w').close()
  subprocess.Popen([sys.executable, os.path.realpath(__file__), '--fetch'],
                   stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, start_new_session=True)


def defer():
  later = time.time() + BACKOFF - POLL
  open(MARK, 'w').close()
  os.utime(MARK, (later, later))


def fetch():
  with open(CREDS) as f:
    token = json.load(f)['claudeAiOauth']['accessToken']
  req = urllib.request.Request(USAGE_URL, headers={
    'authorization': f'Bearer {token}', 'content-type': 'application/json'})
  try:
    with urllib.request.urlopen(req, timeout=15) as r:
      usage = json.load(r)
  except Exception:
    defer()
    return
  scoped = None
  for limit in usage.get('limits') or []:
    if limit.get('kind') == 'weekly_scoped':
      name = (((limit.get('scope') or {}).get('model') or {}).get('display_name') or '')
      scoped = [SHORT.get(name.lower(), name[:2].lower()), limit.get('percent') or 0]
      break
  tmp = CACHE + '.tmp'
  with open(tmp, 'w') as f:
    json.dump(scoped, f)
  os.replace(tmp, CACHE)


if '--fetch' in sys.argv:
  fetch()
  sys.exit(0)

if os.path.exists(os.path.expanduser('~/mariadb-qa/nostatusline')):
  sys.exit(0)

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
  parts.append(f'{LINE}{cwd}{RESET}')

session_id = data.get('session_id') or ''
session = session_id[:8]
if session:
  parts.append(f'{LINE}{session}{RESET}')
  record(session_id)

ctx = data.get('context_window') or {}
used = ctx.get('total_input_tokens')
size = ctx.get('context_window_size')
if used is not None and size:
  if used > 750000:
    color = '\033[1;31m'
  elif used > 500000:
    color = '\033[31m'
  elif used > 300000:
    color = '\033[33m'
  else:
    color = LINE
  parts.append(f'{color}{tokens(used)}/{tokens(size)}{RESET}')

bands = []
days = []
rate = data.get('rate_limits') or {}
for label, key in LIMITS:
  limit = rate.get(key) or {}
  pct = limit.get('used_percentage')
  if pct is None:
    continue
  hhmm, day = clock(limit.get('resets_at'))
  bands.append(band(label, pct, hhmm, False))
  days.append(day)

days = [day for day in days if day]
day = days[-1] if days else ''

scoped, age = cached()
if age is None or age >= POLL:
  spawn()
if scoped:
  bands.append(band(scoped[0], scoped[1], day, age >= STALE))
  day = ''

if bands and day:
  bands[-1] += f' {LINE}{day}{RESET}'
if bands:
  parts.append('  '.join(bands))

name = sname()
if name:
  parts.append(f'{LINE}{name}{RESET}')

model = (data.get('model') or {}).get('display_name', '')
effort = (data.get('effort') or {}).get('level')
if model:
  parts.append(f'{LINE}{model} {effort}{RESET}' if effort else f'{LINE}{model}{RESET}')

parts.append(f'{LINE}{datetime.now().strftime("%H:%M:%S")}{RESET}')

print('  '.join(parts))
