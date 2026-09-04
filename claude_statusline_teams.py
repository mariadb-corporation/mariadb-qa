#!/usr/bin/env python3
# Claude Code status line: cwd, session, context, usage bands, session name, model, clock
# Example: ~/mariadb-qa  abc123de  235k/1M  5h: 25% 13:10  wk: 23% 07:00  f5: 3%   Fri  corlogic-cf  Opus 5 max  ↑1.2M ↓84k  11:02:32
# The 5h and weekly numbers arrive with every render, in the JSON Claude Code feeds
# this script, so they cost nothing and are always current. The Fable weekly number
# is not in that JSON. It is read from GET /api/oauth/usage by a detached background
# copy of this script and cached. That call spends no tokens, and it is paced because
# the endpoint is rate limited.
# Install in ~/.claude/settings.json:
#   "statusLine": { "type": "command", "refreshInterval": 30,
#                   "command": "python3 ~/mariadb-qa/claude_statusline_teams.py" }

import glob
import json
import os
import subprocess
import sys
import time
import urllib.request
from datetime import datetime

CACHE = f'/tmp/.claude_usage_teams.{os.getuid()}.json'
MARK = CACHE + '.pending'
SEEN = f'/tmp/.claude_limits_teams.{os.getuid()}.json'
CREDS = os.path.expanduser('~/.claude/.credentials.json')
CHECK = os.path.expanduser('~/.claude/sanity_check.py')
USAGE_URL = 'https://api.anthropic.com/api/oauth/usage'
POLL = 300      # seconds between Fable-number reads
STALE = 900     # seconds before the Fable number is drawn dimmed
BACKOFF = 1800  # seconds to wait after a read fails, so a rate limit is not hammered
BAR = 13        # width of a usage band, the same for all of them
CWD = 19        # width the current directory is cut back to
NAME = 16       # width the session name is cut back to
LIMITS = (('5h', 'five_hour'), ('wk', 'seven_day'))
SHORT = {'fable': 'f5', 'opus': 'op', 'sonnet': 'so'}
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
INBAR = '\033[38;2;120;120;120m'     # text inside a band
FADED = '\033[38;2;80;80;80m'        # text inside a stale band
DARK = '\033[38;2;22;22;22m'         # text on a filled cell that grey cannot be read on
BARBG = '\033[48;2;28;28;28m'        # unfilled part of a band
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


def bulk(n):
  # the cache-read counter, whole units only
  return f'{int(n / 1000000 + 0.5)}M' if n >= 1000000 else spent(n)


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
  # grey up to the first mark, then yellow, red, and bright red
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


def fill(pct):
  # background of a filled cell, plus the text colour it needs, empty to keep the band's
  if pct > 90.0:
    return '\033[48;2;55;0;0m', ''
  if pct > 77.5:
    return '\033[48;2;55;55;0m', DARK
  v = round(34 + 28 * min(pct, 77.5) / 77.5)
  return f'\033[48;2;{v};{v};{v}m', ''


def clock(epoch):
  if not epoch:
    return '', ''
  t = datetime.fromtimestamp(epoch)
  return t.strftime('%H:%M'), t.strftime('%a')


def band(label, pct, hhmm, stale):
  head = f'{label}: {round(pct)}%'
  if not hhmm:               # with no time to sit on the right, the value goes there
    head, hhmm = f'{label}:', f'{round(pct)}%'
  text = head + ' ' * (BAR - len(head) - len(hhmm)) + hhmm
  n = max(0, min(BAR, round(BAR * pct / 100)))
  ink = FADED if stale else INBAR
  bg, lit = fill(pct)
  return f'{lit or ink}{bg}{text[:n]}{ink}{BARBG}{text[n:]}{RESET}'


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


def cached():
  try:
    age = time.time() - os.path.getmtime(CACHE)
    with open(CACHE) as f:
      return json.load(f), age
  except (OSError, ValueError):
    return None, None


def limits(rate):
  # the 5h and weekly numbers are absent from the first renders of a session, and a
  # render can carry one without the other. Each is kept as it arrives, and drawn
  # faded once old, so a band is there from the first render on
  try:
    with open(SEEN) as f:
      keep = json.load(f)
  except (OSError, ValueError):
    keep = {}
  if not isinstance(keep, dict):
    keep = {}
  now = time.time()
  # an idle session replays the last numbers it saw, so a window whose reset time has
  # already passed is left out, and a kept window is never replaced by an older one.
  # Without that, one idle session wipes the band for every session, since all of them
  # read and write this one file
  fresh = {key: {'pct': one.get('used_percentage'),
                 'resets': one.get('resets_at'), 'seen': now}
           for key, one in rate.items()
           if isinstance(one, dict) and one.get('used_percentage') is not None
           and (one.get('resets_at') or 0) > now}
  fresh = {key: one for key, one in fresh.items()
           if one['resets'] >= ((keep.get(key) or {}).get('resets') or 0)}
  keep.update(fresh)
  # Claude Code drops a window from its own JSON once the window has reset, so a kept
  # one goes the same way rather than showing a number that no longer stands
  keep = {key: one for key, one in keep.items()
          if isinstance(one, dict) and one.get('pct') is not None
          and (one.get('resets') or 0) > now}
  if fresh:
    try:
      tmp = SEEN + '.tmp'
      with open(tmp, 'w') as f:
        json.dump(keep, f)
      os.replace(tmp, SEEN)
    except OSError:
      pass
  return keep


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

if os.path.exists(CHECK):
  try:
    said = subprocess.run([sys.executable, CHECK, '--segment'], input=json.dumps(data),
                          capture_output=True, text=True, timeout=3).stdout.strip()
  except Exception:
    said = ''
  if said:
    parts.append(f'{LINE}{said}{RESET}')

bands = []
days = []
rate = limits(data.get('rate_limits') or {})
for label, key in LIMITS:
  limit = rate.get(key)
  if not limit:
    continue
  hhmm, day = clock(limit['resets'])
  bands.append(band(label, limit['pct'], hhmm, time.time() - limit['seen'] >= STALE))
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
  parts.append(' '.join(bands))

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
               f'{BOLD}{LINE}\u21bb{RESET}{LINE}{bulk(red)}{RESET} '
               f'{share(hit, red + inp)}{hit}%{RESET}')

name = sname()
if name:
  parts.append(f'{LINE}{clip(name, NAME)}{RESET}')

parts.append(f'{LINE}{datetime.now().strftime("%H:%M")}{RESET}')

print(' '.join(parts))
