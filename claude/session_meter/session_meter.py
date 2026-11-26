#!/usr/bin/env python3
"""The session meter: a live friction score for one Claude Code session.

Reads the session transcript, counts signs of friction, weights the recent
ones, and returns one number from 0 (smooth) to 100 (rough). The number shown
walks towards that count a step at a time, so it climbs and falls without
lurching, and a hand move is added to it at face value.

  session_meter.py --report <transcript>     the full table
  session_meter.py --json <transcript>       the same, machine readable
  session_meter.py --segment                 status bar string, bar json on stdin
  session_meter.py --segment --transcript P --session S
  session_meter.py --scan --transcript P --session S    fill the cache, print nothing
  session_meter.py --replay <transcript>     the score after every event
  session_meter.py --calibrate [labels]      how the bands split labelled sessions
  session_meter.py --settings                the settings file as it was read

The transcript is read on this machine, no message text is kept, and nothing
is sent anywhere. README.md beside this file covers the bands, the prompt hook
and the settings file.

Choices that are easy to get wrong:

- Counts are weighted sums, not weighted sums divided by four. Two numbers only
  work without that divisor: the per-occurrence values of the flat parts (0.5 an
  em-dash, 2 an api error, 6 a streak), and "one file view carries 5 view
  points" against the call volume.
- Every rate divides by a base that carries a floor from FLOOR. Without it a
  window holding two edit calls turns one failure into a pinned part, and the
  part stops telling green from red. The scales assume those floors.
- CALIBRATION maps raw points onto the shown 0-100 scale. Refit it with
  --calibrate after any scoring change, or the bands drift off their meaning.
- The three commonest correction words ("no", "but", "why") match at the start of
  a line only. Unanchored they fire on ordinary prose ("there is no file", "small
  but slow"), which pins the correction cap on a clean session and breaks the
  calibration.
"""

import hashlib
import json
import math
import os
import re
import subprocess
import sys
if hasattr(sys.stdout, 'reconfigure'):
  sys.stdout.reconfigure(encoding='utf-8', errors='replace')  # Windows console is cp1252
import time
from collections import deque
from datetime import datetime

VERSION = 2              # cache format; bump on any parsing or scoring change
RING = 70                # events held in the recency window
STEPS = ((7, 1.0), (13, 0.75), (20, 0.5), (30, 0.25))   # newest first
RAMP_AT = 35             # events for full confidence
PASTE = 2000             # a longer user message is a paste: count it, do not scan it
LONG_BLOCK = 250         # words in an assistant block that make it a wall of text
GAPS = 100               # response gaps kept
PENDING_CAP = 200        # tool calls awaiting a result
SIGS = 3                 # call signatures compared for a repeat
BIG_BACKLOG = 8 * 1024 * 1024   # unscanned bytes that move the scan off the bar
SPAWN_WINDOW = 180       # seconds a background scan marker stays fresh
CUTS = (20, 35, 55)      # green under 20, yellow, orange, red from 55
MARKS = ('\U0001F7E2', '\U0001F7E1', '\U0001F7E0', '\U0001F534')
EDIT_TOOLS = ('Edit', 'Write', 'NotebookEdit')
SHELL_TOOL = 'Bash'
DISPLAY = ('cat', 'head', 'tail', 'less', 'more', 'bat')
FREE = ('echo', 'cd')
SCRATCH = '/tmp/claude-'   # the harness scratch tree; a job reading its own output
HAND_MARK = 'meter'      # typed before a signed number, it moves the score by hand

CAPS = {
  'tool_errors': 20, 'edit_errors': 20, 'streaks': 18, 'repeats': 10,
  'pagers': 10, 'corrections': 30, 'nudges': 10, 'interrupts': 8,
  'self_corrections': 15, 'stock_phrases': 15, 'emdashes': 7, 'pronouns': 7,
  'verbosity': 15, 'api_errors': 10, 'praise': 13,
}

FLOOR = {'tool_errors': 10.0, 'edit_errors': 6.0, 'repeats': 10.0, 'pagers': 10.0,
         'corrections': 5.0, 'nudges': 5.0, 'interrupts': 5.0,
         'self_corrections': 5.0, 'stock_phrases': 5.0, 'pronouns': 5.0,
         'long_share': 5.0, 'praise': 5.0}

FREE_RATE = {'tool_errors': 0.02, 'edit_errors': 0.03, 'long_share': 0.10,
             'words_per_sentence': 24}

# Each scale is set so one occurrence lands near the knee, and three or four
# reach the cap. Set higher, a single event pins the part and it stops grading.
SCALE = {'tool_errors': 75, 'edit_errors': 44, 'streak': 6, 'run_step': 2,
         'repeats': 30, 'pagers': 6, 'corrections': 15, 'nudges': 15,
         'interrupts': 12, 'self_corrections': 4.5, 'stock_phrases': 12,
         'emdash': 0.5, 'pronouns': 10, 'long_share': 50, 'api_error': 2,
         'praise': 13}

# Raw points to the shown 0-100 scale. The anchors are fitted against a set of
# labelled sessions, so 20, 35 and 55 keep their meaning.
CALIBRATION = ((0.0, 0.0), (18.0, 20.0), (23.0, 35.0), (29.0, 55.0),
               (40.0, 80.0), (55.0, 100.0))

KNEE = 0.3               # share of a cap a part reads at face value below
GLIDE = 8.0              # points the shown score may move on one event
BIAS_CAP = 25.0          # the most a hand move can hold the score down or up
BIAS_SPAN = 35           # events over which a hand move fades to nothing

PAGER_POINTS = 5         # one file viewed through the shell
WHY_WORKS = 3            # weight of "why this works" prose

SIGNALS = ('user_msgs', 'corrections', 'nudges', 'interrupts', 'praise',
           'tool_calls', 'tool_errors', 'edit_calls', 'edit_errors', 'streaks',
           'repeats', 'pagers', 'text_blocks', 'words', 'sentences',
           'long_blocks', 'self_corrections', 'stock_phrases', 'emdashes',
           'pronouns', 'api_errors')

LABEL = {'tool_errors': 'tool errors', 'edit_errors': 'edit errors',
         'streaks': 'error streaks', 'repeats': 'repeated calls',
         'pagers': 'shell file views', 'corrections': 'user corrections',
         'nudges': 'user nudges', 'interrupts': 'interrupts',
         'self_corrections': 'self corrections',
         'stock_phrases': 'stock phrases', 'emdashes': 'em-dashes',
         'pronouns': 'he/him pronouns', 'verbosity': 'verbosity',
         'api_errors': 'api errors', 'praise': 'praise'}

# The name of every word list. The settings file adds patterns under these names.
# The lists in this file hold clean, general English only: no profanity, and no
# short form that stands for it
WORD_LISTS = ('corrections_severe', 'corrections_heavy', 'corrections_plain',
              'nudges', 'praise_high', 'praise_medium', 'praise_low',
              'self_severe', 'self_heavy', 'self_plain', 'stock_phrases')

GAP = r'.{0,40}?'        # the bounded gap a "..." in the word lists stands for


def alt(*parts):
  return re.compile('|'.join(parts), re.I | re.M)


# After a leading "no", these make it a kind answer and not a correction
KIND_NO = (r'need|problems?|worries|rush|hurry|pressure|thanks|thank you|'
           r'complaints?|objections?|doubt|wonder|idea|all (fine|good)')

# "wrong" as a verdict: not the writer's own slip ("wrong window"), not "not
# wrong", and not a question about what goes wrong
WRONG = (r'(?<!go )(?<!goes )(?<!went )(?<!going )(?<!gone )(?<!something )'
         r'(?<!anything )(?<!nothing )(?<!not )\bwrong\b'
         r'(?! (window|tab|chat|terminal|session|with (my|the|this|our|it))\b)')

# "again" beside a greeting or a thank-you is no correction
AGAIN = (r'(?<!hi )(?<!hello )(?<!thanks )(?<!thanks, )(?<!thank you )'
         r'(?<!thank you, )again\b(?![,!]?[ \t]*thank)')

# Corrections, strongest class per message wins. A word that a plain request
# uses as often as a correction does counts in its correcting form only:
# "again, shorter" and not "run it again", "stop guessing" and not "stop the
# server", "why did you" and not "why is the sky blue"
CORRECT_SEVERE = alt(
  r'\bi never asked\b',
  r'\bnonsense\b',
  r'(?:^[ \t]*|[,.;:!>-][ \t]+)' + AGAIN,
  r"\b(never|don't|do not)\b(?! (mind|worry)\b)[^.!?\n]{0,40}?\bagain\b",
  r'\b(not|(doing|did|done) (it|this|that)) again\b',
  r'\bpoor(ly)?\b',
  r'^[ \t]*no\b(?![,.!]?[ \t]+(' + KIND_NO + r')\b)[,\s]',
  r'^[ \t]*no[.!]*[ \t]*$',
)

CORRECT_HEAVY = alt(
  r'^[ \t]*but\b', r'\bi asked\b', r'\bunrelated\b', WRONG,
  r'\bdid not\b', r'\banswer my question\b', r'\bnot want\b',
  r"\bdon't want\b",
  r'^[ \t]*why\b(?:[ \t]*\?*[ \t]*$|' + GAP + r'\b(?:you|your)\b)',
  r'(?<!was )(?<!is )(?<!are )(?<!were )(?<!the )\bstated\b'
  r'(?! (in|on|at|by the)\b)',
  r'\bi even\b', r'\bi wanted\b', r'\bdid i ask\b', r'\bi never\b',
  r'(?<!even or )(?<!even and )\bodd\b(?!-)(?! (numbers?|rows?|index|indexes'
  r'|indices|elements?|digits?|pages?|lines?|values?|length|count|one out'
  r'|or even|and even)\b)',
  r'\btry again[.!]',
  r"(?<!don't )(?<!do not )(?<!not )(?<!-)\bstop"
  r'(?: (?:\w+ing|it|that|this|now|please)\b|[.!,](?=\s|\Z)|[ \t]*\Z)',
  r'\bnope\b',
)

CORRECT_PLAIN = alt(
  r'\bincorrect\b', r'\bnot what i\b', r"\byou didn't\b",
  r'\byou did not\b', r'\byou keep\b',
  r'\byou' + GAP + r'\b(ignored|missed|skipped|forgot|broke|deleted|overwrote|clobbered)\b',
  r'\bundo\b', r'\brevert\b', r'\broll back\b', r'\bredo\b',
  r'\b' + AGAIN,
  r'\bhow many times\b', r'\btold you (already|before)\b',
  r'\bfor the' + GAP + r'\btime\b',
  r'\bas i' + GAP + r'\b(said|asked|told|wrote|instructed)\b',
  r'\bi (just |already )?(said|asked|told|instructed)\b',
  r'\bi never (said|asked)\b', r'\bnope\b',
  r'\bread' + GAP + r'\b(again|properly)\b',
  r'\blook again\b', r'\bcheck again\b',
  r'\bexplain(?:\?|[.!]?[ \t]*\Z| yourself\b'
  r'| why (?:you|did|would|is this|was this)\b)',
  r'\S[ \t]+-[ \t]+explain\b', r'\bunclear\b',
  r'\bwhat are you (talking|doing)\b', r'\bare you (serious|kidding)\b',
  r'\bcome on\b', r'\bmaking (things|stuff) up\b',
  r'\bmade that up\b', r'\bhallucinat', r'\boff on your own\b', r'\bamiss\b',
  r'\bwhy (would|did) you\b', r'\bwho told you\b',
  r'\bdo (a lot |much )?better\b', r'\bfull stop\b', r'\bnot listening\b',
  r"\bthat's not\b", r'\bthis is not\b', r'\bthat is false\b',
  r'\bstill (broken|wrong|failing|fails|not)\b',
  r'\bdoes not (work|match|exist)\b',
  r'\bnot (right|correct|true|good|okay|ok)\b',
  r'\boverdid\b', r'\boverdoing\b', r'\bstop (doing|making|saying)\b',
  r'\bpay attention\b', r"\bdidn't ask (you|for)\b", r"\bi don't like\b",
  r'\bagainst my\b', r'\byou gave\b',
)

CORRECT_TIERS = (('corrections_severe', CORRECT_SEVERE, 5),
                 ('corrections_heavy', CORRECT_HEAVY, 3),
                 ('corrections_plain', CORRECT_PLAIN, 1))

NUDGE = alt(
  r'\bcontinue\b', r'\bkeep going\b', r'\bkeep working\b', r"\bdon't stop\b",
  r'\bdo not stop\b', r'\bcarry on\b', r'\bwhy did you stop\b',
  r'\bwhy have you stopped\b', r'\byou stopped\b', r'\bfinish\b',
  r'\bproceed\b', r'(?<!-)\bresume\b', r'\bstuck\b', r'\bstalled\b', r'\bidle\b',
  r'\bfrozen\b', r'\bnothing happening\b', r'\bno output\b',
  r'\bdid you (stop|die|crash|freeze)\b',
  r'\bare you (done|stuck|there)\b', r'\bstill there\b', r'\beta\b',
  r'\bstatus\?', r'\bany update\b', r'\bupdate\?', r'\bprogress\?',
  r'\bhow long\b', r'\bhurry\b', r'\bmove on\b', r'\bget on with\b',
  r'\bback to work\b', r'\bwake up\b', r'\bhello\?',
)

NOT = r"(?<!not )(?<!n't )"     # "not great" is no praise

# "works" as a verdict: no "how", "nothing" or "not" before it on the line
WORKS = (r"^(?:(?!\b(?:how|nothing|none|not|never|no longer)\b|n't\b).)*"
         r'\bworks\b(?! (best|better)\b)')

# Praise lowers the score. Strongest class per message.
PRAISE_TIERS = (
  ('praise_high',
   alt(NOT + r'\bgreat\b', NOT + r'\bsuperb\b', NOT + r'\bexcellent\b',
       NOT + r'\bperfect\b', r'\bwell done\b'), 2.0),
  ('praise_medium',
   alt(r'\bthanks\b', r'\bthank\b',
       NOT + r'(?<!would )(?<!would be )\bnice\b(?! (to have|if)\b)',
       NOT + r'\bgood work\b'), 1.5),
  ('praise_low',
   alt(r'\bokay good\b',
       WORKS,
       NOT + r'\bhappy\b(?! (paths?|flows?|cases?)\b)'), 1.0),
)

SELF_TIERS = (
  ('self_severe',
   alt(r'\bapolog', r'\bsorry\b', r'\bstand corrected\b',
       r'\bgot' + GAP + r'\bwrong\b', r'\bthat was wrong\b',
       r'\bi was wrong\b', r'\bi am mistaken\b',
       r'\bmy (mistake|error|fault|bad)\b', r'\boops\b', r"\byou're right\b",
       r'\byou are correct\b', r'\byou are' + GAP + r'\bright\b'), 5),
  ('self_heavy',
   alt(r'\bi (completely |totally )?(misread|misunderstood|misjudged|overlooked|conflated|botched|fumbled)\b',
       r'\bi missed\b', r'\bmessed' + GAP + r'\bup\b', r'\bi broke\b',
       r'\bi failed to\b',
       r'\bi introduced' + GAP + r'\b(bug|regression|error|fault)\b',
       r'\bi erred\b', r'\bi mistakenly\b', r'\bi take that back\b'), 3),
  ('self_plain',
   alt(r'\bi should have\b', r"\bi shouldn't have\b", r'\bi should not have\b',
       r'\bmy oversight\b', r'\bthat was my (mistake|error|fault|bug)\b',
       r'\bcorrecting my\b', r'\bcorrect myself\b',
       r'\blet me correct\b', r'\bi must correct\b', r'\bi need to correct\b',
       r'\b(fixed|fixing) my' + GAP + r'\b(bug|mistake|error)\b',
       r'\bi (said|claimed|wrote|gave)( previously| earlier)?' + GAP +
       r'\b(wrong|incorrect|false|bad)\b', r'\bwrongly\b'), 1),
)

STOCK_PHRASES = alt(
  r'\bgreat (question|catch|point)\b', r'\bgood (catch|point)\b',
  r'\bexcellent (question|point)\b', r'\b(fair|valid) point\b',
  r'\bspot on\b', r'\bnailed it\b', r'\bperfect!', r'\bexcellent!',
  r'\babsolutely!', r'\bcertainly!', r'\bi apologize for the confusion\b',
  r"\blet's dive\b", r"\blet's unpack\b", r'\bdeep dive\b', r'\bdive into\b',
  r'\bdelv', r"\blet's break (it|this|that) down\b", r'\bcomprehensive\b',
  r'\brobust\b', r'\bseamless\b', r'\bleverag', r'\bgame-changing\b',
  r'\bcutting-edge\b', r'\bstate-of-the-art\b', r'\bworld-class\b',
  r'\bbest-in-class\b', r'\bblazing\b', r'\bsupercharge\b', r'\bturbocharge\b',
  r'\belevate\b', r'\bempower\b', r'\bstreamline\b',
  r'\beffortless\b', r'\bsynerg', r'\bholistic\b', r'\bparadigm\b',
  r'\bactionable insight\b', r'\btapestry\b', r'\btestament to\b',
  r'\bplays a (vital|crucial|key) role\b', r"\bin today's\b",
  r'\bever-evolving\b', r'\blandscape of\b', r'\brealm of\b', r'\bembark\b',
  r'\bmeticulous\b', r'\bpivotal\b', r'\bundoubtedly\b',
  r"\bit's important to note\b", r'\bworth noting\b', r'\bessentially\b',
  r'\bcrucially\b', r'\binterestingly\b', r'\bthat said\b', r'\bin summary\b',
  r'\bin conclusion\b', r'\bto summarize\b', r'\bto recap\b',
  r'\bin a nutshell\b', r'\blong story short\b', r'\bsimply put\b',
  r'\bin essence\b', r'\bat its core\b', r'\bthe bottom line\b',
  r'\bneedless to say\b', r'\bgoes without saying\b', r"\bhere's the thing\b",
  r'\bthe reality is\b', r'\bmake no mistake\b', r'\brest assured\b',
  r'\bfear not\b', r'\bwithout further ado\b', r'\bmoreover\b',
  r'\bfurthermore\b', r'\bhope this helps\b', r'\bfeel free\b',
  r"\bi'd be happy\b", r'\bhappy to help\b', r'\blet me know if\b',
  r'\bas you can see\b',
  # self-certification: asserting rigour instead of showing it
  r', not a guess(es|work)?\b', r'\bnot speculation\b', r'\bno speculation\b',
  r', not (opinion|noise|promises|hype|fluff|marketing|magic)\b',
  r'\bi assure you\b', r'\btrust me\b', r'\byou can trust\b',
  r'\bi promise\b', r'\brock-solid\b', r'\bbulletproof\b', r'\bironclad\b',
  r'\bguaranteed to\b', r'\bno fluff\b', r'\bzero fluff\b', r'\bno filler\b',
  r'\b(genuinely|truly) (verified|confirmed|tested|checked|works)\b',
  r'\blet me be clear\b', r'\blet me be blunt\b', r'\bto be crystal clear\b',
)

WHY_THIS_WORKS = re.compile(r'\bwhy\b.{0,60}?\bthis\b.{0,60}?\bworks?\b', re.I)
PRONOUN = re.compile(r'\b(he|him)\b', re.I)
SENTENCE = re.compile(r'[.!?](?=\s)')
COMMAND_TAG = re.compile(r'<command-(name|message|args|contents|stdout|stderr)>')
COMPACT = re.compile(r'this session is being continued from a previous', re.I)
INTERRUPT = '[request interrupted by user'
QUOTED = re.compile(r'"[^"\n]*"')
NAME = re.compile(r'(?<!\.)\bclaude\b(?!/)(?![.-]\w)(?!\s+code\b)', re.I)
EM_DASH = '\u2014'
EM_RULE = re.compile(EM_DASH + r'{3,}')   # a ruled line, not prose


def normalise(text):
  # one apostrophe and one quote shape, so the word lists stay plain
  return text.replace('’', "'").replace('“', '"').replace('”', '"')


def stamp(value):
  # an iso timestamp as epoch seconds, None when it is missing or garbage
  if not isinstance(value, str):
    return None
  try:
    return datetime.fromisoformat(value.replace('Z', '+00:00')).timestamp()
  except (ValueError, TypeError, OverflowError):
    return None


def signature(name, payload):
  # stable across processes; the interpreter's own hash is seeded per run
  try:
    canon = json.dumps(payload, sort_keys=True, default=str)[:2000]
  except (TypeError, ValueError):
    canon = str(payload)[:2000]
  raw = (str(name) + '\x00' + canon).encode('utf-8', 'replace')
  return hashlib.blake2b(raw, digest_size=8).hexdigest()


def pager_points(command):
  # a shell display step puts the file on no one's screen but the model's
  if not isinstance(command, str) or not command.strip():
    return 0
  if '|' in command or '<' in command or '>' in command:
    return 0
  if SCRATCH in command:
    return 0
  shown = False
  for step in re.split(r'&&|;|\n', command):
    step = step.strip()
    if not step:
      continue
    head = os.path.basename(step.split()[0])
    if head in DISPLAY:
      shown = True
    elif head not in FREE:
      return 0
  return PAGER_POINTS if shown else 0


def settings_file():
  base = os.environ.get('XDG_CONFIG_HOME') or os.path.expanduser('~/.config')
  return os.path.join(base, 'mariadb-qa', 'session_meter.json')


def labels_file():
  return os.path.join(os.path.dirname(settings_file()),
                      'session_meter_labels.json')


def own_pattern(text):
  # one pattern from the settings file, or None when it cannot be used. A
  # pattern that matches empty text would count on every message
  try:
    pattern = re.compile(text, re.I | re.M)
    return None if pattern.search('') else pattern
  except Exception:
    return None


def read_own(path):
  """The user's own words and switches. A fault drops that one item only."""
  own = {'path': path, 'words': {}, 'marks': [HAND_MARK], 'em_dashes': False,
         'he_him': False, 'zone': None, 'stamp': '', 'faults': []}
  try:
    with open(path, 'rb') as handle:
      raw = handle.read()
  except OSError:
    if os.path.lexists(path):
      own['faults'].append('the file cannot be read')
    return own                          # no settings file: the built-in set
  own['stamp'] = hashlib.blake2b(raw, digest_size=8).hexdigest()
  fault = own['faults'].append
  try:
    data = json.loads(raw.decode('utf-8'))
  except (ValueError, RecursionError):
    data = None
  if not isinstance(data, dict):
    fault('the file is not a json object')
    return own
  for key, value in data.items():
    if key.startswith('_'):
      continue                          # a note for the reader of the file
    if key == 'words' and isinstance(value, dict):
      for name, patterns in value.items():
        if name not in WORD_LISTS:
          fault('words: there is no word list named %s' % name)
          continue
        if not isinstance(patterns, list):
          fault('words: %s needs a list of patterns' % name)
          continue
        for text in patterns:
          pattern = own_pattern(text)
          if pattern is None:
            fault('words: %s holds a pattern that cannot be used: %s'
                  % (name, json.dumps(text)))
          else:
            own['words'].setdefault(name, []).append(pattern)
    elif key == 'hand_marks' and isinstance(value, list):
      for mark in value:
        # a short run with no space, digit, sign or quote in it
        if isinstance(mark, str) and re.fullmatch(r'[^\s\d+\-"]{1,16}', mark):
          if mark.lower() not in own['marks']:
            own['marks'].append(mark.lower())
        else:
          fault('hand_marks: %s cannot be used' % json.dumps(mark))
    elif key == 'count_em_dashes' and isinstance(value, bool):
      own['em_dashes'] = value
    elif key == 'count_he_him' and isinstance(value, bool):
      own['he_him'] = value
    elif (key == 'context_zone' and isinstance(value, list) and len(value) == 2
          and all(type(edge) in (int, float) and math.isfinite(edge)
                  for edge in value)
          and 0 <= value[0] <= value[1]):
      own['zone'] = (value[0], value[1])
    else:
      fault('%s is not understood' % key)
  return own


def hand_pattern(marks):
  # a mark, a sign and a number. A word counts at the start of a line only, so
  # that a sentence about a meter moves nothing. A symbol counts anywhere
  heads = '|'.join((r'^[ \t]*' if re.match(r'\w', mark) else '') +
                   re.escape(mark) for mark in marks)
  return re.compile('(?:' + heads + r')[ ]{0,3}([+-])[ ]{0,3}(\d+(?:\.\d+)?)',
                    re.M)


def configure(path):
  """Read the settings file and build what depends on it."""
  global OWN, HAND_MOVE
  OWN = read_own(path)
  HAND_MOVE = hand_pattern(OWN['marks'])


configure(settings_file())


def found(name, pattern, low, text):
  # a built-in list reads the lowered text, the user's own patterns read the
  # text as it was typed
  if pattern.search(low):
    return True
  return any(own.search(text) for own in OWN['words'].get(name, ()))


def tally(name, pattern, low, text):
  return (len(pattern.findall(low)) +
          sum(len(own.findall(text)) for own in OWN['words'].get(name, ())))


def hand_total(text):
  # the user's own move: quoted text does not count, several moves sum
  total = 0.0
  for sign, number in HAND_MOVE.findall(QUOTED.sub(' ', text)):
    total += float(number) if sign == '+' else -float(number)
  return total


def weight_table():
  table = []
  for count, value in STEPS:
    table.extend([value] * count)
  return table


WEIGHTS = weight_table()


def weight_at(age):
  return WEIGHTS[age] if age < len(WEIGHTS) else 0.0


def compress(points, cap):
  # below the knee a part reads as it counts; above it, it never sits flat
  knee = KNEE * cap
  if points <= knee:
    return points
  return knee + (cap - knee) * math.tanh((points - knee) / (cap - knee))


def expand(points, cap):
  # compress() read backwards, for a value under the cap
  knee = KNEE * cap
  if points <= knee:
    return points
  return knee + (cap - knee) * math.atanh((points - knee) / (cap - knee))


def weighted(ring):
  # the weighted sum of every signal over the window, newest events count most
  out = dict.fromkeys(SIGNALS, 0.0)
  last = len(ring) - 1
  for index, event in enumerate(ring):
    value = weight_at(last - index)
    if not value:
      continue
    for key, count in event.items():
      if key in out:
        out[key] += value * count
  return out


class Check(object):
  """One session's reading, built up incrementally from its transcript."""

  def __init__(self):
    self.reset()

  def reset(self):
    self.ring = deque(maxlen=RING)
    self.shown = 0.0
    self.moves = deque()
    self.cursor = 0
    self.streak = 0
    self.pending = {}
    self.sigs = deque(maxlen=SIGS)
    self.context = 0
    self.model = ''
    self.user_ts = None
    self.gaps = deque(maxlen=GAPS)
    self.opened = False
    self.skipped = 0

  # ---------------------------------------------------------------- scanning

  def scan(self, path):
    size = os.path.getsize(path)
    if size < self.cursor:      # a compact rewrote the file
      self.reset()
    if size == self.cursor:
      return
    with open(path, 'rb') as handle:
      handle.seek(self.cursor)
      raw = handle.read()
    end = raw.rfind(b'\n') + 1  # a half-written last line waits for the next pass
    for line in raw[:end].split(b'\n'):
      if not line.strip():
        continue
      try:
        self.record(json.loads(line))
      except Exception:
        self.skipped += 1       # one odd line costs that line, never the reading
    self.cursor += end

  def record(self, rec):
    if not isinstance(rec, dict):
      raise ValueError('not a record')
    if rec.get('isSidechain') or rec.get('isMeta'):
      return
    event = {}
    if rec.get('isApiErrorMessage'):
      event['api_errors'] = 1
    kind = rec.get('type')
    if kind == 'assistant':
      self.assistant(rec, event)
    elif kind == 'user':
      self.user(rec, event)
    elif kind == 'attachment':
      self.attachment(rec, event)
    self.push(event)

  def push(self, event):
    # only an event carrying a signal takes a window slot
    event = {key: value for key, value in event.items() if value}
    move = event.pop('hand', 0.0)
    if event:
      self.ring.append(event)
      shave(self.ring)
      self.advance()
    if move:
      self.moves.append([0, move])      # at face value on this reading

  def advance(self):
    """Age the hand moves, then walk the shown score one step to the target."""
    for move in self.moves:
      move[0] += 1
    while self.moves and self.moves[0][0] >= BIAS_SPAN:
      self.moves.popleft()
    target = assemble(self.ring)['raw']
    self.shown += max(-GLIDE, min(GLIDE, target - self.shown))

  # ----------------------------------------------------------------- records

  def assistant(self, rec, event):
    message = rec.get('message') or {}
    model = message.get('model')
    if model == '<synthetic>':   # a harness notice, not model output
      return
    if model:
      self.model = model
    usage = message.get('usage') or {}
    if isinstance(usage, dict):
      size = 0
      for key in ('input_tokens', 'cache_read_input_tokens',
                  'cache_creation_input_tokens'):
        value = usage.get(key)
        if isinstance(value, (int, float)):
          size += int(value)
      if size > 1000:            # a smaller call is a subagent or a summary
        self.context = size
    when = stamp(rec.get('timestamp'))
    if self.user_ts is not None:
      if when is not None:
        span = when - self.user_ts
        if 0 <= span <= 3600:
          self.gaps.append(span)
      self.user_ts = None
    content = message.get('content')
    if not isinstance(content, list):
      return
    for block in content:
      if not isinstance(block, dict):
        continue
      if block.get('type') == 'text':
        self.text_block(block.get('text'), event)
      elif block.get('type') == 'tool_use':
        self.tool_use(block, event)

  def text_block(self, text, event):
    if not isinstance(text, str) or not text.strip():
      return
    event['text_blocks'] = event.get('text_blocks', 0) + 1
    words = len(text.split())
    event['words'] = event.get('words', 0) + words
    event['sentences'] = (event.get('sentences', 0) +
                          max(1, len(SENTENCE.findall(text))))
    if words > LONG_BLOCK:
      event['long_blocks'] = event.get('long_blocks', 0) + 1
    plain = normalise(text)
    low = plain.lower()
    for name, pattern, value in SELF_TIERS:
      if found(name, pattern, low, plain):
        event['self_corrections'] = event.get('self_corrections', 0) + value
        break
    hits = (tally('stock_phrases', STOCK_PHRASES, low, plain) +
            WHY_WORKS * len(WHY_THIS_WORKS.findall(low)))
    if hits:
      event['stock_phrases'] = event.get('stock_phrases', 0) + hits
    if OWN['em_dashes']:
      dashes = text.count(EM_DASH) - sum(len(run) for run in EM_RULE.findall(text))
      if dashes:
        event['emdashes'] = event.get('emdashes', 0) + dashes
    if OWN['he_him']:
      pronouns = len(PRONOUN.findall(low))
      if pronouns:
        event['pronouns'] = event.get('pronouns', 0) + pronouns

  def tool_use(self, block, event):
    name = block.get('name') or ''
    event['tool_calls'] = event.get('tool_calls', 0) + 1
    if name in EDIT_TOOLS:
      event['edit_calls'] = event.get('edit_calls', 0) + 1
    payload = block.get('input')
    if name == SHELL_TOOL and isinstance(payload, dict):
      points = pager_points(payload.get('command'))
      if points:
        event['pagers'] = event.get('pagers', 0) + points
    call_id = block.get('id')
    if call_id:
      if len(self.pending) > PENDING_CAP:
        keep = list(self.pending.items())[len(self.pending) // 2:]
        self.pending = dict(keep)
      self.pending[call_id] = name
    mark = signature(name, payload)
    if mark in self.sigs:
      event['repeats'] = event.get('repeats', 0) + 1
    self.sigs.append(mark)

  def user(self, rec, event):
    message = rec.get('message') or {}
    content = message.get('content')
    if isinstance(content, list):
      results = [b for b in content
                 if isinstance(b, dict) and b.get('type') == 'tool_result']
      if results:
        for block in results:
          self.tool_result(block, event)
        return
      text = ' '.join(b.get('text') or '' for b in content
                      if isinstance(b, dict) and b.get('type') == 'text')
    elif isinstance(content, str):
      text = content
    else:
      return
    self.prompt(text, stamp(rec.get('timestamp')), event)

  def tool_result(self, block, event):
    name = self.pending.pop(block.get('tool_use_id'), '')
    if block.get('is_error'):
      event['tool_errors'] = event.get('tool_errors', 0) + 1
      self.streak += 1
      if self.streak == 3:
        event['streaks'] = event.get('streaks', 0) + 1
      event['run_len'] = max(event.get('run_len', 0), self.streak)
      if name in EDIT_TOOLS:
        event['edit_errors'] = event.get('edit_errors', 0) + 1
    else:
      self.streak = 0

  def attachment(self, rec, event):
    body = rec.get('attachment')
    if not isinstance(body, dict) or body.get('type') != 'queued_command':
      return                      # every other sub-type is harness noise
    origin = body.get('origin')
    if not isinstance(origin, dict) or origin.get('kind') != 'human':
      return                      # an agent's queued text is not user feedback
    self.prompt(body.get('prompt'), stamp(rec.get('timestamp')), event)

  def prompt(self, text, when, event):
    if not isinstance(text, str):
      return
    text = normalise(text).strip()
    if not text:
      return
    if text.startswith('<') or COMMAND_TAG.search(text):
      return                      # hook and command output, the meter's own line included
    if COMPACT.match(text):
      self.opened = True
      return
    if text.lower().startswith(INTERRUPT):
      event['interrupts'] = event.get('interrupts', 0) + 1
      return
    event['user_msgs'] = event.get('user_msgs', 0) + 1
    if when is not None:
      self.user_ts = when
    opening = not self.opened
    self.opened = True
    if len(text) > PASTE:         # a paste or a log: counted, not scanned
      return
    low = text.lower()
    value = 0
    for name, pattern, tier in CORRECT_TIERS:
      if found(name, pattern, low, text):
        value = tier
        break
    if value and not opening:
      value += len(NAME.findall(low))
    if value:
      event['corrections'] = event.get('corrections', 0) + value
    if found('nudges', NUDGE, low, text):
      event['nudges'] = event.get('nudges', 0) + 1
    for name, pattern, tier in PRAISE_TIERS:
      if found(name, pattern, low, text):
        event['praise'] = event.get('praise', 0) + tier
        break
    move = hand_total(low)
    if move:
      event['hand'] = event.get('hand', 0) + move


# ------------------------------------------------------------------- scoring


def assemble(ring):
  """Every part of the score for one window, before the zero clamp."""
  sums = weighted(ring)
  runs = max([event.get('run_len', 0) for event in ring] or [0])
  events = len(ring)
  rows = []

  def rate(top, base, floor=0.0):
    base = max(base, floor)
    return top / base if base > 0 else 0.0

  def share_of(name, top, base):
    # every rate carries a floor under its base, or a small base pins the cap
    return rate(sums[top], sums[base], FLOOR[name])

  def add(name, count, base, points):
    points = compress(max(0.0, points), CAPS[name])
    rows.append({'part': name, 'weighted': count, 'base': base,
                 'points': points})
    return points

  positive = 0.0
  positive += add('tool_errors', sums['tool_errors'], sums['tool_calls'],
                  (share_of('tool_errors', 'tool_errors', 'tool_calls') -
                   FREE_RATE['tool_errors']) * SCALE['tool_errors'])
  positive += add('edit_errors', sums['edit_errors'], sums['edit_calls'],
                  (share_of('edit_errors', 'edit_errors', 'edit_calls') -
                   FREE_RATE['edit_errors']) * SCALE['edit_errors'])
  positive += add('streaks', sums['streaks'], 0.0,
                  SCALE['streak'] * sums['streaks'] +
                  SCALE['run_step'] * max(0, runs - 3))
  positive += add('repeats', sums['repeats'], sums['tool_calls'],
                  share_of('repeats', 'repeats', 'tool_calls') * SCALE['repeats'])
  positive += add('pagers', sums['pagers'], sums['tool_calls'],
                  share_of('pagers', 'pagers', 'tool_calls') * SCALE['pagers'])
  positive += add('corrections', sums['corrections'], sums['user_msgs'],
                  share_of('corrections', 'corrections', 'user_msgs') *
                  SCALE['corrections'])
  positive += add('nudges', sums['nudges'], sums['user_msgs'],
                  share_of('nudges', 'nudges', 'user_msgs') * SCALE['nudges'])
  positive += add('interrupts', sums['interrupts'],
                  max(sums['user_msgs'], FLOOR['interrupts']),
                  share_of('interrupts', 'interrupts', 'user_msgs') *
                  SCALE['interrupts'])
  positive += add('self_corrections', sums['self_corrections'],
                  sums['text_blocks'],
                  share_of('self_corrections', 'self_corrections', 'text_blocks') *
                  SCALE['self_corrections'])
  positive += add('stock_phrases', sums['stock_phrases'], sums['text_blocks'],
                  share_of('stock_phrases', 'stock_phrases', 'text_blocks') *
                  SCALE['stock_phrases'])
  if OWN['em_dashes']:
    positive += add('emdashes', sums['emdashes'], 0.0,
                    SCALE['emdash'] * sums['emdashes'])
  if OWN['he_him']:
    positive += add('pronouns', sums['pronouns'], sums['text_blocks'],
                    share_of('pronouns', 'pronouns', 'text_blocks') *
                    SCALE['pronouns'])
  share = share_of('long_share', 'long_blocks', 'text_blocks')
  per_sentence = rate(sums['words'], sums['sentences'])
  positive += add('verbosity', sums['long_blocks'], sums['text_blocks'],
                  max(0.0, share - FREE_RATE['long_share']) *
                  SCALE['long_share'] +
                  max(0.0, per_sentence - FREE_RATE['words_per_sentence']) / 2)
  positive += add('api_errors', sums['api_errors'], 0.0,
                  SCALE['api_error'] * sums['api_errors'])
  praise = add('praise', sums['praise'], sums['user_msgs'],
               share_of('praise', 'praise', 'user_msgs') * SCALE['praise'])

  ramp = min(1.0, events / float(RAMP_AT)) if RAMP_AT else 1.0
  raw = (positive - praise) * ramp
  return {'raw': raw, 'rows': rows, 'positive': positive, 'praise': praise,
          'ramp': ramp, 'sums': sums, 'runs': runs, 'events': events,
          'words_per_sentence': per_sentence}


def shave(ring):
  """Keep no credit the zero floor refuses, newest event first."""
  credit = False
  last = len(ring) - 1
  for index, event in enumerate(ring):
    if weight_at(last - index) <= 0:
      continue
    if event.get('praise', 0) > 0:
      credit = True
      break
  if not credit:
    return
  # the praise that cancels the other parts exactly is kept: their total, read
  # back through the curve and the floored base of the praise rate. The rest
  # goes, newest credit first. A further pass only clears a rounding remainder
  for _ in range(12):
    parts = assemble(ring)
    if parts['raw'] >= -1e-9:
      return
    base = max(parts['sums']['user_msgs'], FLOOR['praise'])
    keep = expand(parts['positive'], CAPS['praise']) * base / SCALE['praise']
    need = parts['sums']['praise'] - keep
    if need <= 1e-12:
      return
    for index in range(last, -1, -1):
      if need <= 1e-12:
        break
      value = weight_at(last - index)
      praise = ring[index].get('praise', 0.0)
      if praise <= 0 or value <= 0:
        continue
      take = min(praise, need / value)
      ring[index]['praise'] = praise - take
      need -= take * value


def bias(moves):
  """What the hand moves are still worth, newest at face value."""
  total = 0.0
  for age, amount in moves:
    if age < BIAS_SPAN:
      total += amount * (1.0 - age / float(BIAS_SPAN))
  return max(-BIAS_CAP, min(BIAS_CAP, total))


def calibrate(raw):
  """The shown score for a raw point total, straight between the anchors."""
  if raw <= CALIBRATION[0][0]:
    return CALIBRATION[0][1]
  for (x0, y0), (x1, y1) in zip(CALIBRATION, CALIBRATION[1:]):
    if raw <= x1:
      return y0 + (y1 - y0) * (raw - x0) / (x1 - x0)
  last, top = CALIBRATION[-2], CALIBRATION[-1]
  slope = (top[1] - last[1]) / (top[0] - last[0])
  return top[1] + slope * (raw - top[0])


def shown(value):
  return int(math.floor(value + 0.5))


def band(value):
  place = shown(value)
  for index, cut in enumerate(CUTS):
    if place < cut:
      return index
  return len(CUTS)


def median(values):
  values = sorted(values)
  if not values:
    return None
  middle = len(values) // 2
  if len(values) % 2:
    return values[middle]
  return (values[middle - 1] + values[middle]) / 2.0


def reading(check):
  parts = assemble(check.ring)
  parts['bias'] = bias(check.moves)
  parts['target'] = parts['raw']
  score = min(100.0, max(0.0,
                         round(calibrate(check.shown) + parts['bias'], 4)))
  parts['score'] = score
  parts['band'] = band(score)
  parts['mark'] = MARKS[parts['band']]
  parts['model'] = check.model
  parts['context'] = check.context
  zone = OWN['zone']
  parts['zone'] = bool(zone) and zone[0] <= check.context <= zone[1]
  parts['gap'] = median(check.gaps)
  parts['skipped'] = check.skipped
  return parts


# --------------------------------------------------------------------- cache


def cache_dir():
  # made for the owner only: a transcript is private, and so is what is counted
  base = os.environ.get('XDG_CACHE_HOME') or os.path.expanduser('~/.cache')
  return os.path.join(base, 'claude-session-meter')


def cache_file(session):
  safe = re.sub(r'[^A-Za-z0-9._-]', '_', str(session))[:80] or 'session'
  return os.path.join(cache_dir(), safe + '.json')


def numbers(values):
  return all(isinstance(value, (int, float)) for value in values)


def load(session, path):
  """The stored reading for this session, or a fresh check."""
  check = Check()
  try:
    with open(cache_file(session)) as handle:
      state = json.load(handle)
  except (OSError, ValueError):
    return check
  if not isinstance(state, dict):
    return check
  try:
    if state.get('version') != VERSION or state.get('path') != path:
      return Check()                       # rules changed, or another file
    if state.get('own') != OWN['stamp']:
      return Check()                       # the settings file changed
    if os.path.getsize(path) < state.get('cursor', 0):
      return Check()                       # a compact rewrote the transcript
    ring = state.get('ring', [])
    moves = state.get('moves', [])
    gaps = state.get('gaps', [])
    when = state.get('user_ts')
    # a ring or a gap list holding anything but numbers would raise later, in
    # the middle of a score. Refuse it here, where a rescan still heals it
    if not all(isinstance(e, dict) and numbers(e.values()) for e in ring):
      return Check()
    if not numbers(gaps) or not (when is None or isinstance(when, (int, float))):
      return Check()
    if not all(isinstance(m, list) and len(m) == 2 and numbers(m) for m in moves):
      return Check()
    if not isinstance(state.get('shown', 0.0), (int, float)):
      return Check()
    check.cursor = int(state.get('cursor', 0))
    check.ring = deque(ring, maxlen=RING)
    check.shown = float(state.get('shown', 0.0))
    check.moves = deque(moves)
    check.streak = int(state.get('streak', 0))
    check.pending = dict(state.get('pending', {}))
    check.sigs = deque(state.get('sigs', []), maxlen=SIGS)
    check.context = int(state.get('context', 0))
    check.model = state.get('model') or ''
    check.user_ts = when
    check.gaps = deque(gaps, maxlen=GAPS)
    check.opened = bool(state.get('opened'))
    check.skipped = int(state.get('skipped', 0))
  except (OSError, ValueError, TypeError):
    return Check()
  return check


def save(check, session, path):
  state = {'version': VERSION, 'own': OWN['stamp'], 'path': path,
           'cursor': check.cursor,
           'ring': list(check.ring), 'shown': check.shown,
           'moves': [list(move) for move in check.moves], 'streak': check.streak,
           'pending': check.pending, 'sigs': list(check.sigs),
           'context': check.context, 'model': check.model,
           'user_ts': check.user_ts, 'gaps': list(check.gaps),
           'opened': check.opened, 'skipped': check.skipped}
  target = cache_file(session)
  temp = '%s.%d.tmp' % (target, os.getpid())    # two writers can serve one session
  try:
    os.makedirs(cache_dir(), mode=0o700, exist_ok=True)
    with open(temp, 'w') as handle:
      json.dump(state, handle)
    os.replace(temp, target)
  except (OSError, TypeError, ValueError):
    try:
      os.unlink(temp)
    except OSError:
      pass


def spawn_scan(session, path):
  """One detached catch-up scan, so a cold cache never stalls the bar."""
  marker = cache_file(session) + '.scan'
  try:
    if time.time() - os.path.getmtime(marker) < SPAWN_WINDOW:
      return
  except OSError:
    pass
  try:
    os.makedirs(cache_dir(), mode=0o700, exist_ok=True)
    open(marker, 'w').close()
    subprocess.Popen(
      [sys.executable, os.path.realpath(__file__), '--scan',
       '--transcript', path, '--session', str(session)],
      stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
      stderr=subprocess.DEVNULL, start_new_session=True)
  except OSError:
    pass


def live(session, path, update=True):
  """The reading for a running session, scanned on from the cached cursor."""
  check = load(session, path)
  backlog = os.path.getsize(path) - check.cursor
  if backlog > BIG_BACKLOG:
    spawn_scan(session, path)
    return check, True
  if update and backlog > 0:
    check.scan(path)
    save(check, session, path)
  return check, False


# ------------------------------------------------------------------- outputs


def segment(path, session):
  """The status bar string: the score, its band, and the context zone mark."""
  if os.path.isfile(path):
    check, behind = live(session, path)
    if behind and not check.ring:
      return '⋯'                     # the child is still catching up
  else:
    check = Check()                    # the transcript is not written yet
  view = reading(check)
  text = '%s%d' % (view['mark'], shown(view['score']))
  if view['zone']:
    text += '⚠'
  return text


def size(count):
  if count >= 1000000:
    return '%.1fM' % (count / 1000000.0)
  if count >= 1000:
    return '%dk' % round(count / 1000.0)
  return str(count)


def report(view):
  names = ('green', 'yellow', 'orange', 'red')
  head = 'session meter %d %s %s' % (shown(view['score']), view['mark'],
                                    names[view['band']])
  if view['ramp'] < 1:
    head += '   low evidence: %d of %d events' % (view['events'], RAMP_AT)
  lines = [head]
  second = 'model %s   context %s' % (view['model'] or 'unknown',
                                      size(view['context']))
  if view['zone']:
    second += ' ⚠ in the context zone of the settings file'
  lines.append(second)
  if view['gap'] is not None:
    lines.append('median response gap %ds over the last %d' %
                 (round(view['gap']), GAPS))
  if view['skipped']:
    lines.append('WARNING: %d transcript lines could not be read' %
                 view['skipped'])
  if OWN['faults']:
    lines.append('WARNING: items of the settings file left out: %d, see '
                 '--settings' % len(OWN['faults']))
  lines.append('')
  lines.append('%-18s %9s %9s %8s' % ('part', 'weighted', 'base', 'points'))
  for row in view['rows']:
    base = '%9.2f' % row['base'] if row['base'] else '        -'
    points = -row['points'] if row['part'] == 'praise' else row['points']
    lines.append('%-18s %9.2f %s %8.2f' %
                 (LABEL[row['part']], row['weighted'], base, points))
  lines.append('%-18s %9s %9s %8.2f' % ('total', '', '', view['score']))
  return '\n'.join(lines)


def as_json(view):
  return json.dumps({
    'score': round(view['score'], 2),
    'band': ('green', 'yellow', 'orange', 'red')[view['band']],
    'evidence': round(view['ramp'], 4),
    'events': view['events'],
    'points': {row['part']: round(row['points'], 4) for row in view['rows']},
    'weighted': {key: round(value, 4) for key, value in view['sums'].items()},
    'model': view['model'],
    'context': view['context'],
    'context_zone': view['zone'],
    'median_gap': view['gap'],
    'skipped_lines': view['skipped'],
    'longest_run': view['runs'],
  }, indent=2)


def full(path):
  """A one-shot reading of a whole transcript. The live cursor is untouched."""
  check = Check()
  check.scan(path)
  return reading(check)


def trace(path):
  """The shown score after every signal event, over one whole transcript."""
  check = Check()
  out = []
  with open(path, 'rb') as handle:
    for line in handle:
      if not line.strip():
        continue
      try:
        check.record(json.loads(line))
      except Exception:
        continue
      out.append(calibrate(check.shown))
  return out


def find_session(session):
  base = os.path.expanduser('~/.claude/projects')
  for root, _, names in os.walk(base):
    for name in names:
      if name.startswith(session) and name.endswith('.jsonl'):
        return os.path.join(root, name)
  return None


def labelled(path):
  """Every labelled session with its peak reading, for the calibration."""
  try:
    with open(path) as handle:
      marks = json.load(handle)['labels']
    marks = sorted(marks.items())
  except (OSError, ValueError, KeyError, TypeError, AttributeError):
    return None
  rows = []
  for session, label in marks:
    found_at = find_session(session)
    if label not in (0, 1, 2) or not found_at:
      continue
    line = trace(found_at)
    if line:
      rows.append((session, label, max(line), line[-1]))
  return rows


def calibration_report(rows):
  names = {0: 'fine', 1: 'friction', 2: 'failed'}
  groups = {}
  for _, label, peak, _ in rows:
    groups.setdefault(label, []).append(peak)
  lines = []
  for label in sorted(groups):
    values = groups[label]
    lines.append('%-9s n=%-3d  median peak %5.1f' %
                 (names[label], len(values), median(values)))
  fail, fine = groups.get(2, []), groups.get(0, [])
  if fail and fine:
    lines.append('')
    for cut in CUTS[1:]:
      caught = sum(1 for value in fail if value >= cut)
      alarms = sum(1 for value in fine if value >= cut)
      lines.append('cut %2d: caught %d of %d failed, %d of %d fine raised it'
                   % (cut, caught, len(fail), alarms, len(fine)))
  return '\n'.join(lines)


def settings_report():
  """What the settings file added, and every item of it that was left out."""
  lines = ['settings file %s' % OWN['path']]
  if not OWN['stamp'] and not OWN['faults']:
    lines.append('not there: the built-in word lists and switches are in use')
    return '\n'.join(lines)
  for name in WORD_LISTS:
    if OWN['words'].get(name):
      lines.append('%-20s own patterns: %d' % (name, len(OWN['words'][name])))
  lines.append('%-20s %s' % ('hand marks', ' '.join(OWN['marks'])))
  lines.append('%-20s %s' % ('em-dashes', 'counted' if OWN['em_dashes'] else 'off'))
  lines.append('%-20s %s' % ('he/him pronouns',
                             'counted' if OWN['he_him'] else 'off'))
  lines.append('%-20s %s' % ('context zone', '%d to %d' % OWN['zone']
                             if OWN['zone'] else 'off'))
  for fault in OWN['faults']:
    lines.append('WARNING: left out: %s' % fault)
  return '\n'.join(lines)


def top_parts(view, limit=2):
  rows = [row for row in view['rows']
          if row['part'] != 'praise' and row['points'] >= 1.0]
  rows.sort(key=lambda row: row['points'], reverse=True)
  return ', '.join('%s %.0f' % (LABEL[row['part']], row['points'])
                   for row in rows[:limit])


# ----------------------------------------------------------------------- cli


def argument(name, argv):
  try:
    return argv[argv.index(name) + 1]
  except (ValueError, IndexError):
    return None


def main(argv):
  if '--segment' in argv or '--scan' in argv:
    quiet = '--scan' in argv
    try:
      path = argument('--transcript', argv)
      session = argument('--session', argv)
      if not path:
        data = json.load(sys.stdin)
        path = data.get('transcript_path')
        session = data.get('session_id')
      if not path or not session:
        return 0
      if quiet:
        if not os.path.exists(path):
          return 0
        check = load(session, path)
        check.scan(path)
        save(check, session, path)
        return 0
      text = segment(path, session)
      if text:
        print(text)
    except Exception:
      pass                                 # the bar must never break
    return 0

  if '--settings' in argv:
    # half of a character pair in the file prints as a question mark
    print(settings_report().encode('utf-8', 'replace').decode('utf-8'))
    return 0

  if '--calibrate' in argv:
    path = argument('--calibrate', argv) or labels_file()
    rows = labelled(path)
    if not rows:
      sys.stderr.write('no labelled session found through %s\n' % path)
      return 2
    print(calibration_report(rows))
    return 0

  if '--replay' in argv:
    path = argument('--replay', argv)
    if not path or not os.path.isfile(path):
      sys.stderr.write('usage: session_meter.py --replay <transcript.jsonl>\n')
      return 2
    line = trace(path)
    for index, value in enumerate(line):
      print('%5d %6.1f %s' % (index, value, MARKS[band(value)]))
    if line:
      print('peak %.1f   end %.1f' % (max(line), line[-1]))
    return 0

  mode = '--json' if '--json' in argv else '--report'
  path = None
  for item in argv[1:]:
    if not item.startswith('--'):
      path = item
      break
  if not path or not os.path.isfile(path):
    sys.stderr.write(
      'usage: session_meter.py [--report|--json] <transcript.jsonl>\n'
      '       session_meter.py --segment [--transcript P --session S]\n'
      '       session_meter.py --replay <transcript.jsonl>\n'
      '       session_meter.py --calibrate [labels.json]\n'
      '       session_meter.py --settings\n')
    return 2
  view = full(path)
  print(as_json(view) if mode == '--json' else report(view))
  return 0


if __name__ == '__main__':
  sys.exit(main(sys.argv))
