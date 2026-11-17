#!/usr/bin/env python3
"""Self-tests for the session meter. Run: python3 session_meter_test.py"""

import atexit
import copy
import hashlib
import inspect
import json
import os
import random
import shutil
import subprocess
import sys
import tempfile
import unittest

# The tests run without a settings file, so every reading is a built-in one.
# A test that needs settings writes its own file and reads it with Settings.
CONFIG = tempfile.mkdtemp()
atexit.register(shutil.rmtree, CONFIG, True)
os.environ['XDG_CONFIG_HOME'] = CONFIG

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import session_meter as sm

METER = os.path.join(HERE, 'session_meter.py')
HOOK = os.path.join(HERE, 'session_meter_hook.py')
NO_SETTINGS = sm.settings_file()
TS = '2026-01-01T00:00:%02d.000Z'
OWN_MARK = '\U0001F642'     # a symbol a settings file adds as a hand mark

# The cache version must move whenever parsing or scoring moves. Bump VERSION
# in the meter and the fingerprint here together.
FINGERPRINTS = {2: '42a96c069dd7bbf2'}


def fingerprint():
  pieces = [inspect.getsource(sm.assemble), inspect.getsource(sm.shave),
            inspect.getsource(sm.Check), inspect.getsource(sm.pager_points),
            inspect.getsource(sm.found), inspect.getsource(sm.tally),
            inspect.getsource(sm.hand_total), inspect.getsource(sm.hand_pattern),
            repr(sm.CAPS), repr(sm.SCALE), repr(sm.FREE_RATE), repr(sm.STEPS),
            repr(sm.CUTS), repr(sm.RING), repr(sm.RAMP_AT), repr(sm.PASTE),
            repr(sm.LONG_BLOCK), repr(sorted(sm.FLOOR.items())),
            repr(sm.PAGER_POINTS), repr(sm.WHY_WORKS), repr(sm.HAND_MARK),
            inspect.getsource(sm.compress), inspect.getsource(sm.expand),
            inspect.getsource(sm.bias), repr(sm.KNEE), repr(sm.GLIDE),
            repr(sm.BIAS_CAP), repr(sm.BIAS_SPAN)]
  for group in (sm.CORRECT_TIERS, sm.PRAISE_TIERS, sm.SELF_TIERS):
    pieces.extend('%s|%s|%s' % (n, p.pattern, v) for n, p, v in group)
  for one in (sm.NUDGE, sm.STOCK_PHRASES, sm.NAME, sm.SENTENCE):
    pieces.append(one.pattern)
  return hashlib.blake2b(''.join(pieces).encode('utf-8'),
                         digest_size=8).hexdigest()


class Settings(object):
  """Run a block with a settings file in place, then go back to none."""

  def __init__(self, body):
    self.body = body if isinstance(body, str) else json.dumps(body)

  def __enter__(self):
    handle = tempfile.NamedTemporaryFile('w', suffix='.json', delete=False,
                                         encoding='utf-8')
    handle.write(self.body)
    handle.close()
    self.path = handle.name
    sm.configure(self.path)
    return sm.OWN

  def __exit__(self, *fault):
    sm.configure(NO_SETTINGS)
    os.unlink(self.path)


def user(text, second=0):
  return {'type': 'user', 'timestamp': TS % second,
          'message': {'role': 'user', 'content': text}}


def assistant(text=None, tools=(), model='claude-test-1', usage=None, second=0):
  content = []
  if text is not None:
    content.append({'type': 'text', 'text': text})
  for call in tools:
    content.append(dict(call, type='tool_use'))
  return {'type': 'assistant', 'timestamp': TS % second,
          'message': {'model': model, 'usage': usage or {}, 'content': content}}


def call(name='Bash', cid='t1', payload=None):
  return {'id': cid, 'name': name, 'input': payload or {'command': 'true'}}


def result(cid='t1', error=False, second=0):
  return {'type': 'user', 'timestamp': TS % second,
          'message': {'role': 'user', 'content': [
            {'type': 'tool_result', 'tool_use_id': cid, 'is_error': error,
             'content': 'x'}]}}


def queued(text, kind='human'):
  origin = {'kind': kind} if kind else None
  return {'type': 'attachment', 'timestamp': TS % 0,
          'attachment': {'type': 'queued_command', 'prompt': text,
                         'origin': origin}}


def scanned(text, opened=True):
  # one prompt through the word pipeline, before the ring and its credit shave
  check = sm.Check()
  check.opened = opened
  event = {}
  check.prompt(text, None, event)
  return event


def fed(*records, **kwargs):
  check = sm.Check()
  check.opened = kwargs.get('opened', True)
  for record in records:
    check.record(record)
  return check


def last(check, key):
  return check.ring[-1].get(key, 0) if check.ring else 0


def full_reading(path):
  # a cold read of the whole file, with no cache in play
  check = sm.Check()
  check.scan(path)
  return sm.reading(check)


def write(records, escaped=True):
  # escaped=False leaves text outside ASCII as typed, as a live transcript does
  handle = tempfile.NamedTemporaryFile('w', suffix='.jsonl', delete=False,
                                       encoding='utf-8')
  for record in records:
    handle.write(json.dumps(record, ensure_ascii=escaped) + '\n')
  handle.close()
  return handle.name


def config_dir(body):
  # a config home holding one settings file, for a run in a process of its own
  home = tempfile.mkdtemp()
  os.makedirs(os.path.join(home, 'mariadb-qa'))
  with open(os.path.join(home, 'mariadb-qa', 'session_meter.json'), 'wb') as handle:
    handle.write(body if isinstance(body, bytes) else
                 (body if isinstance(body, str) else json.dumps(body)).encode('utf-8'))
  return home


class HandMove(unittest.TestCase):

  def move(self, text):
    return scanned(text).get('hand', 0)

  def test_plus_and_minus(self):
    self.assertEqual(self.move('meter +10'), 10)
    self.assertEqual(self.move('meter -4'), -4)
    self.assertEqual(self.move('Meter +2.5'), 2.5)

  def test_spacing(self):
    self.assertEqual(self.move('meter+7'), 7)
    self.assertEqual(self.move('meter   +   7'), 7)
    self.assertEqual(self.move('  \tmeter +7'), 7)

  def test_four_spaces_does_nothing(self):
    self.assertEqual(self.move('meter    +7'), 0)
    self.assertEqual(self.move('meter+    7'), 0)

  def test_bare_does_nothing(self):
    self.assertEqual(self.move('meter that hurt'), 0)
    self.assertEqual(self.move('meter 7'), 0)

  def test_two_moves_sum(self):
    self.assertEqual(self.move('meter +10\nmeter -4'), 6)

  def test_the_word_counts_at_the_start_of_a_line_only(self):
    self.assertEqual(self.move('move the meter +10'), 0)
    self.assertEqual(self.move('the parking meter - 2 hours'), 0)
    self.assertEqual(self.move('thermometer +5'), 0)
    self.assertEqual(self.move('meters +5'), 0)
    self.assertEqual(self.move('well done\nmeter -5'), -5)

  def test_quoted_is_ignored(self):
    self.assertEqual(self.move('the note said\n"meter +10" and no more'), 0)

  def test_open_quote_does_not_shield_the_next_line(self):
    self.assertEqual(self.move('a "quote\nmeter +5'), 5)

  def test_a_symbol_from_the_settings_counts_anywhere(self):
    with Settings({'hand_marks': [OWN_MARK]}):
      self.assertEqual(self.move('%s +10 and %s -4' % (OWN_MARK, OWN_MARK)), 6)
      self.assertEqual(self.move('go on %s-40' % OWN_MARK), -40)
      self.assertEqual(self.move('it said "%s +10" there' % OWN_MARK), 0)
      self.assertEqual(self.move('meter +3'), 3)      # the built-in mark stays
    self.assertEqual(self.move('%s +10' % OWN_MARK), 0)

  def test_queued_counts_human_only(self):
    self.assertEqual(fed(queued('meter +9')).moves[-1][1], 9)
    self.assertEqual(fed(queued('meter +9', kind='peer')).ring, sm.deque([]))
    self.assertEqual(fed(queued('meter +9', kind=None)).ring, sm.deque([]))

  def test_paste_gate_blocks_the_move(self):
    self.assertEqual(self.move('x' * 2100 + '\nmeter +9'), 0)

  def test_assistant_text_never_moves(self):
    check = fed(assistant('meter +50\nall fine'))
    self.assertEqual(last(check, 'hand'), 0)
    self.assertEqual(len(check.moves), 0)

  def test_flat_at_full_weight(self):
    check = fed(user('meter +12'))
    self.assertAlmostEqual(sm.bias(check.moves), 12.0)

  def test_a_move_past_the_cap_is_held_at_the_cap(self):
    self.assertEqual(sm.bias(fed(user('meter +500')).moves), sm.BIAS_CAP)
    self.assertEqual(sm.bias(fed(user('meter -500')).moves), -sm.BIAS_CAP)

  def test_a_move_fades_over_its_span(self):
    check = fed(user('meter -10'))
    half = sm.BIAS_SPAN // 2
    for _ in range(half):
      check.push({'api_errors': 1})
    self.assertAlmostEqual(sm.bias(check.moves), -10 * (1 - half / float(sm.BIAS_SPAN)))
    for _ in range(sm.BIAS_SPAN):
      check.push({'api_errors': 1})
    self.assertEqual(sm.bias(check.moves), 0.0)


class WordTiers(unittest.TestCase):

  def corr(self, text):
    return last(fed(user(text)), 'corrections')

  def test_severe(self):
    self.assertEqual(self.corr('i never asked for that'), 5)
    self.assertEqual(self.corr('that is nonsense'), 5)
    self.assertEqual(self.corr('you did it again'), 5)
    self.assertEqual(self.corr('no, that is not it'), 5)
    self.assertEqual(self.corr('no'), 5)

  def test_heavy(self):
    self.assertEqual(self.corr('but I asked for the other one'), 3)
    self.assertEqual(self.corr('that is unrelated'), 3)
    self.assertEqual(self.corr('why are you doing that'), 3)

  def test_plain(self):
    self.assertEqual(self.corr('you keep doing it'), 1)
    self.assertEqual(self.corr('please explain'), 1)
    self.assertEqual(self.corr('revert that'), 1)

  def test_strongest_class_wins(self):
    self.assertEqual(self.corr('no, you keep making things up'), 5)

  def test_check_again_is_plain_not_severe(self):
    self.assertEqual(self.corr('check again please'), 1)

  def test_a_plain_request_is_not_a_correction(self):
    for text in ('stop the server', 'how do I stop a running job',
                 'run ./stop.sh first', 'why is the sky blue',
                 'why does this test fail?', 'print the odd numbers',
                 'as stated in the docs', 'it was stated that the fix is in',
                 'please explain the plan', "what's wrong with my code?",
                 'where did it go wrong'):
      self.assertEqual(self.corr(text), 0, text)
    for text in ('run the tests again', 'try again please'):
      self.assertEqual(self.corr(text), 1, text)

  def test_a_kind_reply_is_not_a_correction(self):
    for text in ('no problem', 'no worries', 'no rush, take your time',
                 'no need to do that', 'No, all fine.', 'no thanks',
                 'Hi again!', 'thanks again', 'Thanks, again, for the help',
                 'again, thank you', 'sorry, wrong window',
                 "you're not wrong"):
      self.assertEqual(self.corr(text), 0, text)

  def test_the_correcting_form_still_counts(self):
    for text in ('again, shorter', 'the format, again, is not right',
                 'never do this again', "don't forget this again",
                 'not again', 'no not that one', 'No it should be clearer'):
      self.assertEqual(self.corr(text), 5, text)
    for text in ('stop guessing', 'stop.', 'please stop', 'stop it',
                 'why did you delete it', 'why?', 'as I stated',
                 'it reads odd', 'you edited the wrong file', 'Try again.'):
      self.assertEqual(self.corr(text), 3, text)
    for text in ('explain?', 'explain yourself',
                 'the count went up - explain how'):
      self.assertEqual(self.corr(text), 1, text)

  def test_dont_stop_is_not_a_correction(self):
    self.assertEqual(self.corr("don't stop"), 0)

  def test_praise_tiers(self):
    self.assertEqual(scanned('great').get('praise'), 2.0)
    self.assertEqual(scanned('thanks').get('praise'), 1.5)
    self.assertEqual(scanned('that works').get('praise'), 1.0)
    self.assertEqual(scanned('perfect, thanks').get('praise'), 2.0)

  def test_a_praise_word_in_another_sense_is_no_praise(self):
    for text in ('not great', "this isn't perfect", 'not happy with this',
                 'nothing works', 'this no longer works',
                 'tell me how this works',
                 'the first form works best', 'happy path first',
                 'nice to have: a json flag', 'it would be nice if it ran'):
      self.assertEqual(scanned(text).get('praise', 0), 0, text)
    self.assertEqual(scanned('it works now').get('praise'), 1.0)
    self.assertEqual(scanned('happy with that').get('praise'), 1.0)
    self.assertEqual(scanned('nice work').get('praise'), 1.5)

  def test_a_failure_report_is_a_correction_not_praise(self):
    event = scanned('that does not work')
    self.assertEqual(event.get('praise', 0), 0)
    self.assertEqual(event.get('corrections'), 1)

  def test_nudges(self):
    self.assertEqual(last(fed(user('keep going')), 'nudges'), 1)
    self.assertEqual(last(fed(user('continue, and hurry')), 'nudges'), 1)

  def test_self_correction_tiers(self):
    self.assertEqual(last(fed(assistant('I apologize.')), 'self_corrections'), 5)
    self.assertEqual(last(fed(assistant('I misread the file.')),
                          'self_corrections'), 3)
    self.assertEqual(last(fed(assistant('I should have checked.')),
                          'self_corrections'), 1)

  def test_stock_phrases(self):
    self.assertEqual(last(fed(assistant('Great question. Let me dive into it.')),
                          'stock_phrases'), 2)

  def test_domain_words_are_not_stock_phrases(self):
    # these read as stock phrases and are not
    self.assertEqual(last(fed(assistant('UNLOCK TABLES t1; LOCK TABLES t1 READ;')),
                          'stock_phrases'), 0)

  def test_correcting_code_is_not_a_self_correction(self):
    self.assertEqual(last(fed(assistant('Correcting the fix.')),
                          'self_corrections'), 0)
    self.assertEqual(last(fed(assistant('Correcting the expected code.')),
                          'self_corrections'), 0)
    self.assertEqual(last(fed(assistant('Correcting my earlier count.')),
                          'self_corrections'), 1)

  def test_a_resume_flag_is_not_a_nudge(self):
    self.assertEqual(scanned('./run --resume 1242772').get('nudges', 0), 0)
    self.assertEqual(scanned('please resume at 19:51').get('nudges'), 1)

  def test_why_this_works_counts_three(self):
    self.assertEqual(last(fed(assistant('Here is why this fix works.')),
                          'stock_phrases'), sm.WHY_WORKS)

  def test_em_dashes_and_pronouns_are_off_until_switched_on(self):
    text = 'He said it - or rather \u2014 he wrote it to him.'
    check = fed(assistant(text))
    self.assertEqual(last(check, 'emdashes'), 0)
    self.assertEqual(last(check, 'pronouns'), 0)
    with Settings({'count_em_dashes': True, 'count_he_him': True}):
      check = fed(assistant(text))
      self.assertEqual(last(check, 'emdashes'), 1)
      self.assertEqual(last(check, 'pronouns'), 3)
    with Settings({'count_em_dashes': True}):
      check = fed(assistant(text))
      self.assertEqual(last(check, 'emdashes'), 1)
      self.assertEqual(last(check, 'pronouns'), 0)

  def test_a_frame_of_em_dashes_is_not_prose(self):
    with Settings({'count_em_dashes': True}):
      check = fed(assistant('\u2014' * 80 + '\ntext \u2014 more\n' + '\u2014' * 80))
      self.assertEqual(last(check, 'emdashes'), 1)


class OwnSettings(unittest.TestCase):

  def corr(self, text):
    return last(fed(user(text)), 'corrections')

  def test_no_file_means_the_built_in_set(self):
    own = sm.read_own(NO_SETTINGS)
    self.assertEqual(own['words'], {})
    self.assertEqual(own['marks'], [sm.HAND_MARK])
    self.assertFalse(own['em_dashes'])
    self.assertFalse(own['he_him'])
    self.assertIsNone(own['zone'])
    self.assertEqual(own['stamp'], '')
    self.assertEqual(own['faults'], [])
    self.assertEqual(sm.OWN, own)

  def test_own_patterns_join_every_list(self):
    words = {'corrections_severe': [r'\bgarbage\b'],
             'corrections_heavy': [r'\bnot this way\b'],
             'corrections_plain': [r'\bbogus\b'],
             'nudges': [r'\bchop chop\b'],
             'praise_high': [r'\bbravo\b'],
             'praise_medium': [r'\bcheers\b'],
             'praise_low': [r'\bfine by me\b'],
             'self_severe': [r'\bmea culpa\b'],
             'self_heavy': [r'\bi slipped\b'],
             'self_plain': [r'\bon reflection\b'],
             'stock_phrases': [r'\bmoving forward\b', r'\bcircle back\b']}
    self.assertEqual(sorted(words), sorted(sm.WORD_LISTS))

    def readings():
      return [self.corr('that is garbage'), self.corr('not this way'),
              self.corr('bogus'), scanned('chop chop').get('nudges', 0),
              scanned('bravo').get('praise', 0),
              scanned('cheers').get('praise', 0),
              scanned('fine by me').get('praise', 0),
              last(fed(assistant('Mea culpa.')), 'self_corrections'),
              last(fed(assistant('I slipped there.')), 'self_corrections'),
              last(fed(assistant('On reflection, no.')), 'self_corrections'),
              last(fed(assistant('Moving forward, we circle back. Moving '
                                 'forward.')), 'stock_phrases')]

    self.assertEqual(readings(), [0] * 11)
    with Settings({'words': words}) as own:
      self.assertEqual(own['faults'], [])
      self.assertEqual(readings(), [5, 3, 1, 1, 2.0, 1.5, 1.0, 5, 3, 1, 3])
    self.assertEqual(readings(), [0] * 11)

  def test_the_strongest_class_still_wins(self):
    with Settings({'words': {'corrections_plain': [r'\bbogus\b'],
                             'corrections_severe': [r'\bgarbage\b']}}):
      self.assertEqual(self.corr('no, that is bogus'), 5)
      self.assertEqual(self.corr('garbage, please explain'), 5)
      self.assertEqual(self.corr('bogus and unrelated'), 3)

  def test_an_own_pattern_reads_the_text_as_typed(self):
    with Settings({'words': {'corrections_heavy': ['(?-i:\\bTLDR\\b)'],
                             'corrections_plain': [r'\bbogus\b']}}):
      self.assertEqual(self.corr('TLDR'), 3)
      self.assertEqual(self.corr('tldr'), 0)
      self.assertEqual(self.corr('BOGUS'), 1)
      self.assertEqual(self.corr('Bogus'), 1)

  def test_the_name_adds_to_an_own_correction_too(self):
    with Settings({'words': {'corrections_plain': [r'\bbogus\b']}}):
      self.assertEqual(self.corr('claude, bogus'), 2)

  def test_faults_are_named_and_the_rest_is_kept(self):
    body = {'colour': 'blue',
            'words': {'insults': ['x'], 'nudges': 'chop chop',
                      'corrections_plain': ['(', 'a*', 7, r'\bbogus\b']},
            'hand_marks': ['two words', '12', '', 5, '+', 'a"b', '##'],
            'count_em_dashes': 'yes', 'count_he_him': 1,
            'context_zone': [5, 1]}
    with Settings(body) as own:
      self.assertEqual(len(own['faults']), 15)
      self.assertEqual(list(own['words']), ['corrections_plain'])
      self.assertEqual(len(own['words']['corrections_plain']), 1)
      self.assertEqual(own['marks'], [sm.HAND_MARK, '##'])
      self.assertFalse(own['em_dashes'])
      self.assertFalse(own['he_him'])
      self.assertIsNone(own['zone'])
      self.assertEqual(self.corr('bogus'), 1)
      self.assertEqual(scanned('fine ## -6').get('hand'), -6)
      self.assertEqual(scanned('chop chop').get('nudges', 0), 0)

  def test_a_pattern_that_matches_empty_text_is_refused(self):
    for pattern in ('', 'x*', '^', '(?:bogus)?'):
      with Settings({'words': {'corrections_severe': [pattern]}}) as own:
        self.assertEqual(len(own['faults']), 1, pattern)
        self.assertEqual(own['words'], {}, pattern)
        self.assertEqual(self.corr('fine'), 0, pattern)

  def test_a_note_is_skipped(self):
    with Settings({'_note': 'kept for the reader', '_more': [1, 2]}) as own:
      self.assertEqual(own['faults'], [])
      self.assertNotEqual(own['stamp'], '')

  def test_a_file_that_is_not_an_object_changes_nothing(self):
    for body in ('[1]', '"s"', 'null', '{broken', '', '[' * 100000):
      with Settings(body) as own:
        self.assertEqual(own['faults'], ['the file is not a json object'])
        self.assertEqual(own['words'], {})
        self.assertEqual(own['marks'], [sm.HAND_MARK])
        self.assertNotEqual(own['stamp'], '')
    home = config_dir(b'\xff\xfe{}')
    own = sm.read_own(os.path.join(home, 'mariadb-qa', 'session_meter.json'))
    self.assertEqual(own['faults'], ['the file is not a json object'])
    shutil.rmtree(home)

  def test_a_file_that_cannot_be_read_is_named(self):
    home = config_dir('{}')
    path = os.path.join(home, 'mariadb-qa', 'session_meter.json')
    os.unlink(path)
    os.mkdir(path)                      # a directory where the file belongs
    own = sm.read_own(path)
    self.assertEqual(own['faults'], ['the file cannot be read'])
    self.assertEqual(own['stamp'], '')
    self.assertEqual(own['marks'], [sm.HAND_MARK])
    out = subprocess.run([sys.executable, METER, '--settings'],
                         capture_output=True, text=True,
                         env=dict(os.environ, XDG_CONFIG_HOME=home))
    self.assertIn('WARNING: left out: the file cannot be read', out.stdout)
    self.assertNotIn('not there', out.stdout)
    shutil.rmtree(home)

  def test_the_switches_take_true_and_false_only(self):
    with Settings({'count_em_dashes': True, 'count_he_him': False}) as own:
      self.assertTrue(own['em_dashes'])
      self.assertFalse(own['he_him'])
      self.assertEqual(own['faults'], [])

  def test_the_context_zone(self):
    for good in ([1000, 2000], [1000, 1000], [0, 2000.5]):
      with Settings({'context_zone': good}) as own:
        self.assertEqual(own['zone'], tuple(good))
        self.assertEqual(own['faults'], [])
    for bad in ([2000, 1000], [-1, 5], [1, 2, 3], [True, 5], ['1', '2'], 7, None):
      with Settings({'context_zone': bad}) as own:
        self.assertIsNone(own['zone'], bad)
        self.assertEqual(len(own['faults']), 1, bad)
    # an edge with no end cannot be printed, and python reads both forms
    for body in ('{"context_zone": [1000, 1e999]}',
                 '{"context_zone": [1000, Infinity]}',
                 '{"context_zone": [NaN, 2000]}'):
      with Settings(body) as own:
        self.assertIsNone(own['zone'], body)
        self.assertEqual(own['faults'], ['context_zone is not understood'], body)
    check = sm.Check()
    check.context = 1500
    self.assertFalse(sm.reading(check)['zone'])
    with Settings({'context_zone': [1000, 2000]}):
      self.assertTrue(sm.reading(check)['zone'])
      check.context = 2001
      self.assertFalse(sm.reading(check)['zone'])
      check.context = 999
      self.assertFalse(sm.reading(check)['zone'])

  def test_the_stamp_follows_the_bytes_of_the_file(self):
    with Settings({'count_em_dashes': True}) as own:
      first = own['stamp']
    with Settings({'count_em_dashes': False}) as own:
      second = own['stamp']
    with Settings({'count_em_dashes': True}) as own:
      third = own['stamp']
    self.assertNotEqual(first, second)
    self.assertEqual(first, third)
    self.assertEqual(sm.OWN['stamp'], '')

  def test_a_mark_is_added_once_and_in_lower_case(self):
    with Settings({'hand_marks': ['Dial', 'dial', 'METER']}) as own:
      self.assertEqual(own['marks'], [sm.HAND_MARK, 'dial'])
      self.assertEqual(scanned('Dial +4').get('hand'), 4)
      self.assertEqual(scanned('the dial +4').get('hand', 0), 0)


class WordLists(unittest.TestCase):

  def built_in(self):
    lists = [(name, pattern) for group in (sm.CORRECT_TIERS, sm.PRAISE_TIERS,
                                           sm.SELF_TIERS)
             for name, pattern, _ in group]
    return lists + [('nudges', sm.NUDGE), ('stock_phrases', sm.STOCK_PHRASES)]

  def test_every_list_has_its_name(self):
    self.assertEqual(sorted(name for name, _ in self.built_in()),
                     sorted(sm.WORD_LISTS))

  def test_no_list_matches_empty_text(self):
    for name, pattern in self.built_in():
      self.assertIsNone(pattern.search(''), name)
      self.assertIsNone(pattern.search('the quick brown fox'), name)


class NameAddress(unittest.TestCase):

  def corr(self, text, opened=True):
    return last(fed(user(text), opened=opened), 'corrections')

  def test_an_address_alone_is_not_a_correction(self):
    self.assertEqual(self.corr('claude, read it'), 0)
    self.assertEqual(self.corr('claude, claude, listen'), 0)

  def test_the_name_adds_one_to_a_correction(self):
    self.assertEqual(self.corr('that is wrong'), 3)
    self.assertEqual(self.corr('claude, that is wrong'), 4)

  def test_sentence_ending_dot_counts(self):
    self.assertEqual(self.corr('wrong, claude. then read it'), 4)

  def test_path_file_product_host_never_count(self):
    for text in ('~/.claude/settings.json', 'see CLAUDE.md', 'claude-code',
                 'claude.ai', 'claude/hooks', 'run claude code'):
      self.assertEqual(self.corr('wrong: ' + text), 3, text)

  def test_opening_prompt_never_counts(self):
    self.assertEqual(self.corr('claude, that is wrong', opened=False), 3)

  def test_two_mentions_add_two(self):
    self.assertEqual(self.corr('wrong, claude, claude'), 5)

  def test_name_adds_on_top_of_the_class(self):
    self.assertEqual(self.corr('no, claude'), 6)


class SkipRules(unittest.TestCase):

  def test_system_text_and_command_tags(self):
    self.assertEqual(len(fed(user('<system-reminder>x</system-reminder>')).ring), 0)
    self.assertEqual(len(fed(user('a <command-name>/model</command-name>')).ring), 0)

  def test_empty_and_whitespace(self):
    self.assertEqual(len(fed(user('')).ring), 0)
    self.assertEqual(len(fed(user('   \n ')).ring), 0)

  def test_sidechain_and_meta(self):
    self.assertEqual(len(fed(dict(user('no'), isSidechain=True)).ring), 0)
    self.assertEqual(len(fed(dict(user('no'), isMeta=True)).ring), 0)

  def test_long_paste_counts_but_is_not_scanned(self):
    check = fed(user('no, wrong. ' + 'x' * 2100))
    self.assertEqual(last(check, 'user_msgs'), 1)
    self.assertEqual(last(check, 'corrections'), 0)

  def test_compact_marker_marks_the_opening_prompt_done(self):
    check = sm.Check()
    check.record(user('This session is being continued from a previous run.'))
    self.assertTrue(check.opened)
    self.assertEqual(len(check.ring), 0)
    check.record(user('claude, that is wrong'))
    self.assertEqual(last(check, 'corrections'), 4)

  def test_interrupt_marker_only_at_the_start(self):
    check = fed(user('[Request interrupted by user for tool use]'))
    self.assertEqual(last(check, 'interrupts'), 1)
    self.assertEqual(last(check, 'user_msgs'), 0)
    quoted = fed(user('the log said [Request interrupted by user] there'))
    self.assertEqual(last(quoted, 'interrupts'), 0)
    self.assertEqual(last(quoted, 'user_msgs'), 1)

  def test_synthetic_assistant_scores_nothing(self):
    check = fed(assistant('Great question, sorry \u2014 he did.', model='<synthetic>'))
    self.assertEqual(len(check.ring), 0)

  def test_synthetic_keeps_only_the_api_error(self):
    record = dict(assistant('x', model='<synthetic>'), isApiErrorMessage=True)
    self.assertEqual(last(fed(record), 'api_errors'), 1)

  def test_api_error_on_any_record_type(self):
    self.assertEqual(last(fed({'type': 'system', 'isApiErrorMessage': True}),
                          'api_errors'), 1)


class PagerCheck(unittest.TestCase):

  def test_bare_display_counts(self):
    self.assertEqual(sm.pager_points('cat /etc/hosts'), sm.PAGER_POINTS)
    self.assertEqual(sm.pager_points('head -20 f.txt'), sm.PAGER_POINTS)
    self.assertEqual(sm.pager_points('/bin/cat f.txt'), sm.PAGER_POINTS)

  def test_pipe_and_redirect_give_nothing(self):
    self.assertEqual(sm.pager_points('cat f | grep x'), 0)
    self.assertEqual(sm.pager_points('cat f > g'), 0)
    self.assertEqual(sm.pager_points('cat < f'), 0)

  def test_scratch_tree_gives_nothing(self):
    self.assertEqual(sm.pager_points('cat /tmp/claude-99/out.txt'), 0)

  def test_a_working_step_gives_nothing(self):
    self.assertEqual(sm.pager_points('cat f && make'), 0)
    self.assertEqual(sm.pager_points('make; cat f'), 0)
    self.assertEqual(sm.pager_points('cat f\ngrep x g'), 0)

  def test_echo_and_cd_rescue_nothing(self):
    self.assertEqual(sm.pager_points('echo hi && cat f'), sm.PAGER_POINTS)
    self.assertEqual(sm.pager_points('cd /tmp; cat f'), sm.PAGER_POINTS)
    self.assertEqual(sm.pager_points('echo hi'), 0)

  def test_counted_on_the_shell_tool_only(self):
    shell = fed(assistant(tools=[call('Bash', payload={'command': 'cat f'})]))
    self.assertEqual(last(shell, 'pagers'), sm.PAGER_POINTS)
    other = fed(assistant(tools=[call('Read', payload={'file_path': 'cat f'})]))
    self.assertEqual(last(other, 'pagers'), 0)


class Streaks(unittest.TestCase):

  def run_of(self, count):
    check = sm.Check()
    check.opened = True
    for index in range(count):
      check.record(assistant(tools=[call(cid='c%d' % index)]))
      check.record(result('c%d' % index, error=True))
    return check

  def test_streak_lands_at_three(self):
    check = self.run_of(2)
    self.assertEqual(sm.weighted(check.ring)['streaks'], 0)
    check = self.run_of(3)
    self.assertEqual(sm.weighted(check.ring)['streaks'], 1)

  def test_success_ends_the_run(self):
    check = self.run_of(2)
    check.record(assistant(tools=[call(cid='ok')]))
    check.record(result('ok'))
    self.assertEqual(check.streak, 0)
    check.record(assistant(tools=[call(cid='z')]))
    check.record(result('z', error=True))
    self.assertEqual(check.streak, 1)

  def test_longest_run_is_unweighted_max(self):
    check = self.run_of(5)
    self.assertEqual(max(e.get('run_len', 0) for e in check.ring), 5)

  def test_edit_errors_follow_the_tool_name(self):
    check = sm.Check()
    check.record(assistant(tools=[call('Edit', 'e1', {'file_path': 'a'})]))
    check.record(result('e1', error=True))
    self.assertEqual(last(check, 'edit_errors'), 1)

  def test_pending_map_stays_bounded(self):
    check = sm.Check()
    for index in range(200):
      check.record(assistant(tools=[call(cid='c%d' % index)]))
    self.assertEqual(len(check.pending), 200)     # no early trim
    for index in range(600):
      check.record(assistant(tools=[call(cid='d%d' % index)]))
    self.assertLessEqual(len(check.pending), 201)

  def test_a_repeat_reaches_three_calls_back(self):
    check = sm.Check()
    for text in ('ls a', 'ls b', 'ls c'):
      check.record(assistant(tools=[call(cid=text, payload={'command': text})]))
    check.record(assistant(tools=[call(cid='z', payload={'command': 'ls a'})]))
    self.assertEqual(last(check, 'repeats'), 1)

  def test_a_repeat_does_not_reach_four_calls_back(self):
    same = [call(cid='a', payload={'command': 'ls'})]
    check = fed(assistant(tools=same), assistant(tools=same))
    self.assertEqual(last(check, 'repeats'), 1)
    check = sm.Check()
    for index in range(4):
      check.record(assistant(tools=[call(cid='c%d' % index,
                                         payload={'command': 'ls %d' % index})]))
    check.record(assistant(tools=[call(cid='z', payload={'command': 'ls 0'})]))
    self.assertEqual(last(check, 'repeats'), 0)


class Scoring(unittest.TestCase):

  def test_band_rounds_before_it_colours(self):
    self.assertEqual(sm.shown(34.6), 35)
    self.assertEqual(sm.band(34.6), 2)
    self.assertEqual(sm.band(34.4), 1)
    self.assertEqual(sm.band(19.4), 0)
    self.assertEqual(sm.band(54.6), 3)

  def test_the_score_is_clamped_at_a_hundred(self):
    check = sm.Check()
    check.opened = True
    check.shown = 140.0
    view = sm.reading(check)
    self.assertEqual(view['score'], 100.0)
    self.assertEqual(sm.shown(view['score']), 100)
    self.assertEqual(view['band'], 3)

  def test_caps_are_the_documented_ones(self):
    self.assertEqual(sm.CAPS, {
      'tool_errors': 20, 'edit_errors': 20, 'streaks': 18, 'repeats': 10,
      'pagers': 10, 'corrections': 30, 'nudges': 10, 'interrupts': 8,
      'self_corrections': 15, 'stock_phrases': 15, 'emdashes': 7,
      'pronouns': 7, 'verbosity': 15, 'api_errors': 10, 'praise': 13})

  def test_free_bands_and_window(self):
    self.assertEqual(sm.FREE_RATE['tool_errors'], 0.02)
    self.assertEqual(sm.FREE_RATE['edit_errors'], 0.03)
    self.assertEqual(sm.RING, 70)
    self.assertEqual(sm.RAMP_AT, 35)
    self.assertEqual(sm.CUTS, (20, 35, 55))
    self.assertEqual(sm.STEPS, ((7, 1.0), (13, 0.75), (20, 0.5), (30, 0.25)))
    self.assertEqual(sum(count for count, _ in sm.STEPS), sm.RING)
    self.assertEqual(sm.PASTE, 2000)
    self.assertEqual(sm.LONG_BLOCK, 250)
    self.assertEqual(sm.PAGER_POINTS, 5)
    self.assertEqual(sm.FLOOR, {
      'tool_errors': 10.0, 'edit_errors': 6.0, 'repeats': 10.0, 'pagers': 10.0,
      'corrections': 5.0, 'nudges': 5.0, 'interrupts': 5.0,
      'self_corrections': 5.0, 'stock_phrases': 5.0, 'pronouns': 5.0,
      'long_share': 5.0, 'praise': 5.0})
    self.assertEqual(sm.WHY_WORKS, 3)
    self.assertEqual(sm.SIGS, 3)
    self.assertEqual(sm.PENDING_CAP, 200)
    self.assertEqual(sm.GAPS, 100)

  def test_ramp_curve(self):
    def ramp(count):
      ring = sm.deque([{'api_errors': 1}] * count, maxlen=sm.RING)
      return sm.assemble(ring)['ramp']
    self.assertAlmostEqual(ramp(2), 2 / 35.0)
    self.assertLess(ramp(10), 1 / 3.0)
    self.assertEqual(ramp(35), 1.0)
    self.assertEqual(ramp(50), 1.0)

  def test_two_events_read_near_zero(self):
    ring = sm.deque([{'user_msgs': 1, 'corrections': 5}], maxlen=sm.RING)
    self.assertLess(sm.assemble(ring)['raw'], 1.0)

  def test_interrupt_lands_without_a_typed_message(self):
    ring = sm.deque([{'interrupts': 1}], maxlen=sm.RING)
    row = [r for r in sm.assemble(ring)['rows'] if r['part'] == 'interrupts'][0]
    self.assertEqual(row['base'], sm.FLOOR['interrupts'])
    self.assertAlmostEqual(row['points'],
                           sm.SCALE['interrupts'] / sm.FLOOR['interrupts'])
    self.assertLess(row['points'], sm.CAPS['interrupts'])

  def test_a_small_base_does_not_pin_a_part(self):
    # two edit calls with one failure: the floor under the base keeps it graded
    ring = sm.deque([{'tool_calls': 2, 'edit_calls': 2, 'edit_errors': 1,
                      'tool_errors': 1}], maxlen=sm.RING)
    points = {r['part']: r['points'] for r in sm.assemble(ring)['rows']}
    self.assertLess(points['edit_errors'], 0.5 * sm.CAPS['edit_errors'])
    self.assertLess(points['tool_errors'], 0.5 * sm.CAPS['tool_errors'])

  def test_flat_parts_are_worth_their_number_at_full_weight(self):
    ring = sm.deque([{'emdashes': 1, 'api_errors': 1, 'streaks': 1}],
                    maxlen=sm.RING)
    points = {r['part']: r['points'] for r in sm.assemble(ring)['rows']}
    self.assertNotIn('emdashes', points)
    self.assertNotIn('pronouns', points)
    self.assertAlmostEqual(points['api_errors'], sm.SCALE['api_error'])
    self.assertAlmostEqual(points['streaks'],
                           sm.compress(sm.SCALE['streak'], sm.CAPS['streaks']))
    with Settings({'count_em_dashes': True}):
      points = {r['part']: r['points'] for r in sm.assemble(ring)['rows']}
      self.assertAlmostEqual(points['emdashes'], sm.SCALE['emdash'])
      self.assertNotIn('pronouns', points)

  def test_one_top_praise_in_five_messages_nears_the_floor(self):
    ring = sm.deque([{'user_msgs': 1}] * 4 + [{'user_msgs': 1, 'praise': 2.0}],
                    maxlen=sm.RING)
    row = [r for r in sm.assemble(ring)['rows'] if r['part'] == 'praise'][0]
    self.assertAlmostEqual(row['points'],
                           sm.compress(0.4 * sm.SCALE['praise'],
                                       sm.CAPS['praise']))
    self.assertLess(row['points'], sm.CAPS['praise'])

  def test_older_events_weigh_less(self):
    ring = sm.deque([{'api_errors': 1}] * 41, maxlen=sm.RING)
    self.assertAlmostEqual(sm.weighted(ring)['api_errors'],
                           7 * 1.0 + 13 * 0.75 + 20 * 0.5 + 1 * 0.25)

  def noisy_window(self):
    event = {'user_msgs': 1, 'corrections': 6, 'nudges': 1, 'interrupts': 1,
             'tool_calls': 1, 'tool_errors': 1, 'edit_calls': 1,
             'edit_errors': 1, 'streaks': 1, 'repeats': 1, 'pagers': 5,
             'text_blocks': 1, 'words': 400, 'sentences': 1, 'long_blocks': 1,
             'self_corrections': 5, 'stock_phrases': 4, 'emdashes': 4,
             'pronouns': 4, 'api_errors': 1, 'run_len': 9}
    return sm.assemble(sm.deque([event] * sm.RING, maxlen=sm.RING))

  def test_a_noisy_window_fills_every_part_and_reads_red(self):
    parts = self.noisy_window()
    names = [row['part'] for row in parts['rows']]
    self.assertEqual(len(names), len(sm.CAPS) - 2)
    self.assertNotIn('emdashes', names)
    self.assertNotIn('pronouns', names)
    for row in parts['rows']:
      if row['part'] != 'praise':
        cap = sm.CAPS[row['part']]
        self.assertGreater(row['points'], 0.9 * cap, row['part'])
        self.assertLessEqual(row['points'], cap, row['part'])
    self.assertGreaterEqual(min(100.0, parts['raw']), sm.CUTS[2])

  def test_the_two_switched_parts_join_the_table(self):
    plain = self.noisy_window()
    with Settings({'count_em_dashes': True, 'count_he_him': True}):
      parts = self.noisy_window()
    names = [row['part'] for row in parts['rows']]
    self.assertEqual(sorted(names), sorted(sm.CAPS))
    for row in parts['rows']:
      if row['part'] in ('emdashes', 'pronouns'):
        self.assertGreater(row['points'], 0.9 * sm.CAPS[row['part']])
    self.assertGreater(parts['raw'], plain['raw'])

  def test_every_part_has_a_label(self):
    self.assertEqual(sorted(sm.LABEL), sorted(sm.CAPS))

  def test_expand_reads_compress_backwards(self):
    for cap in (7, 13, 30):
      for points in (0.0, 0.2 * cap, 0.3 * cap, 0.5 * cap, 0.9 * cap, 2.0 * cap):
        self.assertAlmostEqual(sm.expand(sm.compress(points, cap), cap), points,
                               places=6)


class Shave(unittest.TestCase):

  def push(self, check, event):
    check.push(dict(event))

  def test_a_big_minus_is_held_at_the_cap_and_then_fades(self):
    check = sm.Check()
    check.opened = True
    check.record(user('meter -80'))
    self.assertEqual(sm.bias(check.moves), -sm.BIAS_CAP)
    self.assertEqual(sm.reading(check)['score'], 0.0)
    for index in range(sm.BIAS_SPAN):
      check.push({'api_errors': 1})
    self.assertEqual(sm.bias(check.moves), 0.0)
    self.assertGreater(sm.reading(check)['score'], 0.0)

  def test_a_credit_that_fits_is_kept_whole(self):
    check = sm.Check()
    check.opened = True
    for index in range(40):
      check.push({'api_errors': 1})
    before = sm.reading(check)['score']
    check.record(user('meter -3'))
    after = sm.reading(check)['score']
    self.assertAlmostEqual(before - after, 3.0, delta=0.5)
    self.assertEqual(check.moves[-1][1], -3)

  def test_praise_credit_is_shaved_to_exactly_zero(self):
    check = sm.Check()
    check.opened = True
    for _ in range(5):
      check.record(user('great work'))
    self.assertEqual(sm.reading(check)['score'], 0.0)
    self.assertLess(sm.assemble(check.ring)['raw'], 1e-6)
    self.assertGreater(sm.assemble(check.ring)['raw'], -1e-6)

  def test_property_the_shave_never_overshoots(self):
    random.seed(11)
    for _ in range(200):
      ring = sm.deque(maxlen=sm.RING)
      for _ in range(random.randint(1, 90)):
        event = {}
        if random.random() < 0.5:
          event['user_msgs'] = 1
        if random.random() < 0.3:
          event['praise'] = random.choice((1.0, 1.5, 2.0))
        if random.random() < 0.4:
          event['corrections'] = random.choice((1, 3, 5))
        if random.random() < 0.3:
          event['api_errors'] = 1
        event = {k: v for k, v in event.items() if v}
        if not event:
          continue
        ring.append(event)
        pre = sm.assemble(ring)['raw']
        sm.shave(ring)
        post = sm.assemble(ring)['raw']
        self.assertGreater(post, -1e-6)
        if pre < -1e-6:
          self.assertLess(post, 1e-6)       # on the floor, not above it

  def test_praise_in_a_young_session_is_kept_up_to_the_floor(self):
    # few events and under five user messages: the praise that cancels the
    # other parts stays, and only the rest is trimmed
    for faults, thanks in ((1, 1), (3, 2)):     # under the knee, and over it
      check = sm.Check()
      check.opened = True
      for _ in range(faults):
        check.push({'api_errors': 1})
      for _ in range(thanks):
        check.record(user('great, thanks'))
      parts = sm.assemble(check.ring)
      self.assertGreater(parts['positive'], 1.0)
      self.assertAlmostEqual(parts['raw'], 0.0, places=6)
      self.assertAlmostEqual(parts['praise'], parts['positive'], places=6)
      self.assertLess(parts['sums']['praise'], 2.0 * thanks)

  def test_praise_under_the_other_parts_is_left_whole(self):
    check = sm.Check()
    check.opened = True
    for _ in range(40):
      check.push({'api_errors': 1})
    check.record(user('thanks'))
    self.assertEqual(check.ring[-1]['praise'], 1.5)
    self.assertGreater(sm.assemble(check.ring)['raw'], 0.0)


class Robustness(unittest.TestCase):

  def test_survives_odd_records(self):
    check = sm.Check()
    for record in ({'type': 'user', 'message': None},
                   {'type': 'user', 'message': {'content': 12}},
                   {'type': 'assistant', 'message': {'content': 'plain'}},
                   {'type': 'assistant', 'message': {'usage': 'bad',
                                                     'content': []}},
                   {'type': 'nothing-known'},
                   user('x' * 50000),
                   dict(user('hi'), timestamp=None),
                   dict(user('hi'), timestamp='not-a-time')):
      check.record(record)

  def test_lone_surrogate_survives(self):
    path = write([json.loads('{"type":"user","message":'
                             '{"content":"a \\ud800 b"}}')])
    check = sm.Check()
    check.scan(path)
    self.assertEqual(check.skipped, 0)
    os.unlink(path)

  def test_rubbish_lines_are_skipped_and_counted(self):
    path = write([user('hello')])
    with open(path, 'a') as handle:
      handle.write('{not json\n')
      handle.write(json.dumps(user('no, wrong')) + '\n')
    check = sm.Check()
    check.opened = True
    check.scan(path)
    self.assertEqual(check.skipped, 1)
    self.assertEqual(last(check, 'corrections'), 5)
    os.unlink(path)

  def test_half_written_line_is_left(self):
    path = write([user('hello')])
    with open(path, 'a') as handle:
      handle.write('{"type":"user","message":{"content":"no')
    check = sm.Check()
    check.scan(path)
    size = os.path.getsize(path)
    self.assertLess(check.cursor, size)
    with open(path, 'a') as handle:
      handle.write('"}}\n')
    check.scan(path)
    self.assertEqual(check.cursor, os.path.getsize(path))
    self.assertEqual(check.skipped, 0)
    os.unlink(path)

  def test_rescan_of_the_same_bytes_is_stable(self):
    path = write([user('no, wrong'), assistant('sorry')])
    check = sm.Check()
    check.scan(path)
    first = sm.reading(check)['score']
    check.scan(path)
    self.assertEqual(sm.reading(check)['score'], first)
    os.unlink(path)

  def test_a_shrunken_transcript_resets(self):
    path = write([user('no, wrong')] * 5)
    check = sm.Check()
    check.scan(path)
    with open(path, 'w') as handle:
      handle.write(json.dumps(user('hello')) + '\n')
    check.scan(path)
    self.assertEqual(check.cursor, os.path.getsize(path))
    self.assertEqual(len(check.ring), 1)
    os.unlink(path)


class Cache(unittest.TestCase):

  def setUp(self):
    self.home = tempfile.mkdtemp()
    self.old = os.environ.get('XDG_CACHE_HOME')
    os.environ['XDG_CACHE_HOME'] = self.home

  def tearDown(self):
    if self.old is None:
      os.environ.pop('XDG_CACHE_HOME', None)
    else:
      os.environ['XDG_CACHE_HOME'] = self.old
    shutil.rmtree(self.home, ignore_errors=True)

  def test_round_trip(self):
    path = write([user('no, wrong')])
    check = sm.Check()
    check.scan(path)
    sm.save(check, 'abc', path)
    again = sm.load('abc', path)
    self.assertEqual(again.cursor, check.cursor)
    self.assertEqual(list(again.ring), list(check.ring))
    os.unlink(path)

  def test_the_cache_folder_is_for_the_owner_only(self):
    path = write([user('no, wrong')])
    check = sm.Check()
    check.scan(path)
    sm.save(check, 'abc', path)
    self.assertEqual(os.stat(sm.cache_dir()).st_mode & 0o777, 0o700)
    os.unlink(path)

  def test_a_stale_version_is_refused(self):
    path = write([user('no, wrong')])
    check = sm.Check()
    check.scan(path)
    sm.save(check, 'abc', path)
    with open(sm.cache_file('abc')) as handle:
      state = json.load(handle)
    state['version'] = sm.VERSION + 1
    with open(sm.cache_file('abc'), 'w') as handle:
      json.dump(state, handle)
    self.assertEqual(sm.load('abc', path).cursor, 0)
    os.unlink(path)

  def test_another_path_is_refused(self):
    path = write([user('no')])
    check = sm.Check()
    check.scan(path)
    sm.save(check, 'abc', path)
    self.assertEqual(sm.load('abc', path + '.other').cursor, 0)
    os.unlink(path)

  def test_a_shrink_is_refused(self):
    path = write([user('no, wrong')] * 4)
    check = sm.Check()
    check.scan(path)
    sm.save(check, 'abc', path)
    with open(path, 'w') as handle:
      handle.write('\n')
    self.assertEqual(sm.load('abc', path).cursor, 0)
    os.unlink(path)

  def test_a_cache_that_is_not_an_object_is_refused(self):
    path = write([user('no')])
    os.makedirs(sm.cache_dir(), exist_ok=True)
    for body in ('[1,2,3]', '"s"', 'null', '42'):
      with open(sm.cache_file('abc'), 'w') as handle:
        handle.write(body)
      self.assertEqual(sm.load('abc', path).cursor, 0, body)
    os.unlink(path)

  def test_a_value_json_cannot_write_leaves_nothing_behind(self):
    path = write([user('no')])
    check = sm.Check()
    check.pending = {'a': set()}
    sm.save(check, 'abc', path)
    left = [f for f in os.listdir(sm.cache_dir()) if f.endswith('.tmp')]
    self.assertEqual(left, [])
    os.unlink(path)

  def test_an_unwritable_directory_leaves_nothing_behind(self):
    os.environ['XDG_CACHE_HOME'] = '/proc/nowhere'
    sm.save(sm.Check(), 'abc', '/x')
    self.assertFalse(os.path.exists('/proc/nowhere'))

  def test_a_changed_settings_file_drops_the_cache(self):
    path = write([user('no, wrong')])
    check = sm.Check()
    check.scan(path)
    sm.save(check, 'abc', path)
    self.assertEqual(sm.load('abc', path).cursor, check.cursor)
    with Settings({'count_em_dashes': True}):
      self.assertEqual(sm.load('abc', path).cursor, 0)
      sm.save(check, 'abc', path)
      self.assertEqual(sm.load('abc', path).cursor, check.cursor)
    self.assertEqual(sm.load('abc', path).cursor, 0)
    os.unlink(path)

  def test_incremental_matches_a_full_rescan(self):
    records = []
    for index in range(30):
      records.append(user('no, wrong %d' % index, index % 60))
      records.append(assistant('sorry \u2014 I misread.', [call(cid='c%d' % index)],
                               second=index % 60))
      records.append(result('c%d' % index, error=bool(index % 3)))
    path = write(records)
    step = sm.Check()
    with open(path) as handle:
      lines = handle.readlines()
    part = tempfile.NamedTemporaryFile('w', suffix='.jsonl', delete=False)
    part.close()
    for index in range(0, len(lines), 7):
      with open(part.name, 'a') as handle:
        handle.write(''.join(lines[index:index + 7]))
      step.scan(part.name)
    whole = sm.Check()
    whole.scan(path)
    self.assertEqual(list(step.ring), list(whole.ring))
    self.assertAlmostEqual(sm.reading(step)['score'],
                           sm.reading(whole)['score'])
    os.unlink(path)
    os.unlink(part.name)

  def test_the_fingerprint_pins_the_version(self):
    self.assertIn(sm.VERSION, FINGERPRINTS)
    self.assertEqual(fingerprint(), FINGERPRINTS[sm.VERSION],
                     'scoring changed: bump VERSION and this fingerprint')


class CommandLine(unittest.TestCase):

  def setUp(self):
    self.home = tempfile.mkdtemp()
    self.env = dict(os.environ, XDG_CACHE_HOME=self.home)

  def tearDown(self):
    shutil.rmtree(self.home, ignore_errors=True)

  def run_check(self, args, stdin=''):
    return subprocess.run([sys.executable, METER] + args, input=stdin,
                          capture_output=True, text=True, env=self.env)

  def test_report_mode(self):
    path = write([user('no, wrong'), assistant('sorry')])
    out = self.run_check(['--report', path])
    self.assertEqual(out.returncode, 0)
    self.assertTrue(out.stdout.startswith('session meter '))
    self.assertIn('user corrections', out.stdout)
    self.assertIn('stock phrases', out.stdout)
    self.assertNotIn('em-dashes', out.stdout)
    self.assertNotIn('WARNING', out.stdout)
    os.unlink(path)

  def test_json_mode(self):
    path = write([user('no, wrong')])
    out = self.run_check(['--json', path])
    body = json.loads(out.stdout)
    self.assertIn(body['band'], ('green', 'yellow', 'orange', 'red'))
    self.assertIn('corrections', body['points'])
    os.unlink(path)

  def test_segment_mode_from_stdin(self):
    path = write([user('no, wrong')])
    payload = json.dumps({'session_id': 's1', 'transcript_path': path})
    out = self.run_check(['--segment'], stdin=payload)
    self.assertEqual(out.returncode, 0)
    self.assertRegex(out.stdout.strip(), r'^[🟢🟡🟠🔴]\d+⚠?$')
    os.unlink(path)

  def test_segment_mode_from_arguments(self):
    path = write([user('hello')])
    out = self.run_check(['--segment', '--transcript', path, '--session', 's2'])
    self.assertEqual(out.returncode, 0)
    self.assertTrue(out.stdout.strip())
    os.unlink(path)

  def test_segment_reads_zero_for_an_unreadable_transcript(self):
    self.assertEqual(sm.segment('/no/such/file', 's'), '🟢0')
    self.assertEqual(sm.segment(self.home, 's'), '🟢0')

  def test_segment_reads_zero_on_a_missing_file(self):
    out = self.run_check(['--segment', '--transcript', '/no/such',
                          '--session', 's3'])
    self.assertEqual(out.returncode, 0)
    self.assertEqual(out.stdout.strip(), '🟢0')

  def test_segment_is_silent_on_broken_stdin(self):
    out = self.run_check(['--segment'], stdin='not json')
    self.assertEqual(out.returncode, 0)
    self.assertEqual(out.stdout.strip(), '')

  def test_report_fails_loudly(self):
    out = self.run_check(['--report', '/no/such/file'])
    self.assertEqual(out.returncode, 2)
    self.assertIn('usage', out.stderr)
    for mode in ('--report', '--json', '--replay'):     # a folder is no transcript
      folder = self.run_check([mode, self.home])
      self.assertEqual(folder.returncode, 2, mode)
      self.assertIn('usage', folder.stderr, mode)
    for mode in ('--report', '--json', '--segment', '--replay', '--calibrate',
                 '--settings'):
      self.assertIn(mode, out.stderr)
      self.assertIn(mode, sm.__doc__)
    self.assertIn('--scan', sm.__doc__)

  def test_replay_mode(self):
    path = write([user('no, wrong'), assistant('sorry'), user('thanks')])
    out = self.run_check(['--replay', path])
    self.assertEqual(out.returncode, 0)
    lines = out.stdout.splitlines()
    self.assertEqual(len(lines), 4)
    self.assertRegex(lines[0], r'^ +0 +\d+\.\d [🟢🟡🟠🔴]$')
    self.assertRegex(lines[-1], r'^peak \d+\.\d   end \d+\.\d$')
    self.assertEqual(self.run_check(['--replay', '/no/such']).returncode, 2)
    os.unlink(path)

  def run_with(self, body, args, stdin=''):
    home = config_dir(body)
    out = subprocess.run([sys.executable, METER] + args, input=stdin,
                         capture_output=True, text=True,
                         env=dict(self.env, XDG_CONFIG_HOME=home))
    shutil.rmtree(home)
    return out

  def test_settings_mode_without_a_file(self):
    out = self.run_check(['--settings'])
    self.assertEqual(out.returncode, 0)
    self.assertIn(NO_SETTINGS, out.stdout)
    self.assertIn('not there', out.stdout)

  def test_settings_mode_lists_what_was_read_and_what_was_left_out(self):
    out = self.run_with({'words': {'nudges': [r'\bchop chop\b', '(']},
                         'hand_marks': [OWN_MARK], 'count_he_him': True,
                         'context_zone': [1200, 2000], 'colour': 1},
                        ['--settings'])
    self.assertEqual(out.returncode, 0)
    self.assertRegex(out.stdout, r'nudges +own patterns: 1')
    self.assertRegex(out.stdout, r'hand marks +meter ' + OWN_MARK)
    self.assertRegex(out.stdout, r'em-dashes +off')
    self.assertRegex(out.stdout, r'he/him pronouns +counted')
    self.assertRegex(out.stdout, r'context zone +1200 to 2000')
    self.assertEqual(out.stdout.count('WARNING: left out: '), 2)
    self.assertIn('colour is not understood', out.stdout)

  def test_settings_mode_prints_half_of_a_character_pair(self):
    out = self.run_with('{"hand_marks": ["\\ud800"], "\\udc00": 1}',
                        ['--settings'])
    self.assertEqual(out.returncode, 0, out.stderr)
    self.assertRegex(out.stdout, r'hand marks +meter \?')
    self.assertIn('WARNING: left out: ? is not understood', out.stdout)

  def test_report_points_at_left_out_settings(self):
    path = write([user('no, wrong'), assistant('He said \u2014 sorry.')])
    out = self.run_with({'colour': 1, 'count_em_dashes': True,
                         'count_he_him': True}, ['--report', path])
    self.assertEqual(out.returncode, 0)
    self.assertIn('WARNING: items of the settings file left out: 1, see',
                  out.stdout)
    self.assertIn('em-dashes', out.stdout)
    self.assertIn('he/him pronouns', out.stdout)
    os.unlink(path)

  def test_segment_survives_a_broken_settings_file(self):
    path = write([user('no, wrong')])
    payload = json.dumps({'session_id': 's4', 'transcript_path': path})
    for body in ('{broken', '[]', b'\xff\xfe', {'words': {'nudges': ['(']}}):
      out = self.run_with(body, ['--segment'], stdin=payload)
      self.assertEqual(out.returncode, 0)
      self.assertRegex(out.stdout.strip(), r'^[🟢🟡🟠🔴]\d+$')
      self.assertEqual(out.stderr, '')
    os.unlink(path)

  def test_segment_marks_the_context_zone(self):
    path = write([user('hello'),
                  assistant('Done.', usage={'input_tokens': 1500})])
    payload = json.dumps({'session_id': 's5', 'transcript_path': path})
    plain = self.run_check(['--segment'], stdin=payload)
    self.assertRegex(plain.stdout.strip(), r'^🟢\d+$')
    inside = self.run_with({'context_zone': [1200, 2000]}, ['--segment'],
                           stdin=payload)
    self.assertRegex(inside.stdout.strip(), r'^🟢\d+⚠$')
    outside = self.run_with({'context_zone': [2000, 3000]}, ['--segment'],
                            stdin=payload)
    self.assertRegex(outside.stdout.strip(), r'^🟢\d+$')
    os.unlink(path)

  def test_calibrate_reads_a_labels_file(self):
    home = tempfile.mkdtemp()
    project = os.path.join(home, '.claude', 'projects', 'p')
    os.makedirs(project)
    calm = [user('please build it'), assistant('Done.')] * 30
    rough = []
    for index in range(30):
      rough.append(user('no, wrong again', index))
      rough.append(assistant('Sorry, I misread that.', [call(cid='c%d' % index)],
                             second=index))
      rough.append(result('c%d' % index, error=True))
    for name, records in (('aaaa1111', calm), ('bbbb2222', calm[:20] + rough[:9]),
                          ('cccc3333', rough), ('dddd4444', rough)):
      with open(os.path.join(project, name + '-0000.jsonl'), 'w') as handle:
        for record in records:
          handle.write(json.dumps(record) + '\n')
    labels = os.path.join(home, 'labels.json')
    with open(labels, 'w') as handle:
      json.dump({'_note': 'x', 'labels': {'aaaa1111': 0, 'bbbb2222': 1,
                                          'cccc3333': 2, 'dddd4444': 7,
                                          'eeee5555': 2}}, handle)
    env = dict(self.env, HOME=home)
    out = subprocess.run([sys.executable, METER, '--calibrate', labels],
                         capture_output=True, text=True, env=env)
    self.assertEqual(out.returncode, 0, out.stderr)
    self.assertRegex(out.stdout, r'fine +n=1 +median peak +0\.0')
    self.assertRegex(out.stdout, r'friction +n=1 ')
    self.assertRegex(out.stdout, r'failed +n=1 ')
    self.assertIn('cut 35: caught 1 of 1 failed, 0 of 1 fine raised it', out.stdout)
    self.assertIn('cut 55: caught 1 of 1 failed, 0 of 1 fine raised it', out.stdout)
    # with no path given, the labels file beside the settings file is read
    place = os.path.join(home, 'config', 'mariadb-qa')
    os.makedirs(place)
    shutil.copy(labels, os.path.join(place, 'session_meter_labels.json'))
    env['XDG_CONFIG_HOME'] = os.path.join(home, 'config')
    bare = subprocess.run([sys.executable, METER, '--calibrate'],
                          capture_output=True, text=True, env=env)
    self.assertEqual(bare.stdout, out.stdout)
    for broken in ('[]', '{"labels": 7}', '{broken', '{"labels": {}}'):
      with open(labels, 'w') as handle:
        handle.write(broken)
      none = subprocess.run([sys.executable, METER, '--calibrate', labels],
                            capture_output=True, text=True, env=env)
      self.assertEqual(none.returncode, 2, broken)
      self.assertIn('no labelled session found', none.stderr)
    shutil.rmtree(home)


class Hook(unittest.TestCase):

  def setUp(self):
    self.home = tempfile.mkdtemp()
    self.env = dict(os.environ, XDG_CACHE_HOME=self.home)

  def tearDown(self):
    shutil.rmtree(self.home, ignore_errors=True)

  def run_hook(self, payload):
    return subprocess.run([sys.executable, HOOK], input=json.dumps(payload),
                          capture_output=True, text=True, env=self.env)

  def calm(self):
    # forty clean tool calls, no two alike: a full window that reads zero
    records = [user('go', 0)]
    for index in range(40):
      records.append(assistant('x', [call(cid='c%d' % index,
                                          payload={'command': 'true %d' % index})],
                               second=index))
      records.append(result('c%d' % index))
    return records

  def noisy(self):
    records = []
    for index in range(20):
      records.append(user('no, wrong again', index))
      records.append(assistant('Sorry \u2014 I misread that, he did.',
                               [call(cid='c%d' % index)], second=index))
      records.append(result('c%d' % index, error=True))
    return write(records)

  def test_speaks_up_when_the_reading_is_yellow_or_worse(self):
    path = self.noisy()
    out = self.run_hook({'session_id': 'h1', 'transcript_path': path,
                         'prompt': 'no, that is wrong again'})
    self.assertEqual(out.returncode, 0)
    self.assertRegex(out.stdout, r'^session meter \d+ [🟡🟠🔴] \| ')
    self.assertEqual(out.stdout.count('\n'), 1)
    os.unlink(path)

  def test_the_advice_follows_the_band(self):
    sys.path.insert(0, HERE)
    import session_meter_hook as hook
    self.assertEqual(len(hook.ADVICE), len(sm.MARKS))
    self.assertEqual(hook.ADVICE[0], '')
    seen = []
    for rounds, move in ((0, 25), (3, 5), (3, 25)):
      records = self.calm()
      for index in range(rounds):
        records.append(user('that is not right', index))
        records.append(assistant('Sorry, I misread that.',
                                 [call(cid='e%d' % index,
                                       payload={'command': 'false %d' % index})],
                                 second=index))
        records.append(result('e%d' % index, error=True))
      path = write(records)
      out = self.run_hook({'session_id': 'a%d%d' % (rounds, move),
                           'transcript_path': path, 'prompt': 'meter +%d' % move})
      head, _, advice = out.stdout.strip().rpartition(' | ')
      band = sm.band(float(head.split()[2]))
      self.assertEqual(head.split()[3], sm.MARKS[band])
      self.assertEqual(advice, hook.ADVICE[band])
      self.assertTrue(advice)
      seen.append(band)
      os.unlink(path)
    self.assertEqual(seen, [1, 2, 3])

  def test_a_landed_prompt_outside_ascii_is_not_counted_twice(self):
    prompt = 'meter +20\ncaf\u00e9 \u2013 na\u00efve \U0001F642'
    records = self.calm() + [user(prompt)]
    for escaped in (False, True):
      path = write(records, escaped=escaped)
      on_disk = sm.shown(full_reading(path)['score'])
      self.assertEqual(on_disk, 20)
      out = self.run_hook({'session_id': 'u%d' % escaped,
                           'transcript_path': path, 'prompt': prompt})
      self.assertEqual(self.score_of(out), on_disk, escaped)
      os.unlink(path)

  def test_stays_quiet_on_a_clean_session(self):
    path = write([user('please build it'), assistant('Done.')])
    out = self.run_hook({'session_id': 'h2', 'transcript_path': path,
                         'prompt': 'thanks, that works'})
    self.assertEqual(out.stdout.strip(), '')
    os.unlink(path)

  def test_counts_the_prompt_it_fires_for(self):
    records = [user('go', 0)]
    for index in range(30):
      records.append(assistant('x', [call(cid='c%d' % index)], second=index))
      records.append(result('c%d' % index, error=True))
    path = write(records)
    quiet = self.run_hook({'session_id': 'h3', 'transcript_path': path,
                           'prompt': 'fine'})
    loud = self.run_hook({'session_id': 'h4', 'transcript_path': path,
                          'prompt': 'no, wrong again, claude'})
    self.assertNotEqual(quiet.stdout, loud.stdout)
    os.unlink(path)

  def score_of(self, out):
    return float(out.stdout.split()[2])

  def test_does_not_double_count_a_landed_prompt(self):
    # the hand move is flat, so a second helping would show as twice the number
    records = [user('go', 0)]
    for index in range(40):
      records.append(assistant('x', [call(cid='c%d' % index)], second=index))
      records.append(result('c%d' % index))
    records.append(user('meter +20'))
    path = write(records)
    on_disk = sm.shown(full_reading(path)['score'])
    landed = self.run_hook({'session_id': 'h5', 'transcript_path': path,
                            'prompt': 'meter +20'})
    self.assertEqual(self.score_of(landed), on_disk)
    fresh = self.run_hook({'session_id': 'h5b', 'transcript_path': path,
                           'prompt': 'meter +4'})
    # the glide moves with the extra event, so the move lands about whole
    self.assertAlmostEqual(self.score_of(fresh), on_disk + 4, delta=2)
    os.unlink(path)

  def test_says_nothing_while_the_backlog_is_large(self):
    path = write([user('no, wrong again')])
    with open(path, 'a') as handle:                 # push it past the limit
      handle.write(json.dumps(user('x' * (sm.BIG_BACKLOG + 1000))) + '\n')
    self.assertGreater(os.path.getsize(path), sm.BIG_BACKLOG)
    out = self.run_hook({'session_id': 'h7', 'transcript_path': path,
                         'prompt': 'no, wrong again'})
    self.assertEqual(out.returncode, 0)
    self.assertEqual(out.stdout.strip(), '')
    old = os.environ.get('XDG_CACHE_HOME')
    os.environ['XDG_CACHE_HOME'] = self.home
    try:
      self.assertFalse(os.path.exists(sm.cache_file('h7')))
    finally:
      if old is None:
        os.environ.pop('XDG_CACHE_HOME', None)
      else:
        os.environ['XDG_CACHE_HOME'] = old
    os.unlink(path)

  def test_never_saves_the_prompt_it_fed_in_memory(self):
    path = self.noisy()
    self.run_hook({'session_id': 'h8', 'transcript_path': path,
                   'prompt': 'meter +90'})
    old = os.environ.get('XDG_CACHE_HOME')
    os.environ['XDG_CACHE_HOME'] = self.home
    try:
      stored = sm.load('h8', path)
    finally:
      if old is None:
        os.environ.pop('XDG_CACHE_HOME', None)
      else:
        os.environ['XDG_CACHE_HOME'] = old
    self.assertGreater(stored.cursor, 0)            # the scan itself was saved
    self.assertEqual(sum(e.get('hand', 0) for e in stored.ring), 0)
    os.unlink(path)

  def test_silent_on_a_broken_payload(self):
    out = self.run_hook({'session_id': 'h6'})
    self.assertEqual(out.returncode, 0)
    self.assertEqual(out.stdout.strip(), '')
    broken = subprocess.run([sys.executable, HOOK], input='}{',
                            capture_output=True, text=True, env=self.env)
    self.assertEqual(broken.returncode, 0)
    self.assertEqual(broken.stdout.strip(), '')


class EndToEnd(unittest.TestCase):

  def setUp(self):
    self.home = tempfile.mkdtemp()
    self.env = dict(os.environ, XDG_CACHE_HOME=self.home)

  def tearDown(self):
    shutil.rmtree(self.home, ignore_errors=True)

  def test_one_session_through_the_real_entry_points(self):
    records = [user('build the parser', 0)]
    for index in range(8):                      # clean work
      records.append(assistant('Done.', [call(cid='ok%d' % index)],
                               second=index))
      records.append(result('ok%d' % index))
    path = write(records)
    payload = json.dumps({'session_id': 'e1', 'transcript_path': path})
    clean = subprocess.run([sys.executable, METER, '--segment'], input=payload,
                           capture_output=True, text=True, env=self.env)
    self.assertTrue(clean.stdout.strip().startswith('🟢'))

    with open(path, 'a') as handle:             # a failure run
      for index in range(12):
        handle.write(json.dumps(user('no, wrong again', index)) + '\n')
        handle.write(json.dumps(assistant('Sorry \u2014 I got that wrong.',
                                          [call(cid='b%d' % index)],
                                          second=index)) + '\n')
        handle.write(json.dumps(result('b%d' % index, error=True)) + '\n')
    hook = subprocess.run([sys.executable, HOOK], capture_output=True,
                          text=True, env=self.env,
                          input=json.dumps({'session_id': 'e1',
                                            'transcript_path': path,
                                            'prompt': 'why did you stop'}))
    self.assertIn('session meter', hook.stdout)

    with open(path, 'a') as handle:             # a hand move
      handle.write(json.dumps(user('meter +25')) + '\n')
    raised = subprocess.run([sys.executable, METER, '--segment'], input=payload,
                            capture_output=True, text=True, env=self.env)
    self.assertRegex(raised.stdout.strip(), r'^[🟠🔴]\d+⚠?$')

    table = subprocess.run([sys.executable, METER, '--report', path],
                           capture_output=True, text=True, env=self.env)
    self.assertIn('user corrections', table.stdout)
    os.unlink(path)


if __name__ == '__main__':
  unittest.main(verbosity=1)
