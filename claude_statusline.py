#!/usr/bin/env python3
# Claude Code status line: cwd | session | context used/max | model (effort) | cost
# Example output: ~/mariadb-qa | 298aa97a | 150k/1M | Fable (xhigh) | $1.23
# Install in ~/.claude/settings.json:
#   "statusLine": { "type": "command", "command": "python3 ~/mariadb-qa/claude_statusline.py" }

import json
import os
import sys

if os.path.exists(os.path.expanduser('~/mariadb-qa/nostatusline')):
  sys.exit(0)

def tokens(n):
  if n >= 1000000:
    return f'{n / 1000000:.1f}'.rstrip('0').rstrip('.') + 'M'
  if n >= 1000:
    return f'{round(n / 1000)}k'
  return str(n)

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

session = (data.get('session_id') or '')[:8]
if session:
  parts.append(session)

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

model = (data.get('model') or {}).get('display_name', '')
effort = (data.get('effort') or {}).get('level')
if model:
  parts.append(f'{model} ({effort})' if effort else model)

cost = (data.get('cost') or {}).get('total_cost_usd')
if cost is not None:
  parts.append(f'${cost:.2f}')

print(' | '.join(parts))
