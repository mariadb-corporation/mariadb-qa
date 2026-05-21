#!/usr/bin/env python3
# Created by Roel Van de Paar, MariaDB
"""HISTORICAL / LEGACY — DO NOT RUN.
This script was used to bootstrap generator.cpp + pools.h from ../generator/generator.sh.
The C++ generator is now the canonical source and is hand-edited directly. Re-running
this script would overwrite live edits. Kept for reference only."""
import re, os, sys, pathlib

SRC_DIR = "/home/roel/mariadb-qa/generator"
DST_DIR = "/home/roel/mariadb-qa/generatorcpp"
MYSQL_VERSION = "57"
SH = open(f"{SRC_DIR}/generator.sh").read()

# ============================================================
# 1) Parse pool/mapfile section
# ============================================================
POOL_RE = re.compile(r'^mapfile\s+-t\s+(\w+)\s+<\s+(\S+\.txt)\b.*?(\w+)=\$\{#\1\[\*\]\}\s*;\s*(\w+)\(\)\s*\{\s*REPLY=', re.M)
POOL_DATA_RE = re.compile(r'^mapfile\s+-t\s+(\w+)\s+<\s+(\S+\.txt)\b', re.M)
POOLS = []   # list of (poolname, txtfile, helper_name_or_None)
seen = set()
for ln in SH.splitlines():
  m = POOL_RE.match(ln)
  if m:
    n,fn,_,h = m.group(1), m.group(2).replace("$MYSQL_VERSION", MYSQL_VERSION), m.group(3), m.group(4)
    POOLS.append((n, fn, h))
    seen.add(n)
    continue
  m = POOL_DATA_RE.match(ln)
  if m and m.group(1) not in seen:
    POOLS.append((m.group(1), m.group(2).replace("$MYSQL_VERSION", MYSQL_VERSION), None))
    seen.add(m.group(1))
COSTVARS_RE = re.search(r'^costvars=\(([^)]+)\)', SH, re.M)
COSTVARS_LIST = COSTVARS_RE.group(1).split() if COSTVARS_RE else []

# load pool data
POOL_DATA = {}
for (n, fn, _) in POOLS:
  path = os.path.join(SRC_DIR, fn)
  POOL_DATA[n] = open(path).read().splitlines() if os.path.exists(path) else []
# combine datafile + datafile2 (then drop datafile2 pool)
if "datafile" in POOL_DATA and "datafile2" in POOL_DATA:
  POOL_DATA["datafile"] = POOL_DATA["datafile"] + POOL_DATA["datafile2"]
POOL_NAMES = [n for (n,_,_) in POOLS if n != "datafile2"]

# Map mapfile-defined helpers to their pool
POOL_HELPER = { h: n for (n, _, h) in POOLS if h }
# also datafile -> "datafile" helper
POOL_HELPER["datafile"] = "datafile"
POOL_HELPER["costvar"] = "costvars"

# C++ keyword/built-in clashes: rename these helper names with a "h_" prefix in C++
CPP_KEYWORD_CLASHES = {'not', 'operator', 'class', 'struct', 'template', 'new', 'delete', 'this', 'public', 'private', 'protected', 'virtual', 'inline', 'static', 'auto', 'const', 'volatile', 'mutable', 'typename', 'typedef', 'union', 'enum', 'namespace', 'using', 'and', 'or', 'xor', 'bitand', 'bitor', 'compl', 'not_eq',
  # also clashes with libc/POSIX globals
  'timezone', 'daylight', 'tzname', 'errno', 'optarg', 'optind', 'optopt', 'environ',
  'index', 'rindex', 'end',
}
def cpp_name(n):
  if n in CPP_KEYWORD_CLASHES: return f"h_{n}"
  return n

# Global state vars (e.g., INC1, INC2 used by partdef helpers).
STATE_VARS = set()

# Top-level config flags emitted as static constexpr int. Always equal to their
# bash source value. Pulled by scanning generator.sh for `^NAME=N` lines.
GLOBAL_CONFIG = {}
for _ln in SH.splitlines():
  _m = re.match(r'^([A-Z][A-Z_0-9]*)\s*=\s*(\d+)\s*(?:#.*)?$', _ln)
  if _m:
    GLOBAL_CONFIG[_m.group(1)] = int(_m.group(2))

# ============================================================
# 2) Identify helper definitions
# ============================================================
# All one-liner bash helpers (functions defined on a single line)
HELPER_RE = re.compile(r'^([a-z][a-z_0-9]*)\(\)\s*\{\s*(.*?)\s*\}\s*(?:#.*)?$')
HELPERS = {}  # name -> body (string, the contents inside the braces)
HELPER_ORDER = []
for ln in SH.splitlines():
  m = HELPER_RE.match(ln)
  if not m:
    continue
  name, body = m.group(1), m.group(2)
  if name in HELPERS:
    continue  # first-wins
  HELPERS[name] = body
  HELPER_ORDER.append(name)

# Multi-line helper extractor: name() { ... } across multiple lines, brace-balanced.
# Only extracts top-level helpers (those with `name()` at column 0). Stops at the
# matching close brace also at column 0. Skips helpers already in HELPERS.
ML_HEADER_RE = re.compile(r'^([a-z][a-z_0-9]*)\(\)\s*\{')
ML_FRAMEWORK_FNS = {"query", "thread", "main", "usage", "cleanup", "error_exit", "trap"}
def extract_multiline_helpers(text):
  out = []
  lines = text.split('\n')
  i = 0
  while i < len(lines):
    m = ML_HEADER_RE.match(lines[i])
    if not m:
      i += 1; continue
    name = m.group(1)
    # Skip framework dispatch functions (not REPLY-emitting helpers)
    if name in ML_FRAMEWORK_FNS:
      i += 1; continue
    # Skip if this is a one-liner (already in HELPERS) or matches HELPER_RE
    if HELPER_RE.match(lines[i]):
      i += 1; continue
    # Brace-balance across subsequent lines. Start with 1 since we saw an open brace.
    depth = lines[i].count('{') - lines[i].count('}')
    body_lines = []
    after = lines[i][m.end():]
    if after.strip():
      body_lines.append(after)
    j = i + 1
    while j < len(lines) and depth > 0:
      depth += lines[j].count('{') - lines[j].count('}')
      if depth <= 0:
        # Trim the trailing close brace from this line
        body_lines.append(re.sub(r'\}\s*$', '', lines[j]))
        break
      body_lines.append(lines[j])
      j += 1
    body = '\n'.join(body_lines).strip()
    if name not in HELPERS:
      HELPERS[name] = body
      HELPER_ORDER.append(name)
    i = j + 1

extract_multiline_helpers(SH)
# Filter out top-level non-helper one-liners that match the regex but aren't really helpers
# (none expected, but safety check: helpers usually contain REPLY= or call other helpers)

# ============================================================
# 3) Find dispatcher cases
# ============================================================
# The query() function dispatches on _pick = $RANDOM % N + 1 via a big case statement.
# Each top-level case starts with a pattern like:
#   N)  case $(($RANDOM % K + 1)) in ... esac;;
# or:
#   N) STATEMENT;;
# Patterns may be ranges like [4-7]|12[0-9][0-9]|...
# We scan the query() function definition and parse it.

# Find the query() function
QF_RE = re.compile(r'^query\(\)\s*\{', re.M)
m = QF_RE.search(SH)
if not m:
  print("FATAL: query() not found", file=sys.stderr); sys.exit(1)
qstart = m.end()
# Find matching closing brace at indent 0 by depth-tracking. query() body uses a nested case.
# Simpler: look for the `*) query;;` line followed by `esac` and then `}`.
qend_re = re.compile(r'^\s*\}\s*$', re.M)
# Scan forward; we want the brace at column 0 that closes query()
# All braces inside are deeper. Look for /^}\s*$/.
qend = qend_re.search(SH, qstart)
if not qend:
  print("FATAL: query() close brace not found", file=sys.stderr); sys.exit(1)
QUERY_BODY = SH[qstart:qend.start()]

# Split into case arms inside the body. The structure is:
#   local _pick=$(($RANDOM % NNN + 1))
#   case ${_pick} in
#     <arms>
#     *) query;;
#   esac
# Each arm is one of:
#   <PATTERN>) <BODY>;;
# where BODY may itself contain a sub-case (case $((RANDOM % K + 1)) in ... esac), terminated by ;;.

# Find the outer case ... esac (the dispatcher block) inside QUERY_BODY.
outer_case_re = re.compile(r'case\s+\$\{?_pick\}?\s+in\b')
m2 = outer_case_re.search(QUERY_BODY)
if not m2:
  print("FATAL: outer dispatcher case not found", file=sys.stderr); sys.exit(1)
inner_start = m2.end()
# Find the matching esac for the outer case. We need balanced "case ... esac".
# Use a hand-rolled scanner.
def find_matching_esac(text, start):
  # The outer dispatcher esac is the LAST `esac` keyword that appears at the start of
  # a line (after optional leading whitespace) before query()'s closing brace.
  # This is robust against bash command substitutions like $(case X in 1) ... esac)
  # inside string literals (those esacs are NEVER at start of a line in this codebase).
  last = None
  for m in re.finditer(r'^\s*esac\b', text[start:], re.M):
    last = (start + m.start(), start + m.end())
  if last is None: return -1, -1
  # The last esac before the function's closing }
  return last
es, ee = find_matching_esac(QUERY_BODY, inner_start)
if es < 0:
  print("FATAL: outer esac not found", file=sys.stderr); sys.exit(1)
DISPATCHER_BODY = QUERY_BODY[inner_start:es]

# Extract dispatcher modulus N
MOD_RE = re.compile(r'\$RANDOM\s*%\s*(\d+)\s*\+\s*1', re.M)
mod_match = MOD_RE.search(QUERY_BODY[:inner_start])
DISPATCH_MOD = int(mod_match.group(1)) if mod_match else 4377

# Now split DISPATCHER_BODY into arms.
# An arm is: <PATTERN_EXPR>) BODY ;;
# Need to handle nested ;; inside arm bodies (case $((..)) in ... ;; esac;;).
# Strategy: scan top-level (case-depth 0 inside outer case), look for "PATTERN)" at the start of a logical line, then everything until the matching ";;" at outer depth.
arms = []  # list of (patterns_list, body_text)
def parse_dispatcher_lineidx(body):
  """Parse top-level dispatcher arms using indentation: outer arms start with exactly 4 spaces."""
  lines = body.split("\n")
  i = 0
  n = len(lines)
  while i < n:
    ln = lines[i]
    if not ln.strip() or ln.lstrip().startswith('#'):
      i += 1; continue
    # outer arm pattern: starts with EXACTLY 4 leading spaces (not 5+)
    if not (ln.startswith('    ') and (len(ln) < 5 or ln[4] != ' ')):
      i += 1; continue
    # Find ')' to extract pattern. May span multiple lines? No — patterns are one line.
    rest = ln[4:]
    pat_end = -1
    paren = 0
    for k, c in enumerate(rest):
      if c == '(': paren += 1
      elif c == ')':
        if paren == 0:
          pat_end = k; break
        paren -= 1
    if pat_end < 0:
      i += 1; continue
    pat = rest[:pat_end].strip()
    # Body: everything from after `)` until line that contains `;;` at outer level
    # Specifically: until we see a line that ends with `;;` AND is at indent <= 6 (so esac;;)
    # OR an inline arm: pattern) body;;  (all on the same line, no inner case)
    after = rest[pat_end+1:]
    # If after contains `;;` AND no `case` keyword starting a sub-case (i.e., no `case ` followed by `in`),
    # this is a single-line arm.
    semi = after.find(';;')
    has_inner_case = re.search(r'\bcase\s+\$\(\(', after) is not None
    if semi >= 0 and not has_inner_case:
      arms.append((pat, after[:semi]))
      i += 1; continue
    # Multi-line arm with inner case. Collect lines until we see `esac;;` at any
    # indent ≥ 4 spaces (per-arm indents vary: 4-7 spaces). The outermost dispatcher
    # arms start with exactly 4 spaces; inner esac;; is always more indented.
    body_lines = [after]
    i += 1
    inner_case_depth = 0  # Track nested `case` to correctly find the matching esac
    # If `after` already opened a `case`, depth starts at 1
    if re.search(r'\bcase\s+\$\(\(', after):
      inner_case_depth = 1
    while i < n:
      l2 = lines[i]
      body_lines.append(l2)
      ls = l2.lstrip()
      # Nested case opener inside this arm
      if re.search(r'\bcase\s+\$\(\(', l2):
        inner_case_depth += 1
      # esac at start of stripped line, possibly with `;;`
      if ls.startswith('esac;;') or ls == 'esac;;' or re.match(r'^esac\s*;;', ls):
        inner_case_depth -= 1
        if inner_case_depth <= 0:
          i += 1
          break
      i += 1
    arms.append((pat, "\n".join(body_lines)))
  return arms

def parse_dispatcher(body):
  # Tokenize lines. The body usually has each top-level arm starting on its own line:
  #   N) ... ;;
  #   or:
  #   N) case $((RANDOM % K + 1)) in
  #         1) ... ;;
  #         ...
  #      esac;;
  i = 0
  while i < len(body):
    # Skip whitespace/comments
    while i < len(body) and body[i] in ' \t\n':
      i += 1
    if i >= len(body):
      break
    if body[i] == '#':
      # Comment to EOL
      j = body.find('\n', i)
      i = j+1 if j > 0 else len(body)
      continue
    # Read the pattern up to unmatched ')'
    pat_start = i
    paren_depth = 0
    while i < len(body):
      c = body[i]
      if c == '(':
        paren_depth += 1
      elif c == ')':
        if paren_depth == 0:
          break
        paren_depth -= 1
      i += 1
    if i >= len(body):
      break
    pat = body[pat_start:i].strip()
    i += 1  # skip ')'
    # Now read body until ";;" at outer-arm depth. Use a line-start anchor for case/esac
    # to avoid false-matching inside string literals like $(case ... esac).
    arm_start = i
    case_depth = 0
    LINE_KW = re.compile(r'(?:^|\n)[ \t]*(case|esac)\b')
    found_arm_end = False
    while i < len(body):
      m_kw = LINE_KW.search(body, i)
      m_dsc = body.find(';;', i)
      if m_dsc == -1: m_dsc = len(body)
      kw_pos = m_kw.start(1) if m_kw else len(body)
      if m_dsc < kw_pos:
        if case_depth == 0:
          arms.append((pat, body[arm_start:m_dsc]))
          i = m_dsc + 2
          found_arm_end = True
          break
        else:
          i = m_dsc + 2
      else:
        if not m_kw:
          break
        if m_kw.group(1) == "case":
          case_depth += 1
        else:
          case_depth -= 1
        i = m_kw.end(1)
    if not found_arm_end:
      break
  return arms
parse_dispatcher_lineidx(DISPATCHER_BODY)

print(f"# dispatcher arms parsed: {len(arms)}, modulus: {DISPATCH_MOD}", file=sys.stderr)
print(f"# helpers (one-liners) parsed: {len(HELPERS)}", file=sys.stderr)

# Expand bash patterns like  N | [A-B] | NN[0-9] | 12[0-3][0-9]  into a list of integers.
def expand_pattern(pat):
  pat = pat.strip()
  results = []
  if pat == "*":
    return ["__default__"]
  for alt in pat.split('|'):
    alt = alt.strip()
    if re.fullmatch(r'\d+', alt):
      results.append(int(alt))
    elif re.fullmatch(r'\[\d-\d\]', alt):
      # e.g., [1-3]
      a, b = int(alt[1]), int(alt[3])
      results.extend(range(a, b+1))
    else:
      # General glob with [N-M] and digit ranges. Expand by brute combination.
      # Convert to regex of literal digits and ranges.
      # e.g., "12[0-9][0-9]" -> 1200..1299
      # e.g., "13[0-4][0-9]" -> 1300..1349
      m = re.fullmatch(r'([\d\[\]\-\?]+)', alt)
      if not m:
        # unknown pattern; skip
        print(f"  WARN: unknown pattern alt: {alt!r}", file=sys.stderr)
        continue
      # Expand: walk through, for each char, either digit or [a-b]
      pieces = []
      i = 0
      while i < len(alt):
        if alt[i] == '[':
          j = alt.find(']', i)
          inner = alt[i+1:j]
          if re.fullmatch(r'\d-\d', inner):
            a, b = int(inner[0]), int(inner[2])
            pieces.append(list(range(a, b+1)))
          else:
            pieces.append([int(d) for d in inner if d.isdigit()])
          i = j+1
        elif alt[i].isdigit():
          pieces.append([int(alt[i])])
          i += 1
        elif alt[i] == '?':
          pieces.append(list(range(0,10)))
          i += 1
        else:
          i += 1
      # cartesian product
      def cart(idx, num):
        if idx == len(pieces):
          results.append(num)
          return
        for d in pieces[idx]:
          cart(idx+1, num*10+d)
      cart(0, 0)
  return results

# Build case_id -> arm_body map.
CASE_ARMS = {}
DEFAULT_ARM = None
for (pat, body) in arms:
  expanded = expand_pattern(pat)
  for v in expanded:
    if v == "__default__":
      DEFAULT_ARM = body
    else:
      if v in CASE_ARMS:
        pass  # silently keep first
      else:
        CASE_ARMS[v] = body

print(f"# distinct case IDs: {len(CASE_ARMS)}, default arm: {'yes' if DEFAULT_ARM else 'no'}", file=sys.stderr)

# ============================================================
# 4) Bash string -> C++ expression translator
# ============================================================
# A REPLY="..." string contains a mix of:
#   * literal text (possibly with bash escapes inside "...")
#   * ${var}, $var, ${arr[idx]}, ${var/pat/rep}, ${var//pat/rep}
#   * $((arith))   — usually $((RANDOM % N + M)) or similar
#   * $(cmd)       — rare; some helpers use $((var)) which we handle as arith too
#
# Output: a C++ expression that builds the resulting string.
# Use a mutable std::string buffer via emit_to(buf): emit "buf += ..." statements.

def parse_arith(expr, ctx_vars):
  """Translate a bash arithmetic expression like 'RANDOM % 100 + 5' into C++ code."""
  e = expr.strip()
  # Common patterns:
  m = re.fullmatch(r'\s*RANDOM\s*%\s*(\d+)\s*\+\s*(-?\d+)\s*', e)
  if m: return f"(rnd() % {m.group(1)} + {m.group(2)})"
  m = re.fullmatch(r'\s*RANDOM\s*%\s*(\d+)\s*-\s*(\d+)\s*', e)
  if m: return f"(rnd() % {m.group(1)} - {m.group(2)})"
  m = re.fullmatch(r'\s*RANDOM\s*%\s*(\d+)\s*', e)
  if m: return f"(rnd() % {m.group(1)})"
  m = re.fullmatch(r'\s*RANDOM\s*', e)
  if m: return "rnd()"
  # var reference (bash arithmetic context resolves $VAR or VAR)
  m = re.fullmatch(r'\s*([A-Za-z_]\w*)\s*', e)
  if m:
    v = m.group(1)
    if v == "RANDOM": return "rnd()"
    # might be a count-of-pool like TABLES
    if v.isupper() and v.lower() in POOL_DATA:
      return str(len(POOL_DATA[v.lower()]))
    if v == "COSTVARS":
      return str(len(COSTVARS_LIST))
    if v in STATE_VARS:
      return v   # bare state var
    return f"({v}_g)"   # fallback: treat as global (rare)
  # Generic substitution: strip $VAR -> VAR first, then replace RANDOM with rnd().
  e2 = e
  # Strip $ prefix on any var name (bash arith allows both $VAR and VAR)
  e2 = re.sub(r'\$(\w+)', r'\1', e2)
  e2 = re.sub(r'\bRANDOM\b', 'rnd()', e2)
  # State vars stay as-is; pool counts get _g suffix.
  def fix(m):
    v = m.group(0)
    if v in STATE_VARS: return v
    if v.isupper() and v.lower() in POOL_DATA: return str(len(POOL_DATA[v.lower()]))
    if v == "COSTVARS": return str(len(COSTVARS_LIST))
    return v
  e2 = re.sub(r'\b[A-Z_][A-Z_0-9]+\b', fix, e2)
  return f"({e2})"

# C++ string-literal escaping for the literal portions
def cescape(s):
  out = []
  prev_hex = False
  for b in s.encode("utf-8"):
    if b == ord('\\'): out.append('\\\\'); prev_hex = False
    elif b == ord('"'): out.append('\\"'); prev_hex = False
    elif b == ord('\n'): out.append('\\n'); prev_hex = False
    elif b == ord('\t'): out.append('\\t'); prev_hex = False
    elif b == ord('\r'): out.append('\\r'); prev_hex = False
    elif 32 <= b < 127:
      ch = chr(b)
      if prev_hex and ch in "0123456789abcdefABCDEF":
        out.append('""' + ch)
      else:
        out.append(ch)
      prev_hex = False
    else:
      out.append(f'\\x{b:02x}')
      prev_hex = True
  return ''.join(out)

# Process bash double-quoted string content -> list of (kind, value) chunks.
# kind in {"lit", "expr"}; "lit" = C++ string literal body, "expr" = C++ expression yielding a std::string-convertible value.
def parse_bash_dq_string(s):
  """Take a bash double-quoted string CONTENT (between the quotes) and emit chunks."""
  chunks = []
  cur_lit = []
  i = 0
  n = len(s)
  while i < n:
    c = s[i]
    if c == '\\' and i+1 < n:
      nxt = s[i+1]
      if nxt == '"':
        cur_lit.append('"'); i += 2; continue
      if nxt == '\\':
        cur_lit.append('\\'); i += 2; continue
      if nxt == '$':
        cur_lit.append('$'); i += 2; continue
      if nxt == '`':
        cur_lit.append('`'); i += 2; continue
      # other bash backslash in double-quote: backslash is preserved literally
      cur_lit.append('\\'); cur_lit.append(nxt); i += 2; continue
    if c == '$':
      if i+1 < n and s[i+1] == '(':
        # $(  or  $((
        if i+2 < n and s[i+2] == '(':
          # arithmetic $((...))
          j = i + 3
          paren = 2
          while j < n and paren > 0:
            if s[j] == '(': paren += 1
            elif s[j] == ')': paren -= 1
            j += 1
          # back up 2 closing parens
          expr = s[i+3:j-2]
          # flush literal
          if cur_lit: chunks.append(("lit", ''.join(cur_lit))); cur_lit = []
          chunks.append(("arith", expr))
          i = j
          continue
        else:
          # command substitution — rare, treat as literal '$(' for safety
          cur_lit.append('$')
          i += 1
          continue
      elif i+1 < n and s[i+1] == '{':
        # ${...}  — variable or array access
        j = i + 2
        depth = 1
        while j < n and depth > 0:
          if s[j] == '{': depth += 1
          elif s[j] == '}': depth -= 1
          j += 1
        spec = s[i+2:j-1]
        if cur_lit: chunks.append(("lit", ''.join(cur_lit))); cur_lit = []
        chunks.append(("var", spec))
        i = j
        continue
      elif i+1 < n and (s[i+1].isalpha() or s[i+1] == '_'):
        # $VAR
        j = i + 1
        while j < n and (s[j].isalnum() or s[j] == '_'):
          j += 1
        name = s[i+1:j]
        if cur_lit: chunks.append(("lit", ''.join(cur_lit))); cur_lit = []
        chunks.append(("var", name))
        i = j
        continue
      else:
        cur_lit.append('$'); i += 1; continue
    cur_lit.append(c); i += 1
  if cur_lit:
    chunks.append(("lit", ''.join(cur_lit)))
  return chunks

def emit_var_chunk(spec, locals_in_scope):
  """Translate a ${spec} reference to a C++ expression yielding text.
  spec patterns:
    NAME                            -> name (string)
    arr[INDEX]                      -> pool_arr[INDEX] (string_view)
    arr[$((RANDOM % SIZE))]          -> pool_arr[(rnd() % SIZE)]
    var/PAT/REP                     -> single-replace
    var//PAT/REP                    -> replace-all
    #arr[*]                         -> array size
  """
  s = spec.strip()
  # Length-of-array
  m = re.fullmatch(r'#(\w+)\[\*\]', s)
  if m:
    name = m.group(1)
    if name in POOL_DATA:
      return f'std::to_string({len(POOL_DATA[name])})'
    return f"std::to_string({name}_size)"
  # array index access
  m = re.fullmatch(r'(\w+)\[(.+?)\]', s, re.S)
  if m:
    name, idx = m.group(1), m.group(2)
    if name in POOL_DATA:
      return f"std::string(pool_{name}[{parse_arith(idx, locals_in_scope)} % pool_{name}.size()])"
    return f"std::string({name}[{parse_arith(idx, locals_in_scope)}])"
  # Variable with substitution: var/PAT/REP  or var//PAT/REP
  m = re.fullmatch(r'(\w+)(/{1,2})(.*?)/(.*)', s, re.S)
  if m:
    name, op, pat, rep = m.group(1), m.group(2), m.group(3), m.group(4)
    rep_expr = bash_to_cpp_expr('"' + rep + '"', locals_in_scope)
    pat_expr = bash_to_cpp_expr('"' + pat + '"', locals_in_scope)
    all_flag = "true" if op == "//" else "false"
    cpp_var = "tls_reply" if name == "REPLY" else name
    return f"bash_replace({cpp_var}, {pat_expr}, {rep_expr}, {all_flag})"
  # Strip-suffix forms: ${var%%PAT*} (longest = leftmost match) and ${var%PAT*} (shortest = rightmost).
  m = re.fullmatch(r'(\w+)(%%|%)(.+?)\*', s, re.S)
  if m:
    name, op, pat = m.group(1), m.group(2), m.group(3)
    cpp_var = "tls_reply" if name == "REPLY" else name
    use_rfind = "true" if op == "%" else "false"
    return f'bash_strip_suffix({cpp_var}, "{cescape(pat)}", {use_rfind})'
  # plain VAR
  if re.fullmatch(r'\w+', s):
    if s == "REPLY":
      return "tls_reply"
    if s in STATE_VARS:
      return f"std::to_string({s})"
    return s
  # Fallback: emit literal $-expansion
  return f'std::string("${{{cescape(s)}}}")'

def bash_to_cpp_expr(quoted_string, locals_in_scope=None):
  """Bash double-quoted string -> C++ expression that evaluates to a std::string."""
  if locals_in_scope is None: locals_in_scope = {}
  s = quoted_string.strip()
  if not (s.startswith('"') and s.endswith('"')):
    if s.startswith("'") and s.endswith("'"):
      return f'std::string("{cescape(s[1:-1])}")'
    return f'std::string("{cescape(s)}")'
  content = s[1:-1]
  chunks = parse_bash_dq_string(content)
  if not chunks:
    return 'std::string()'
  parts = []
  for (kind, val) in chunks:
    if kind == "lit":
      parts.append(f'std::string("{cescape(val)}")')
    elif kind == "arith":
      parts.append(f'std::to_string({parse_arith(val, locals_in_scope)})')
    elif kind == "var":
      parts.append(emit_var_chunk(val, locals_in_scope))
  if len(parts) == 1:
    return parts[0]
  return '(' + ' + '.join(parts) + ')'

def bash_to_cpp_append(quoted_string, locals_in_scope, buf="tls_reply"):
  """Like bash_to_cpp_expr but emit a sequence of `buf.append(...)` calls — avoids temp allocs."""
  if locals_in_scope is None: locals_in_scope = {}
  s = quoted_string.strip()
  if not (s.startswith('"') and s.endswith('"')):
    if s.startswith("'") and s.endswith("'"):
      return [f'{buf}.append("{cescape(s[1:-1])}");']
    return [f'{buf}.append("{cescape(s)}");']
  content = s[1:-1]
  chunks = parse_bash_dq_string(content)
  if not chunks:
    return []
  out = []
  for (kind, val) in chunks:
    if kind == "lit":
      out.append(f'{buf}.append("{cescape(val)}");')
    elif kind == "arith":
      out.append(f'append_int({buf}, {parse_arith(val, locals_in_scope)});')
    elif kind == "var":
      out.append(f'{buf}.append({emit_var_chunk(val, locals_in_scope)});')
  return out

# ============================================================
# 5) Helper-body translation
# ============================================================
# A helper body is a sequence of bash statements separated by `;` and/or newlines.
# Statements we handle:
#   * REPLY="..."                         -> tls_reply = <expr>
#   * REPLY="$_v"                          -> tls_reply = _v
#   * local _v=$REPLY                      -> std::string _v = tls_reply
#   * local _v=...                         -> std::string _v = <expr>
#   * _v=${...}                            -> _v = <expr>  (with substitution)
#   * helper_call                          -> helper_call()
#   * if (( COND )); then ... ; else ... ; fi
#   * case $(($RANDOM % K + 1)) in ... esac
#   * (( EXPR ))                           -> (no-op for our use; skip)
#   * comments (# ...)
#
# For correctness we tolerate unknown statements by emitting them as a comment.

KW_PAIRS = [('case', 'esac'), ('if', 'fi'), ('for', 'done'), ('while', 'done'), ('until', 'done')]
# Note: bash `select` (interactive menu) removed — it's never used in generator.sh as a
# shell construct, but appears in comments/SQL strings where it would falsely open a
# never-closed keyword scope, blocking subsequent `;;` statement splits.
def smart_split_stmts(body):
  """Split bash body into statements; preserve case/esac, if/fi, etc. blocks as single statements."""
  stmts = []
  cur = []
  i = 0
  n = len(body)
  paren = 0
  brace = 0
  brack = 0
  in_sq = False
  in_dq = False
  kw_depth = {}  # opener -> nesting level
  def at_word_boundary(pos, prev=False):
    if prev:
      return pos == 0 or not (body[pos-1].isalnum() or body[pos-1] == '_')
    return True
  def starts_keyword(pos):
    for opener, closer in KW_PAIRS:
      if body[pos:pos+len(opener)] == opener and (pos == 0 or not (body[pos-1].isalnum() or body[pos-1] == '_')) and (pos+len(opener) >= n or not (body[pos+len(opener)].isalnum() or body[pos+len(opener)] == '_')):
        return ('open', opener, closer)
      if body[pos:pos+len(closer)] == closer and (pos == 0 or not (body[pos-1].isalnum() or body[pos-1] == '_')) and (pos+len(closer) >= n or not (body[pos+len(closer)].isalnum() or body[pos+len(closer)] == '_')):
        # Only count as close if this opener has depth > 0
        if kw_depth.get(opener, 0) > 0:
          return ('close', opener, closer)
    return None
  any_kw_open = lambda: any(v > 0 for v in kw_depth.values())
  while i < n:
    c = body[i]
    if in_sq:
      cur.append(c); i += 1
      if c == "'": in_sq = False
      continue
    if in_dq:
      cur.append(c)
      if c == '\\' and i+1 < n:
        cur.append(body[i+1]); i += 2; continue
      if c == '"': in_dq = False
      i += 1; continue
    if c == "'":
      in_sq = True; cur.append(c); i += 1; continue
    if c == '"':
      in_dq = True; cur.append(c); i += 1; continue
    if c == '(':
      paren += 1; cur.append(c); i += 1; continue
    if c == ')':
      # Only decrement if balanced; otherwise this is a bash case sub-arm pattern terminator (e.g., "1)")
      if paren > 0: paren -= 1
      cur.append(c); i += 1; continue
    if c == '{':
      brace += 1; cur.append(c); i += 1; continue
    if c == '}':
      if brace > 0: brace -= 1
      cur.append(c); i += 1; continue
    if c == '[':
      brack += 1; cur.append(c); i += 1; continue
    if c == ']':
      if brack > 0: brack -= 1
      cur.append(c); i += 1; continue
    # Detect keyword start/end at word boundary (only when not inside parens/braces/brackets/strings)
    if paren == 0 and brace == 0 and brack == 0:
      kw = starts_keyword(i)
      if kw is not None:
        action, opener, closer = kw
        if action == 'open':
          kw_depth[opener] = kw_depth.get(opener, 0) + 1
          cur.append(body[i:i+len(opener)])
          i += len(opener)
          continue
        else:
          kw_depth[opener] -= 1
          cur.append(body[i:i+len(closer)])
          i += len(closer)
          continue
    # Statement separators only at outer depth
    if c == ';' and paren == 0 and brace == 0 and brack == 0 and not any_kw_open():
      if i+1 < n and body[i+1] == ';':
        s = ''.join(cur).strip()
        if s: stmts.append(s)
        cur = []
        i += 2; continue
      s = ''.join(cur).strip()
      if s: stmts.append(s)
      cur = []
      i += 1; continue
    if c == '\n' and paren == 0 and brace == 0 and brack == 0 and not any_kw_open():
      s = ''.join(cur).strip()
      if s: stmts.append(s)
      cur = []
      i += 1; continue
    cur.append(c); i += 1
  s = ''.join(cur).strip()
  if s: stmts.append(s)
  return stmts

def translate_bracket_test(expr, locals_in_scope):
  """Translate a bash `[[ ... ]]` condition expression to a C++ boolean expression.
  Supports:
    * "$VAR" == *LITERAL*       -> VAR.find("LITERAL") != npos
    * "$VAR" =~ (A|B|C)         -> (VAR.find("A") != npos || ...)
    * ! EXPR                    -> !(EXPR)
    * EXPR && EXPR, EXPR || EXPR
  Falls back to `(rnd() & 1)` on unrecognised forms so the helper still runs.
  """
  s = expr.strip()
  # Tokenize: identifiers, `&&`, `||`, `!`, `(`, `)`, `==`, `=~`, quoted strings, $VARS, glob patterns
  toks = []
  i = 0
  n = len(s)
  while i < n:
    c = s[i]
    if c.isspace():
      i += 1; continue
    if c == '&' and i+1 < n and s[i+1] == '&':
      toks.append(('&&', '&&')); i += 2; continue
    if c == '|' and i+1 < n and s[i+1] == '|':
      toks.append(('||', '||')); i += 2; continue
    if c == '!':
      toks.append(('!', '!')); i += 1; continue
    if c == '(':
      toks.append(('(', '(')); i += 1; continue
    if c == ')':
      toks.append((')', ')')); i += 1; continue
    if s.startswith('==', i):
      toks.append(('==', '==')); i += 2; continue
    if s.startswith('=~', i):
      toks.append(('=~', '=~')); i += 2; continue
    if c == '"':
      j = i+1
      while j < n and s[j] != '"':
        if s[j] == '\\' and j+1 < n: j += 2; continue
        j += 1
      toks.append(('str', s[i+1:j]))
      i = j+1; continue
    # Bareword (glob pattern, regex group, identifier). Read until space/operator.
    # Stops at structural tokens; allows lone `|` and `&` as content (regex alternation, etc.).
    j = i
    while j < n and not s[j].isspace() and s[j] not in '()=!':
      # Allow `\ ` (escaped space) inside the word
      if s[j] == '\\' and j+1 < n: j += 2; continue
      # Stop on doubled `||` or `&&` (those are operators, not bareword content)
      if (s[j] == '|' and j+1 < n and s[j+1] == '|') or \
         (s[j] == '&' and j+1 < n and s[j+1] == '&'):
        break
      j += 1
    if j == i:
      # No progress — bareword start char is junk; consume one char as fallback
      toks.append(('word', s[i])); i += 1; continue
    toks.append(('word', s[i:j]))
    i = j

  # Recursive-descent parse: or := and ('||' and)*; and := atom ('&&' atom)*; atom := '!' atom | '(' or ')' | cmp
  pos = [0]
  def peek():
    return toks[pos[0]] if pos[0] < len(toks) else ('end', '')
  def consume():
    t = peek(); pos[0] += 1; return t
  def parse_or():
    left = parse_and()
    while peek()[0] == '||':
      consume(); right = parse_and()
      left = f"({left} || {right})"
    return left
  def parse_and():
    left = parse_atom()
    while peek()[0] == '&&':
      consume(); right = parse_atom()
      left = f"({left} && {right})"
    return left
  def parse_atom():
    t = peek()
    if t[0] == '!':
      consume(); return f"!({parse_atom()})"
    if t[0] == '(':
      consume(); v = parse_or()
      if peek()[0] == ')': consume()
      return v
    # cmp := LHS (== | =~) RHS
    lhs = consume()
    op = consume()
    rhs = consume()
    return cmp_to_cpp(lhs, op, rhs)
  def cmp_to_cpp(lhs, op, rhs):
    # LHS: "str" containing $VAR
    lhs_var = None
    if lhs[0] == 'str':
      m = re.fullmatch(r'\$\{?(\w+)\}?', lhs[1])
      if m: lhs_var = m.group(1)
    elif lhs[0] == 'word':
      m = re.fullmatch(r'\$\{?(\w+)\}?', lhs[1])
      if m: lhs_var = m.group(1)
    if lhs_var is None:
      return "(rnd() & 1)"  # fallback
    # `==` with glob *PAT* → string-contains; else direct equality
    if op[0] == '==':
      pat = rhs[1]
      if pat.startswith('*') and pat.endswith('*') and len(pat) >= 2:
        needle = pat[1:-1]
        return f'({lhs_var}.find("{cescape(needle)}") != std::string::npos)'
      if pat.startswith('*'):
        needle = pat[1:]
        return f'({lhs_var}.size() >= {len(needle)} && {lhs_var}.compare({lhs_var}.size()-{len(needle)}, {len(needle)}, "{cescape(needle)}") == 0)'
      if pat.endswith('*'):
        needle = pat[:-1]
        return f'({lhs_var}.compare(0, {len(needle)}, "{cescape(needle)}") == 0)'
      return f'({lhs_var} == "{cescape(pat)}")'
    if op[0] == '=~':
      # regex: handle (A|B|C) as set of substrings, else fall back to true
      r = rhs[1].lstrip('(').rstrip(')')
      # Unescape "\ " -> " "
      r = r.replace('\\ ', ' ')
      alts = r.split('|')
      checks = ' || '.join(
        f'{lhs_var}.find("{cescape(a)}") != std::string::npos' for a in alts if a
      )
      return f'({checks})' if checks else '(rnd() & 1)'
    return "(rnd() & 1)"
  try:
    return parse_or()
  except Exception:
    return "(rnd() & 1)"

def parse_if_statement(s, cond_kind='arith'):
  """Depth-aware parse of `if (( COND )); then THEN_BODY [; else ELSE_BODY] ; fi`
  or `if [[ COND ]]; then ...`. Returns (cond, then_body, else_body) or None.
  Handles nested if/fi and case/esac by tracking keyword depth.
  cond_kind: 'arith' (((...))) or 'bracket' ([[ ... ]])."""
  if cond_kind == 'arith':
    m = re.match(r'^if\s*\(\(\s*', s)
    if not m: return None
    i = m.end()
    paren = 2
    while i < len(s) and paren > 0:
      if s[i] == '(': paren += 1
      elif s[i] == ')': paren -= 1
      i += 1
    if paren != 0: return None
    cond = s[m.end():i-2].strip()
  else:  # bracket
    m = re.match(r'^if\s*\[\[\s*', s)
    if not m: return None
    i = m.end()
    # Find matching `]]`. We track no nesting for `[[ ]]` (not nestable in bash).
    end = s.find(']]', i)
    if end < 0: return None
    cond = s[m.end():end].strip()
    i = end + 2
  # Expect `[; or newline] then ` (semicolon optional when followed by newline)
  m2 = re.match(r'\s*;?\s*then\b\s*', s[i:])
  if not m2: return None
  i += m2.end()
  body_start = i
  # Walk through s looking for `else` or `fi` at outer if-depth.
  # Track keyword pairs: if/fi, case/esac.
  if_depth = 0
  case_depth = 0
  in_sq = False
  in_dq = False
  then_end = -1
  else_start = -1
  fi_pos = -1
  def at_word(idx):
    return idx == 0 or not (s[idx-1].isalnum() or s[idx-1] == '_')
  def word_at(idx, kw):
    if not s.startswith(kw, idx): return False
    if not at_word(idx): return False
    end = idx + len(kw)
    return end >= len(s) or not (s[end].isalnum() or s[end] == '_')
  while i < len(s):
    c = s[i]
    if in_sq:
      if c == "'": in_sq = False
      i += 1; continue
    if in_dq:
      if c == '\\' and i+1 < len(s): i += 2; continue
      if c == '"': in_dq = False
      i += 1; continue
    if c == "'": in_sq = True; i += 1; continue
    if c == '"': in_dq = True; i += 1; continue
    if word_at(i, 'if'):
      if_depth += 1; i += 2; continue
    if word_at(i, 'case'):
      case_depth += 1; i += 4; continue
    if word_at(i, 'esac'):
      if case_depth > 0: case_depth -= 1
      i += 4; continue
    if word_at(i, 'fi'):
      if if_depth == 0 and case_depth == 0:
        fi_pos = i
        break
      if if_depth > 0: if_depth -= 1
      i += 2; continue
    if word_at(i, 'else'):
      if if_depth == 0 and case_depth == 0 and then_end < 0:
        then_end = i
        else_start = i + 4
        i += 4; continue
      i += 4; continue
    i += 1
  if fi_pos < 0: return None
  if then_end < 0:
    then_body = s[body_start:fi_pos]
    else_body = ""
  else:
    then_body = s[body_start:then_end]
    else_body = s[else_start:fi_pos]
  # Strip trailing `; ` from then/else bodies
  then_body = then_body.strip().rstrip(';').strip()
  else_body = else_body.strip().rstrip(';').strip()
  # Anything after `fi`? Allow trailing whitespace only.
  tail = s[fi_pos + 2:].strip()
  if tail: return None
  return (cond, then_body, else_body)

def translate_statement(stmt, locals_in_scope, out_lines, indent):
  """Translate one bash statement into one or more C++ statements appended to out_lines."""
  s = stmt.strip()
  if not s: return
  if s.startswith('#'): return
  # noop in our context
  if s in (';', '', 'fi', 'esac', 'done', 'then', 'else'): return
  # `>&2 echo "..."` — debug; suppress
  m = re.fullmatch(r'>&2\s+echo\s+(["\']?)(.*?)\1', s)
  if m:
    out_lines.append(indent + f'// stderr: {m.group(2)}')
    return
  # leftover `else REPLY=...`  (from partial if-translation)
  m = re.fullmatch(r'else\s+(.+)', s, re.S)
  if m:
    inner = m.group(1).strip().rstrip(';').rstrip()
    out_lines.append(indent + "// stray else: handled in fallback")
    if inner.startswith('REPLY='):
      out_lines.append(indent + f"tls_reply = {bash_to_cpp_expr(inner[len('REPLY='):], locals_in_scope)};")
    return
  # similar for `then BODY`
  m = re.fullmatch(r'then\s+(.+)', s, re.S)
  if m:
    inner = m.group(1).strip().rstrip(';').rstrip()
    if inner.startswith('REPLY='):
      out_lines.append(indent + f"tls_reply = {bash_to_cpp_expr(inner[len('REPLY='):], locals_in_scope)};")
    return
  # If statement
  if s.startswith('if '):
    # Brace/keyword-depth aware parser: handles nested `if/fi` and `case/esac`.
    # Pattern: `if (( COND )); then THEN_BODY; [else ELSE_BODY;] fi`
    parsed = parse_if_statement(s)
    if parsed is not None:
      cond, then_body, else_body = parsed
      cond_cpp = translate_arith_cond(cond)
      out_lines.append(indent + f"if ({cond_cpp}) {{")
      for st in smart_split_stmts(then_body):
        translate_statement(st, locals_in_scope, out_lines, indent + "  ")
      if else_body:
        out_lines.append(indent + "} else {")
        for st in smart_split_stmts(else_body):
          translate_statement(st, locals_in_scope, out_lines, indent + "  ")
      out_lines.append(indent + "}")
      return
    # Alt: bash [[ ... ]] form — use depth-aware parser (avoids catastrophic regex backtracking)
    if re.match(r'^if\s*\[\[', s):
      parsed = parse_if_statement(s, cond_kind='bracket')
      if parsed is not None:
        cond_text, then_body, else_body = parsed
        cond_cpp = translate_bracket_test(cond_text, locals_in_scope)
        out_lines.append(indent + f"if ({cond_cpp}) {{")
        for st in smart_split_stmts(then_body):
          translate_statement(st, locals_in_scope, out_lines, indent + "  ")
        if else_body:
          out_lines.append(indent + "} else {")
          for st in smart_split_stmts(else_body):
            translate_statement(st, locals_in_scope, out_lines, indent + "  ")
        out_lines.append(indent + "}")
        return
    out_lines.append(indent + f"/* TODO if: {cescape(s[:80])} */")
    out_lines.append(indent + "tls_reply.clear();")
    return
  # case statement
  if s.startswith('case '):
    m = re.match(r'case\s+(.+?)\s+in\s+(.*?)\s+esac\s*$', s, re.S)
    if m:
      sel = m.group(1)
      body = m.group(2)
      sel_cpp = parse_arith_or_var(sel)
      out_lines.append(indent + f"switch ({sel_cpp}) {{")
      # parse arms
      arms2 = parse_simple_case_arms(body)
      for (pat, abody) in arms2:
        if pat == "*":
          out_lines.append(indent + "default: {")
        else:
          for v in expand_pattern(pat):
            out_lines.append(indent + f"case {v}:")
          out_lines.append(indent + "{")
        for st in smart_split_stmts(abody):
          translate_statement(st, locals_in_scope, out_lines, indent + "  ")
        out_lines.append(indent + "} break;")
      out_lines.append(indent + "}")
      return
    out_lines.append(indent + f"/* TODO case: {cescape(s[:80])} */")
    out_lines.append(indent + "tls_reply.clear();")
    return
  # REPLY="..."   (whole-string assignment)
  # Fast path: emit clear()+append calls (zero temp alloc).
  # Self-reference path: when RHS references $REPLY (set by a prior helper call), the
  # fast path is wrong — clear() wipes the inbound value and tls_reply.append(tls_reply)
  # after clear just doubles the literal prefix. Use expr-path so RHS evaluates first,
  # then assigns.
  m = re.fullmatch(r'REPLY=(.+)', s, re.S)
  if m:
    rhs = m.group(1).strip()
    if '$REPLY' in rhs or '${REPLY}' in rhs:
      out_lines.append(indent + f"tls_reply = {bash_to_cpp_expr(rhs, locals_in_scope)};")
    else:
      out_lines.append(indent + "tls_reply.clear();")
      for ap in bash_to_cpp_append(rhs, locals_in_scope, "tls_reply"):
        out_lines.append(indent + ap)
    return
  # local _v=...
  m = re.fullmatch(r'local\s+(\w+)=(.*)', s, re.S)
  if m:
    name, rhs = m.group(1), m.group(2).strip()
    if rhs == '$REPLY':
      out_lines.append(indent + f"std::string {name} = tls_reply;")
    elif rhs.startswith('"') or rhs.startswith("'"):
      out_lines.append(indent + f"std::string {name} = {bash_to_cpp_expr(rhs, locals_in_scope)};")
    elif rhs.startswith('$((') and rhs.endswith('))'):
      out_lines.append(indent + f"int {name} = {parse_arith(rhs[3:-2], locals_in_scope)};")
    elif rhs.startswith('$') and len(rhs) > 1:
      # $VAR or $\{...\}
      out_lines.append(indent + f"std::string {name} = {emit_var_chunk(rhs[1:].strip('{}'), locals_in_scope)};")
    else:
      out_lines.append(indent + f"std::string {name} = {bash_to_cpp_expr('\"' + rhs + '\"', locals_in_scope)};")
    locals_in_scope[name] = True
    return
  # var=...   (also: declare-if-unseen as thread-local long for globals like INC1, INC2)
  m = re.fullmatch(r'(\w+)=(.*)', s, re.S)
  if m:
    name, rhs = m.group(1), m.group(2).strip()
    is_global = name not in locals_in_scope
    if is_global:
      STATE_VARS.add(name)
    # State-var assignment: treat as long-int arithmetic
    if is_global:
      if rhs.startswith('$((') and rhs.endswith('))'):
        out_lines.append(indent + f"{name} = {parse_arith(rhs[3:-2], locals_in_scope)};")
      elif re.fullmatch(r'-?\d+', rhs):
        out_lines.append(indent + f"{name} = {rhs};")
      elif re.fullmatch(r'"-?\d+"', rhs):
        out_lines.append(indent + f"{name} = {rhs[1:-1]};")
      else:
        out_lines.append(indent + f"{name} = 0; /* unparsed: {cescape(rhs[:60])} */")
      return
    # Local-var assignment
    if rhs == '$REPLY':
      out_lines.append(indent + f"{name} = tls_reply;")
    elif rhs.startswith('"') or rhs.startswith("'"):
      out_lines.append(indent + f"{name} = {bash_to_cpp_expr(rhs, locals_in_scope)};")
    elif rhs.startswith('$((') and rhs.endswith('))'):
      out_lines.append(indent + f"{name} = {parse_arith(rhs[3:-2], locals_in_scope)};")
    elif rhs.startswith('${') and rhs.endswith('}'):
      out_lines.append(indent + f"{name} = {emit_var_chunk(rhs[2:-1], locals_in_scope)};")
    elif rhs.startswith('$'):
      out_lines.append(indent + f"{name} = {emit_var_chunk(rhs[1:].strip('{}'), locals_in_scope)};")
    else:
      out_lines.append(indent + f"{name} = {bash_to_cpp_expr('\"' + rhs + '\"', locals_in_scope)};")
    return
  # bare helper call?
  m = re.fullmatch(r'(\w+)', s)
  if m:
    name = m.group(1)
    out_lines.append(indent + f"{cpp_name(name)}();")
    return
  out_lines.append(indent + f"/* TODO stmt: {cescape(s[:80])} */")

def translate_arith_cond(cond):
  """Translate a bash arithmetic condition (inside (( )) ) to C++ expression."""
  c = cond.strip()
  # common: RANDOM % N + 1 <= K
  m = re.fullmatch(r'RANDOM\s*%\s*(\d+)\s*\+\s*1\s*<=\s*(\d+)', c)
  if m: return f"(rnd() % {m.group(1)} + 1) <= {m.group(2)}"
  m = re.fullmatch(r'RANDOM\s*%\s*(\d+)\s*\+\s*1\s*<\s*(\d+)', c)
  if m: return f"(rnd() % {m.group(1)} + 1) < {m.group(2)}"
  m = re.fullmatch(r'(\w+)\s*<\s*(\d+)', c)
  if m: return f"({m.group(1)}_g) < {m.group(2)}"
  # Substitute RANDOM and $VAR
  c2 = re.sub(r'\bRANDOM\b', 'rnd()', c)
  c2 = re.sub(r'\$(\w+)', r'\1_g', c2)
  return c2

def parse_arith_or_var(s):
  s = s.strip()
  if s.startswith('$((') and s.endswith('))'):
    return parse_arith(s[3:-2], {})
  if s.startswith('$'):
    # $VAR or ${var}
    name = s[1:].strip('{}')
    return name
  return s

def parse_simple_case_arms(body):
  """Parse 'PAT) BODY ;; PAT) BODY ;; *) BODY ;;'.
  String- and quote-aware: ignores `case`/`esac`/`;;` inside single/double quotes,
  inside `# ... \n` comments, and inside parens (so `1)` patterns don't fire `)` early)."""
  arms_out = []
  i = 0
  n = len(body)
  while i < n:
    # skip whitespace and comments-to-EOL
    while i < n:
      if body[i] in ' \t\n':
        i += 1
      elif body[i] == '#':
        j = body.find('\n', i)
        i = j+1 if j >= 0 else n
      else:
        break
    if i >= n: break
    # read pattern up to ')'
    j = i
    paren = 0
    while j < n:
      c = body[j]
      if c == '(': paren += 1
      elif c == ')':
        if paren == 0: break
        paren -= 1
      j += 1
    if j >= n: break
    pat = body[i:j].strip()
    j += 1
    # read body to ;; at case_depth == 0, skipping quoted strings and comments
    k = j
    case_depth = 0
    in_sq = False
    in_dq = False
    found = False
    while k < n:
      c = body[k]
      if in_sq:
        if c == "'": in_sq = False
        k += 1; continue
      if in_dq:
        if c == '\\' and k+1 < n: k += 2; continue
        if c == '"': in_dq = False
        k += 1; continue
      if c == "'": in_sq = True; k += 1; continue
      if c == '"': in_dq = True; k += 1; continue
      if c == '#':
        # Line comment to EOL
        nl = body.find('\n', k)
        k = nl + 1 if nl >= 0 else n
        continue
      # Check for case/esac/;; at this position
      if body.startswith(';;', k) and case_depth == 0:
        arms_out.append((pat, body[j:k].strip()))
        k += 2; found = True; break
      if body.startswith(';;', k):
        k += 2; continue
      # case keyword (word-bounded)
      if body.startswith('case', k) and (k == 0 or not (body[k-1].isalnum() or body[k-1] == '_')) and (k+4 >= n or not (body[k+4].isalnum() or body[k+4] == '_')):
        case_depth += 1; k += 4; continue
      if body.startswith('esac', k) and (k == 0 or not (body[k-1].isalnum() or body[k-1] == '_')) and (k+4 >= n or not (body[k+4].isalnum() or body[k+4] == '_')):
        case_depth -= 1; k += 4; continue
      k += 1
    if not found:
      break
    i = k
  return arms_out

# ============================================================
# 6) Emit pools.h
# ============================================================
with open(f"{DST_DIR}/pools.h", "w") as o:
  o.write("// AUTOGENERATED — do not edit\n")
  o.write("// Created by Roel Van de Paar, MariaDB\n")
  o.write("#pragma once\n#include <array>\n#include <string_view>\n\n")
  for name in POOL_NAMES:
    entries = POOL_DATA[name]
    o.write(f"inline constexpr std::array<std::string_view, {len(entries)}> pool_{name} = {{\n")
    for e in entries:
      o.write(f'  "{cescape(e)}",\n')
    o.write("};\n\n")
  o.write(f"inline constexpr std::array<std::string_view, {len(COSTVARS_LIST)}> pool_costvars = {{\n")
  for v in COSTVARS_LIST:
    o.write(f'  "{cescape(v)}",\n')
  o.write("};\n\n")
print(f"# pools.h written ({len(POOL_NAMES)+1} pools)", file=sys.stderr)

# ============================================================
# 7) Emit generator.cpp
# ============================================================
HEADER = r"""// AUTOGENERATED — do not edit
// Created by Roel Van de Paar, MariaDB
// MariaDB SQL fuzz generator — C++20 port of generator.sh
#include "pools.h"
#include <atomic>
#include <bit>
#include <charconv>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <random>
#include <string>
#include <string_view>
#include <thread>
#include <vector>
#include <getopt.h>
#include <unistd.h>
#include <mysql/mysql.h>

// xoshiro256++ — BigCrush-clean 64-bit PRNG, period 2^256-1. Seeded via splitmix64
// from a high-entropy mix of std::random_device + clock + thread-unique address bits.
struct Xoshiro256pp {
  uint64_t s[4];
  static inline uint64_t splitmix64(uint64_t& x) {
    uint64_t z = (x += 0x9E3779B97F4A7C15ULL);
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
    return z ^ (z >> 31);
  }
  void seed(uint64_t z) {
    s[0] = splitmix64(z); s[1] = splitmix64(z);
    s[2] = splitmix64(z); s[3] = splitmix64(z);
    if ((s[0] | s[1] | s[2] | s[3]) == 0) s[0] = 0x9E3779B97F4A7C15ULL;
  }
  [[gnu::always_inline]] inline uint64_t next() {
    const uint64_t result = std::rotl(s[0] + s[3], 23) + s[0];
    const uint64_t t = s[1] << 17;
    s[2] ^= s[0]; s[3] ^= s[1]; s[1] ^= s[2]; s[0] ^= s[3];
    s[2] ^= t;
    s[3] = std::rotl(s[3], 45);
    return result;
  }
};

thread_local Xoshiro256pp tls_rng = []{
  Xoshiro256pp x;
  std::random_device rd;
  uint64_t s = (uint64_t(rd()) << 32) ^ rd();
  s ^= uint64_t(std::chrono::high_resolution_clock::now().time_since_epoch().count());
  s ^= uint64_t(reinterpret_cast<uintptr_t>(&x));
  x.seed(s);
  return x;
}();
thread_local std::string tls_reply;
thread_local std::string tls_out_buf;

// Top 31 bits of xoshiro256++ output, returned as positive int. Top bits used because
// they're the highest-quality bits from xoshiro (lowest correlation).
[[gnu::always_inline]] static inline int rnd() {
  return static_cast<int>(tls_rng.next() >> 33);
}

static inline std::string bash_replace(std::string s, std::string_view pat, std::string_view rep, bool all) {
  if (pat.empty()) return s;
  size_t pos = s.find(pat);
  if (pos == std::string::npos) return s;
  do {
    s.replace(pos, pat.size(), rep);
    pos += rep.size();
    if (!all) break;
    pos = s.find(pat, pos);
  } while (pos != std::string::npos);
  return s;
}
// Append a signed integer to a string without going through std::to_string (avoids alloc).
[[gnu::always_inline]] static inline void append_int(std::string& s, long v) {
  char buf[24];
  auto r = std::to_chars(buf, buf + sizeof(buf), v);
  s.append(buf, r.ptr);
}

// Collapse runs of >=2 spaces to a single space, but preserve content inside SQL
// quotes ('...'), double quotes ("..."), and backtick identifiers (`...`). Handles
// the standard SQL '' doubled-quote escape and the MySQL/MariaDB \' backslash escape.
static inline void collapse_double_spaces(std::string& s) {
  if (s.size() < 2) return;
  char* w = s.data();
  const char* r = s.data();
  const char* end = s.data() + s.size();
  char in_q = 0;
  bool last_space = false;
  while (r < end) {
    char c = *r;
    if (in_q) {
      *w++ = c;
      if (c == '\\' && r + 1 < end) {
        *w++ = r[1];
        r += 2;
        continue;
      }
      if (c == in_q) {
        if (r + 1 < end && r[1] == in_q) {  // doubled-quote escape
          *w++ = r[1];
          r += 2;
          continue;
        }
        in_q = 0;
      }
      ++r;
      last_space = false;
    } else if (c == '\'' || c == '"' || c == '`') {
      in_q = c;
      *w++ = c;
      ++r;
      last_space = false;
    } else if (c == ' ') {
      if (!last_space) *w++ = c;
      last_space = true;
      ++r;
    } else {
      *w++ = c;
      ++r;
      last_space = false;
    }
  }
  s.resize(w - s.data());
}

// ----- pool-size helpers (for arith expressions that referenced POOL_SIZE globals) -----
"""

POOL_GLOBALS = "\n".join(
  f"static constexpr int {n.upper()}_g = static_cast<int>(pool_{n}.size());" for n in POOL_NAMES
) + "\nstatic constexpr int COSTVARS_g = static_cast<int>(pool_costvars.size());\n"

# Emit helpers (one-liners). We translate each to a C++ inline function returning void.
def emit_helper(name, body):
  out_lines = []
  out_lines.append(f"static inline void {cpp_name(name)}() {{")
  locals_in_scope = {}
  for st in smart_split_stmts(body):
    translate_statement(st, locals_in_scope, out_lines, "  ")
  out_lines.append("}")
  return "\n".join(out_lines)

def emit_pool_helper(helper_name, pool_name):
  return f"static inline void {cpp_name(helper_name)}() {{ tls_reply = std::string(pool_{pool_name}[rnd() % pool_{pool_name}.size()]); }}"

def emit_dispatch_fn(case_id, body):
  """Emit a standalone function for one dispatcher case."""
  out_lines = []
  out_lines.append(f"static void d_{case_id}() {{")
  locals_in_scope = {}
  for st in smart_split_stmts(body):
    translate_statement(st, locals_in_scope, out_lines, "  ")
  out_lines.append("}")
  return "\n".join(out_lines)

# Collect helpers we'll emit. Order matters because of `static inline` definitions (forward-decl is needed).
# Strategy: forward-declare all, then define all.
# Build the ordered list of helpers to emit:
#   * pool helpers first (from mapfile parse) — n3, table, ctype, ...
#   * then one-liner helpers (in source order)
#   * then all OTHER helpers defined in generator.sh (multi-line) — emitted as no-op stubs
HELPER_NAMES_ORDERED = []
seen_h = set()
for h in POOL_HELPER.keys():
  if h in seen_h: continue
  HELPER_NAMES_ORDERED.append(h); seen_h.add(h)
for h in HELPER_ORDER:
  if h in seen_h: continue
  HELPER_NAMES_ORDERED.append(h); seen_h.add(h)
# Discover all other helpers defined anywhere in the file (multi-line ones)
ALL_HELPERS = set(re.findall(r'^([a-z][a-z_0-9]*)\(\)', SH, re.M))
STUB_HELPERS = ALL_HELPERS - seen_h - {"query", "thread"}
for h in sorted(STUB_HELPERS):
  HELPER_NAMES_ORDERED.append(h); seen_h.add(h)
POOL_HELPER_NAMES = set(POOL_HELPER.keys())

# Hand-written override for `data()` only — the bash version calls external `pwgen`
# which we can't run; we substitute a fixed pwgen-pool. All other helpers are auto-translated.
HAND_PORTED = {
  "data": r"""static inline void data() {
  // 80%: pwgen-pool string or datafile entry; 20%: timefunc or numeric expression
  if (rnd() % 20 + 1 <= 16) {
    if (rnd() % 20 + 1 <= 10) {
      static thread_local const char* pwgen_pool[] = {
        "abc123","xyz789","quick","brown","fox","jumps","over","lazy","dog","42",
        "p4ss","w0rd","secret","admin","root","test","mysql","fuzz","query","data"
      };
      static thread_local const int pwgen_pool_size = sizeof(pwgen_pool)/sizeof(pwgen_pool[0]);
      tls_reply.assign(1, '\'');
      tls_reply.append(pwgen_pool[rnd() % pwgen_pool_size]);
      tls_reply.push_back('\'');
    } else {
      datafile();
    }
  } else {
    if (rnd() % 20 + 1 <= 10) {
      timefunc();
    } else {
      fullnrfunc();
      std::string _v1 = tls_reply;
      numsimple();
      std::string _v2 = tls_reply;
      fullnrfunc();
      std::string _v3 = std::move(tls_reply);
      tls_reply.assign(1, '(');
      tls_reply.append(_v1);
      tls_reply.append(") ");
      tls_reply.append(_v2);
      tls_reply.append(" (");
      tls_reply.append(_v3);
      tls_reply.push_back(')');
    }
  }
}""",
}

with open(f"{DST_DIR}/generator.cpp", "w") as o:
  o.write(HEADER)
  o.write(POOL_GLOBALS)
  if GLOBAL_CONFIG:
    o.write("\n// ----- top-level config flags from generator.sh (static at build time) -----\n")
    for k in sorted(GLOBAL_CONFIG.keys()):
      # SUBWHEREACTIVE is a runtime state var (mutated by helpers); skip — handled by STATE_VARS.
      if k == "SUBWHEREACTIVE": continue
      o.write(f"static constexpr int {k} = {GLOBAL_CONFIG[k]};\n")
    o.write("\n")
  helper_emissions = []
  for h in HELPER_NAMES_ORDERED:
    if h in HAND_PORTED:
      helper_emissions.append(HAND_PORTED[h])
    elif h in POOL_HELPER:
      helper_emissions.append(emit_pool_helper(h, POOL_HELPER[h]))
    elif h in HELPERS:
      try:
        helper_emissions.append(emit_helper(h, HELPERS[h]))
      except Exception as e:
        helper_emissions.append(f"static inline void {cpp_name(h)}() {{ tls_reply.clear(); /* trans-fail: {e!r} */ }}")
    else:
      helper_emissions.append(f"static inline void {cpp_name(h)}() {{ tls_reply.clear(); /* stub: multi-line helper */ }}")
  # Per-case translation with timeout safeguard against pathological input
  import signal
  class _TimeOut(Exception): pass
  signal.signal(signal.SIGALRM, lambda s,f: (_ for _ in ()).throw(_TimeOut()))
  dispatch_emissions = []
  for cid in sorted(CASE_ARMS.keys()):
    signal.alarm(20)
    try:
      dispatch_emissions.append(emit_dispatch_fn(cid, CASE_ARMS[cid]))
      signal.alarm(0)
    except _TimeOut:
      signal.alarm(0)
      dispatch_emissions.append(f"static void d_{cid}() {{ tls_reply.clear(); /* trans-timeout */ }}")
    except Exception:
      signal.alarm(0)
      dispatch_emissions.append(f"static void d_{cid}() {{ tls_reply.clear(); /* trans-fail */ }}")
  # Emit thread-local state vars after collection
  if STATE_VARS:
    o.write("\n// ----- thread-local state vars (bash globals; modeled as long ints) -----\n")
    for v in sorted(STATE_VARS):
      o.write(f"thread_local long {v} = 0;\n")
  o.write("\n// ----- forward declarations -----\n")
  for h in HELPER_NAMES_ORDERED:
    o.write(f"static inline void {cpp_name(h)}();\n")
  o.write("static void query();\n\n")
  o.write("// ----- helper definitions -----\n")
  for emission in helper_emissions:
    o.write(emission); o.write("\n")
  o.write("\n// ----- dispatcher case functions -----\n")
  for emission in dispatch_emissions:
    o.write(emission); o.write("\n")
  # Function-pointer table: index = case ID (1..DISPATCH_MOD). nullptr = default (re-roll).
  o.write("\nusing case_fn = void(*)();\n")
  o.write(f"static constexpr case_fn dispatch_table[{DISPATCH_MOD+1}] = {{\n  nullptr,\n")
  for i in range(1, DISPATCH_MOD+1):
    if i in CASE_ARMS:
      o.write(f"  d_{i},\n")
    else:
      o.write(f"  nullptr,\n")
  o.write("};\n\n")
  o.write(r"""
// Retry up to N times if the picked arm produces no SQL (some arms can fail-through
// when their inner helpers return empty). Bounded by N to avoid pathological loops.
static void query() {
  for (int retries = 0; retries < 16; ++retries) {
    int _pick = rnd() % """ + str(DISPATCH_MOD) + r""" + 1;
    case_fn fn = dispatch_table[_pick];
    if (!fn) continue;
    fn();
    // Accept if non-empty after trimming whitespace
    for (char c : tls_reply) {
      if (c != ' ' && c != '\t' && c != '\n' && c != '\r') return;
    }
    tls_reply.clear();  // empty/blank — re-roll
  }
}

""")
  # PREPARE-validation support + main
  o.write(r"""
// ----- PREPARE-validation support -----
// Prefixes for statements that are valid SQL but cannot be prepared (server returns
// ER_UNSUPPORTED_PS 1295). Skip PREPARE for these so we don't lose them, and so any
// 1064 from PREPARE-wrapper parser quirks doesn't drop a valid query.
static const std::string_view SKIP_PREPARE_PREFIXES[] = {
  "USE ", "BEGIN", "START ", "COMMIT", "ROLLBACK", "RELEASE ", "SAVEPOINT ",
  "XA ", "LOCK ", "UNLOCK ", "HANDLER ", "LOAD ",
  "INSTALL ", "UNINSTALL ", "KILL ", "CHANGE ", "PURGE ", "RESET ",
  "HELP", "BACKUP ", "RESTORE ", "BINLOG ", "DELIMITER ", "CACHE ", "UNCACHE ",
  "GET DIAGNOSTICS"
};
static inline bool skip_prepare(const char* s, size_t n) {
  size_t i = 0;
  while (i < n && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n')) ++i;
  if (i >= n) return true;
  char head[20];
  size_t hn = std::min(size_t(19), n - i);
  for (size_t k = 0; k < hn; ++k) {
    char c = s[i + k];
    if (c >= 'a' && c <= 'z') c -= 32;
    head[k] = c;
  }
  head[hn] = '\0';
  for (auto p : SKIP_PREPARE_PREFIXES) {
    if (hn >= p.size() && std::memcmp(head, p.data(), p.size()) == 0) return true;
  }
  return false;
}

struct Validator {
  MYSQL* conn = nullptr;
  MYSQL_STMT* stmt = nullptr;
  std::string socket_path;
  FILE* failed_log = nullptr;
  uint64_t total = 0, dropped = 0, server_lost = 0, other_err = 0, skipped = 0;
  bool reconnect() {
    if (stmt) { mysql_stmt_close(stmt); stmt = nullptr; }
    if (conn) { mysql_close(conn); conn = nullptr; }
    conn = mysql_init(nullptr);
    if (!conn) return false;
    if (!mysql_real_connect(conn, nullptr, "root", nullptr, nullptr, 0,
                            socket_path.c_str(), 0)) {
      std::fprintf(stderr, "[validator] connect failed: %s\n", mysql_error(conn));
      mysql_close(conn); conn = nullptr;
      return false;
    }
    stmt = mysql_stmt_init(conn);
    return stmt != nullptr;
  }
  bool init(const std::string& sock, FILE* log) {
    socket_path = sock;
    failed_log = log;
    return reconnect();
  }
  bool validate(const char* sql, size_t len) {
    ++total;
    if (skip_prepare(sql, len)) { ++skipped; return true; }
    if (!stmt && !reconnect()) return true;
    int rc = mysql_stmt_prepare(stmt, sql, static_cast<unsigned long>(len));
    if (rc == 0) return true;
    unsigned int err = mysql_stmt_errno(stmt);
    if (err == 1064) {
      ++dropped;
      if (failed_log) {
        std::fwrite(sql, 1, len, failed_log);
        std::fputs(";\n", failed_log);
      }
      return false;
    }
    if (err == 2006 || err == 2013) {
      ++server_lost;
      std::fprintf(stderr, "[validator] SERVER LOST on prepare of: %.*s\n",
                   (int)std::min(len, size_t(200)), sql);
      reconnect();
      return true;
    }
    ++other_err;
    return true;
  }
  ~Validator() {
    if (stmt) mysql_stmt_close(stmt);
    if (conn) mysql_close(conn);
  }
};
thread_local Validator tls_validator;

// ----- main -----
static void usage() {
  std::cerr <<
    "Usage: generator [--output FILE] [--threads N] [--socket PATH] [--validate-sql] [QUERIES]\n"
    "  --output FILE     output file (default: out.sql)\n"
    "  --threads N       number of generation threads (default: nproc/4)\n"
    "  --socket PATH     mariadbd UNIX socket (required for --validate-sql)\n"
    "  --validate-sql    PREPARE-test each query; drop on ER_PARSE_ERROR (1064).\n"
    "                    Logs dropped queries to failed_1064_on_prepare.txt (append).\n"
    "                    Connects as user=root, no password.\n"
    "  QUERIES           number of queries to generate (default: 1000)\n";
}
[[gnu::used]] int main(int argc, char** argv) {
  std::string out_path = "out.sql";
  long queries = 1000;
  unsigned threads = 0;
  std::string socket_path;
  bool validate_sql = false;
  static struct option opts[] = {
    {"output",       required_argument, nullptr, 'o'},
    {"threads",      required_argument, nullptr, 't'},
    {"socket",       required_argument, nullptr, 's'},
    {"validate-sql", no_argument,       nullptr, 'v'},
    {"help",         no_argument,       nullptr, 'h'},
    {nullptr, 0, nullptr, 0}
  };
  int c;
  while ((c = getopt_long(argc, argv, "o:t:s:vh", opts, nullptr)) != -1) {
    switch (c) {
      case 'o': out_path = optarg; break;
      case 't': threads = std::stoul(optarg); break;
      case 's': socket_path = optarg; break;
      case 'v': validate_sql = true; break;
      case 'h': usage(); return 0;
      default: usage(); return 2;
    }
  }
  if (validate_sql && socket_path.empty()) {
    std::cerr << "--validate-sql requires --socket=PATH\n";
    return 2;
  }
  if (optind < argc) queries = std::stol(argv[optind]);
  if (queries <= 0) { std::cerr << "queries must be > 0\n"; return 2; }
  if (threads == 0) {
    unsigned hc = std::thread::hardware_concurrency();
    threads = std::max(1u, hc / 4);
  }
  if (threads > static_cast<unsigned>(queries)) threads = static_cast<unsigned>(queries);
  std::cerr << "generator: queries=" << queries << " threads=" << threads
            << " out=" << out_path;
  if (validate_sql) std::cerr << " validate=on socket=" << socket_path;
  std::cerr << "\n";

  FILE* failed_log = nullptr;
  if (validate_sql) {
    mysql_library_init(0, nullptr, nullptr);
    failed_log = std::fopen("failed_1064_on_prepare.txt", "a");
    if (!failed_log) std::cerr << "warning: cannot open failed_1064_on_prepare.txt for append\n";
  }

  long per = queries / threads;
  long rem = queries - per * threads;
  std::vector<std::string> part_paths(threads);
  std::vector<std::thread> ts;
  ts.reserve(threads);
  std::atomic<uint64_t> agg_total{0}, agg_dropped{0}, agg_lost{0}, agg_other{0}, agg_skipped{0};

  auto t0 = std::chrono::steady_clock::now();
  for (unsigned i = 0; i < threads; ++i) {
    long n = per + (static_cast<long>(i) < rem ? 1 : 0);
    part_paths[i] = out_path + ".part" + std::to_string(i);
    ts.emplace_back([i, n, &part = part_paths[i], &socket_path, validate_sql, failed_log,
                     &agg_total, &agg_dropped, &agg_lost, &agg_other, &agg_skipped]() {
      if (validate_sql) {
        if (!tls_validator.init(socket_path, failed_log)) {
          std::fprintf(stderr, "thread %u: validator init failed (continuing without validation)\n", i);
        }
      }
      tls_reply.reserve(4096);
      std::ofstream f(part, std::ios::binary | std::ios::trunc);
      if (!f) { std::fprintf(stderr, "thread %u: cannot open %s\n", i, part.c_str()); return; }
      std::string outbuf;
      outbuf.reserve(64 * 1024);
      long emitted = 0;
      long attempts = 0;
      const long attempts_cap = validate_sql ? n * 10 : n * 2;
      auto is_blank = [](const std::string& r) {
        for (char c : r) if (c != ' ' && c != '\t' && c != '\n' && c != '\r') return false;
        return true;
      };
      while (emitted < n && attempts < attempts_cap) {
        tls_reply.clear();
        query();
        collapse_double_spaces(tls_reply);
        ++attempts;
        if (is_blank(tls_reply)) continue;  // skip empty/whitespace queries (helper returned nothing)
        if (validate_sql && tls_validator.conn) {
          if (!tls_validator.validate(tls_reply.data(), tls_reply.size())) continue;
        }
        outbuf.append(tls_reply);
        outbuf.append(";\n", 2);
        if (outbuf.size() >= 64 * 1024) {
          f.write(outbuf.data(), outbuf.size());
          outbuf.clear();
        }
        ++emitted;
      }
      if (!outbuf.empty()) f.write(outbuf.data(), outbuf.size());
      f.close();
      if (validate_sql) {
        agg_total   += tls_validator.total;
        agg_dropped += tls_validator.dropped;
        agg_lost    += tls_validator.server_lost;
        agg_other   += tls_validator.other_err;
        agg_skipped += tls_validator.skipped;
      }
    });
  }
  for (auto& t : ts) t.join();
  auto t1 = std::chrono::steady_clock::now();

  std::ofstream f(out_path, std::ios::binary | std::ios::trunc);
  if (!f) { std::cerr << "cannot open " << out_path << "\n"; return 1; }
  std::vector<char> buf(1 << 20);
  for (auto& p : part_paths) {
    std::ifstream in(p, std::ios::binary);
    while (in) {
      in.read(buf.data(), buf.size());
      f.write(buf.data(), in.gcount());
    }
    in.close();
    std::error_code ec;
    std::filesystem::remove(p, ec);
  }
  f.close();

  auto secs = std::chrono::duration<double>(t1 - t0).count();
  std::cerr << "DONE! Generated " << queries << " queries in " << secs << "s -> " << out_path << "\n";
  if (validate_sql) {
    std::cerr << "[validator] prepared=" << agg_total
              << " skipped(non-preparable)=" << agg_skipped
              << " dropped(1064)=" << agg_dropped
              << " server_lost=" << agg_lost
              << " other_err=" << agg_other << "\n";
    std::cerr << "Any SQL which failed PREPARE-tested verify was logged to failed_1064_on_prepare.txt\n";
    if (failed_log) std::fclose(failed_log);
    mysql_library_end();
  }
  return 0;
}
""")

print(f"# generator.cpp written", file=sys.stderr)
print(f"# done", file=sys.stderr)
