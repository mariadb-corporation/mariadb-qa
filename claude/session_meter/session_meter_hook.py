#!/usr/bin/env python3
"""UserPromptSubmit hook: let a session see its own session meter reading.

Reads the hook json on stdin, scans the transcript to its current end, adds
the prompt that fired this hook (it is not on disk yet), and prints one line
when the reading is yellow or worse. That line enters the model's context.
Prints nothing and exits clean on any fault.
"""

import copy
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))

TAIL = 256 * 1024      # bytes of the transcript checked for the typed prompt

# What the session is asked to do, by band. Green prints nothing.
ADVICE = ('',
          're-read the request before you act',
          'take smaller steps, and check each claim before you state it',
          'stop new work, write a handover file (open tasks, findings, how to '
          'run) in the working folder, and tell the user that a fresh session '
          'is advised')


def landed(path, prompt):
  # the prompt is usually not written yet; when it is, do not count it twice.
  # A transcript holds text outside ASCII as typed, so that form is looked for
  # as well as the escaped one
  try:
    with open(path, 'rb') as handle:
      handle.seek(0, os.SEEK_END)
      handle.seek(max(0, handle.tell() - TAIL))
      tail = handle.read()
  except OSError:
    return False
  for escaped in (False, True):
    needle = json.dumps(prompt, ensure_ascii=escaped)[1:-1]
    needle = needle.encode('utf-8', 'replace')
    if needle and needle in tail:
      return True
  return False


def main():
  try:
    data = json.load(sys.stdin)
    path = data.get('transcript_path')
    session = data.get('session_id')
    prompt = data.get('prompt') or ''
    if not path or not session or not os.path.exists(path):
      return 0
    import session_meter as meter
    reader = meter.load(session, path)
    if os.path.getsize(path) - reader.cursor > meter.BIG_BACKLOG:
      return 0                      # the bar's background scan will catch up
    reader.scan(path)
    meter.save(reader, session, path)
    if prompt and not landed(path, prompt):
      ahead = copy.deepcopy(reader)     # in memory only, never saved
      event = {}
      ahead.prompt(prompt, None, event)
      ahead.push(event)
      reader = ahead
    view = meter.reading(reader)
    if meter.shown(view['score']) < meter.CUTS[0]:
      return 0
    parts = meter.top_parts(view)
    line = 'session meter %d %s' % (meter.shown(view['score']), view['mark'])
    if parts:
      line += ' | %s' % parts
    line += ' | %s' % ADVICE[view['band']]
    print(line)
  except Exception:
    return 0
  return 0


if __name__ == '__main__':
  sys.exit(main())
