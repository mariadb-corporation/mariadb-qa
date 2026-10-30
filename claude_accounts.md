# Claude Code: swap between Team and Enterprise logins

One command swaps the Claude Code login on Linux, macOS or Windows: `~/claude_teams`,
`~/claude_ent`, or `~/claude_teams1`, `~/claude_teams2` and so on for more than one Team account.
All running sessions follow the swap. Each login is saved, so a swap needs no new login. A warning
shows at session start when a saved login ends within 3 days.

## Set it up

In Claude Code on Linux, macOS, Windows or WSL:

1. Run `/model` and pick Opus 5.5 or newer. Run `/effort max`.
2. Paste this prompt:

```
Fetch https://raw.githubusercontent.com/mariadb-corporation/mariadb-qa/master/claude_accounts.md with curl and follow it
```

Claude asks which accounts you have, installs the commands, and tells you when to log in. On
Windows, it needs Python 3.9 or newer. macOS and Windows are not tested yet, so they may need a
small tweak.

## Use

Run these in a terminal. On Windows, use PowerShell. In Command Prompt, type
`%USERPROFILE%\claude_teams`, and in Git Bash, `~/claude_teams.cmd`.

| Command | What it does |
|---|---|
| `~/claude_teams` | Use the Team login, or stay on it |
| `~/claude_teams1`, `~/claude_teams2`, ... | The same, with more than one Team account |
| `~/claude_ent` | Use the Enterprise login, or stay on it |
| `~/claude_ent --login` | Log in again now, for example when the saved login ends soon |
| `~/claude_ent --sso` | Use single sign-on when a browser login is needed |

The first use of an account opens a browser login, and so does the first use after its saved login
ended. Sign in with that account. When the browser does not open, open the link that the terminal
shows. When the browser shows a code, paste it into the terminal. Each run lists the saved logins
and when each one ends.

To add an account later, make one more link and run it, for example
`ln -s ~/.claude_accounts/claude_swap.py ~/claude_teams3`, then `~/claude_teams3`. On Windows,
copy one of the `.cmd` files in PowerShell, for example
`Copy-Item ~/claude_teams.cmd ~/claude_teams3.cmd`.

To change accounts, use these commands, not `/login` with another account: `/login` replaces the
login in use without a saved copy. To renew the login in use, `/login` with the same account is fine.

## For Claude: setup steps

Do the steps in order. When a check fails, stop and tell the user why in one sentence.

On Windows, use the commands under "PowerShell commands" at the end of these steps, in place of
the bash blocks. When you have no PowerShell tool, use the bash blocks in Git Bash.

### 1. Check the model and the effort

Your system prompt names your model. Run `printenv CLAUDE_EFFORT` for the effort. Go on only when
the model is Opus 5.5 or newer (a Fable model also counts) and the effort is `max`. Otherwise stop,
do nothing else, and reply only with:

> Please swap me to Opus 5.5 or newer at /effort max, and then run this prompt again.

When `printenv CLAUDE_EFFORT` prints nothing, add: "Please also update Claude Code first, with
`claude update`."

### 2. Get an exact copy of this file

A web fetch can return a summary, and the script below must be byte-exact. When this file is on
disk already, for example in a mariadb-qa checkout, use that path. Else download it:

```bash
curl -fsSL https://raw.githubusercontent.com/mariadb-corporation/mariadb-qa/master/claude_accounts.md -o /tmp/claude_accounts.md
```

On Windows, always download it, as a git checkout there can have Windows line ends. Below, FILE is
the path of the copy.

### 3. Check the machine

Below, PY is `python3` on Linux and macOS. On Windows it is `py -3`, or `python` when there is no
`py`.

Each check must give the result in its comment:

```bash
uname -s                     # Linux, Darwin (macOS), or MINGW64_NT-... (Windows)
printenv CLAUDE_CONFIG_DIR   # nothing. This setup uses the default ~/.claude folder
PY -c 'import sys; print(sys.version_info >= (3, 9))'   # True
PY -c 'import os; print(os.path.samefile(os.path.expanduser("~"), os.environ["HOME"]))'   # True
claude auth status           # "loggedIn": false, or "authMethod": "claude.ai"
env | grep -oE '^(ANTHROPIC_API_KEY|ANTHROPIC_AUTH_TOKEN|CLAUDE_CODE_OAUTH_TOKEN|CLAUDE_CODE_USE_(BEDROCK|VERTEX|FOUNDRY))='   # nothing
```

An API key, a token or a cloud provider wins over the claude.ai login, so a swap would do nothing.
On Windows, Python finds the home folder from `USERPROFILE` and Git Bash from `HOME`, and the two
must be the same folder.

### 4. Ask about the accounts

From `claude auth status`, note the email, the organization (`orgName`) and the plan
(`subscriptionType`, `team` or `enterprise`) of the login in use. Ask the user how many Team accounts
and how many Enterprise accounts to swap between. Then pick the names:

- One Team account: `claude_teams`. More: `claude_teams1`, `claude_teams2`, and so on.
- One Enterprise account: `claude_ent`. More: `claude_ent1`, `claude_ent2`, and so on.
- Keep a name that this machine has already (see step 5).

Find the name of the login in use, and ask the user when it can be more than one name. A Pro or Max
login is not part of this setup: tell the user that the first swap replaces it without a copy.

### 5. Look before you write

```bash
ls -la ~ | grep -E 'claude_(teams|ent)'; ls -la ~/.claude_accounts
```

- Saved logins in `~/.claude_accounts/*.json` stay. The script reads them.
- A `~/claude_<name>` file that contains `Swap the Claude Code login` is an older copy of this
  script. Step 6 replaces it with a link.
- On Windows, a `~/claude_<name>.cmd` file that runs `claude_swap.py` is from this setup. Step 6
  replaces it.
- Any other file with one of the names: stop and ask the user.

### 6. Install

```bash
mkdir -p -m 700 ~/.claude_accounts
awk '/^```python$/{f=1; next} f && /^```$/{exit} f' FILE > ~/.claude_accounts/claude_swap.py
chmod 700 ~/.claude_accounts/claude_swap.py
sha256sum ~/.claude_accounts/claude_swap.py 2>/dev/null || shasum -a 256 ~/.claude_accounts/claude_swap.py
```

The sum must be `1ac7e9b536a2ed22cfd5435f4f09303fcd65bdff158ae944d1256ef9c05d1695`. Stop when it is not. Do not retype the script.

Make the commands, and add the warning at session start. Give the names from step 4 without
`claude_`, here `teams` and `ent`. On Linux and macOS each name is a link to the script, and on
Windows a `.cmd` file. The SessionStart hook goes into `~/.claude/settings.json`. All other settings
stay, and nothing changes when the hook is there already:

```bash
PY - teams ent <<'EOF'
import json, os, sys, tempfile
script = os.path.normpath(os.path.expanduser('~/.claude_accounts/claude_swap.py'))
for name in sys.argv[1:]:
  link = os.path.expanduser(f'~/claude_{name}')
  if sys.platform == 'win32':
    # runs the script with its own name; PowerShell finds it as ~/claude_<name>
    exe = sys.executable.replace('%', '%%')
    with open(link + '.cmd', 'w', encoding='oem') as f:
      f.write(f'@"{exe}" "%USERPROFILE%\\.claude_accounts\\claude_swap.py" %~n0 %*\n')
  else:
    if os.path.lexists(link):
      os.remove(link)
    os.symlink(script, link)
if sys.platform == 'win32':
  # Claude Code starts Python itself, with no shell
  hook = {'type': 'command', 'command': sys.executable, 'args': [script, '--check'], 'timeout': 10}
else:
  hook = {'type': 'command', 'command': script + ' --check', 'timeout': 10}
path = os.path.realpath(os.path.expanduser('~/.claude/settings.json'))
data = json.load(open(path, encoding='utf-8-sig')) if os.path.exists(path) else {}
before = json.dumps(data)
starts = data.setdefault('hooks', {}).setdefault('SessionStart', [])
# the hook of an earlier run, also when it names another Python
mine = [h for e in starts for h in e.get('hooks', [])
        if h.get('args', h.get('command')) == hook.get('args', hook['command'])]
for h in mine:
  h.update(hook)
if not mine:
  starts.append({'matcher': 'startup', 'hooks': [hook]})
if json.dumps(data) != before:
  fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
  with os.fdopen(fd, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2)
  os.replace(tmp, path)
print(json.dumps(data['hooks']['SessionStart'], indent=2))
EOF
```

### 7. Save the login in use

Skip this step when no one is logged in. Else run the name of the login in use, for example
`~/claude_teams`, or `~/claude_teams.cmd` in Git Bash on Windows. It must print
`Already on the ... login: <email> (<organization>)`. This saves the login with no browser login.

### 8. Log in to the other accounts

The user runs each other name in their own terminal, one at a time, for example `~/claude_ent`.
Claude cannot run this step, as the login needs the user at a browser and a terminal. Tell the user:

- Sign in with that account. When the browser does not open, open the link that the terminal shows.
  When the browser shows a code, paste it into the terminal.
- Add `--sso` for single sign-on, or `--email <address>` to fill in the email.
- After the login, all sessions use that account, this one too.

After each login, run that name yourself. It must print `Already on the ... login` with the email and
the organization of that account.

### 9. Check and report

```bash
ls -la ~ | grep -E 'claude_(teams|ent)'; ls -la ~/.claude_accounts
PY ~/.claude_accounts/claude_swap.py --check; echo "exit $?"
```

- Each name is a link to `~/.claude_accounts/claude_swap.py`, or on Windows a `.cmd` file.
- The folder is `drwx------`, and each saved login is `-rw-------`. Skip this on Windows, where the
  home folder is private to the user.
- The check prints nothing or one line of JSON, and `exit 0`.

Run the name from step 7 again, if there was one, so the user ends on the login they started with.
Report each name, its account, and the end date of its login (that run lists them), and show the
"Use" table from the top of this file. Remove `/tmp/claude_accounts.md` if you downloaded it.

### PowerShell commands

On Windows these replace the bash blocks of the steps above. PY is `py -3`, or `python` when there
is no `py`. FILE is `$env:TEMP\claude_accounts.md`.

Step 1:

```powershell
$env:CLAUDE_EFFORT
```

Step 2, with `curl.exe`, as `curl` in Windows PowerShell is a different command:

```powershell
curl.exe -fsSL https://raw.githubusercontent.com/mariadb-corporation/mariadb-qa/master/claude_accounts.md -o "$env:TEMP\claude_accounts.md"
```

Step 3:

```powershell
$env:CLAUDE_CONFIG_DIR                                   # nothing
PY -c 'import sys; print(sys.version_info >= (3, 9))'   # True
claude auth status                                       # "loggedIn": false, or "authMethod": "claude.ai"
(Get-ChildItem env:).Name -match '^(ANTHROPIC_API_KEY|ANTHROPIC_AUTH_TOKEN|CLAUDE_CODE_OAUTH_TOKEN|CLAUDE_CODE_USE_(BEDROCK|VERTEX|FOUNDRY))$'   # nothing
```

Step 5:

```powershell
Get-ChildItem -Force $env:USERPROFILE | Where-Object Name -Match 'claude_(teams|ent)'
Get-ChildItem -Force "$env:USERPROFILE\.claude_accounts"
```

Step 6. This writes the script and prints its sum, which must be the sum given in step 6:

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.claude_accounts" | Out-Null
@'
import hashlib, os, sys
md = open(sys.argv[1], encoding='utf-8', newline='').read()
code = md.split('\n```python\n', 1)[1].split('\n```\n', 1)[0] + '\n'
with open(os.path.expanduser('~/.claude_accounts/claude_swap.py'), 'w', encoding='utf-8', newline='') as f:
  f.write(code)
print(hashlib.sha256(code.encode()).hexdigest())
'@ | PY - "$env:TEMP\claude_accounts.md"
```

Then run the Python code of step 6 in the same way: a line `@'`, then the code, then the line
`'@ | PY - teams ent` with the names from step 4.

Steps 7 and 8, to run a name:

```powershell
& "$env:USERPROFILE\claude_teams.cmd"
```

Step 9:

```powershell
Get-ChildItem -Force $env:USERPROFILE | Where-Object Name -Match 'claude_(teams|ent)'
Get-ChildItem -Force "$env:USERPROFILE\.claude_accounts"
PY "$env:USERPROFILE\.claude_accounts\claude_swap.py" --check; "exit $LASTEXITCODE"
Remove-Item "$env:TEMP\claude_accounts.md"
```

## For Claude: how it works

Use these facts when something goes wrong.

- Claude Code keeps the login under the key `claudeAiOauth`: on Linux and Windows in
  `~/.claude/.credentials.json`, on macOS in the Keychain. The account details are in
  `~/.claude.json` (key `oauthAccount`), or in `~/.claude/.config.json` when an old install left
  one. A swap changes only these two keys. Settings, memory, skills, MCP logins and chats stay
  shared.
- On macOS the login is in the login Keychain: item `Claude Code-credentials`, account `$USER`.
  `~/.claude/.credentials.json` is only a fallback for when the Keychain refuses a write, such as a
  locked Keychain over SSH. The script reads and writes that item with the `security` tool, the
  same way that Claude Code does. After a swap it removes a leftover fallback file, as that file
  would hide the change from running sessions.
- On Windows, Claude Code keeps the login in Windows Credential Manager instead when its setting
  `tengu_windows_credman` is on (under `cachedGrowthBookFeatures` in `~/.claude.json`), or when
  `CLAUDE_CODE_FORCE_WINDOWS_CREDMAN=1` is set. The entry is
  `Claude Code-credentials/claude-code-user`, and the file is a fallback, as on macOS. A login over
  2400 bytes is split into base64 parts: `claude-code-user#0`, `#1` and so on, listed in `#m`. The
  script reads and writes these entries the way Claude Code does.
- A login made with `CLAUDE_CONFIG_DIR` set goes to a Keychain item or Credential Manager entry
  named after that folder: `Claude Code-credentials-` and the first 8 hex digits of the sha256 of
  the folder path. After a browser login, the script takes the new login from there and removes it.
- On Windows each name is a `.cmd` file in the home folder that runs the script with its own name.
  PowerShell runs `~/claude_teams` as `claude_teams.cmd`, but a file named `claude_teams` with no
  `.cmd` would win. The hook starts Python with no shell (exec form, with `args`). The `.cmd` files
  and the hook name the Python that ran the setup, so run the setup again when that Python is
  removed.
- Each file write is a new file that is renamed into place, so a session never reads half a file.
- Running sessions read the login again when it changes. They use the new account from their next
  request, with no restart. On macOS, and on Windows with Credential Manager, this can take up to
  30 seconds, as Claude Code keeps a read of the store for that long. `/status` shows the new
  account at once.
- A running session does not undo the change that the script makes to `~/.claude.json`.
- The script finds the account in use from `oauthAccount`: the account ID and the organization ID.
  One person can have accounts in several organizations, with the same email.
- Claude Code renews the access token every few hours, and it replaces the refresh token when it
  does. So an old copy of the login in use can stop working. That is why the script saves the login
  in use again before each swap. Do not copy login files by hand.
- Each login has a fixed end date (`refreshTokenExpiresAt`). A token renewal does not move it. After
  that date, a browser login is needed.
- Claude Code warns at startup when the login in use ends within 3 days: "Your login expires in 3
  days · run /login to renew". The hook gives the same warning for the saved logins that are not in
  use.
- The browser login runs `claude auth login` with `CLAUDE_CONFIG_DIR` set to a scratch folder. The
  login in use changes only after the new login passed its checks.
- A new login is saved only when its plan fits the name (the Team plan for `teams` names, the
  Enterprise plan for `ent` names), and when it is not saved under another name already. Else
  nothing changes.
- After a swap, the script removes the usage numbers that the mariadb-qa status line keeps in
  `/tmp`, as they belong to the old account.
- A request that fails with "Login expired · Please run /login" means that the login in use ended.
  Run its name with `--login`.
- When the warning never shows at session start, look at `/hooks`.

## The script

```python
#!/usr/bin/env python3
# Created by Roel Van de Paar, MariaDB
# Swap the Claude Code login between Team and Enterprise accounts, for all sessions at once.
# Usage:
#   ~/claude_teams          use the Team login, or stay on it
#   ~/claude_teams2         use a second Team login; any number works, for ent too
#   ~/claude_ent            use the Enterprise login, or stay on it
#   ~/claude_ent --login    log in again now, for example when the saved login ends soon
#   ~/claude_ent --sso      other options go to the browser login, when one is needed
#   claude_swap.py --check  warn about a saved login that ends within 3 days (for a hook)
# All names are links to this one script, or on Windows .cmd files that run it; the name picks
# the account. Each login is saved in ~/.claude_accounts, so a swap needs no new login. A browser
# login is needed only the first time an account is used, and when its saved login has run out.
# Running sessions follow the swap, as Claude Code reads its login again when it changes. All
# other settings stay shared

import base64
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unicodedata

HOME = os.path.expanduser('~')
CREDS = f'{HOME}/.claude/.credentials.json'
# the global config; Claude Code uses ~/.claude/.config.json instead when an old install left one
LEGACY = f'{HOME}/.claude/.config.json'
STATE = LEGACY if os.path.isfile(LEGACY) and os.path.getsize(LEGACY) > 0 else f'{HOME}/.claude.json'
STORE = f'{HOME}/.claude_accounts'
PLANS = {'teams': ('team', 'Teams', 'a Team'), 'ent': ('enterprise', 'Enterprise', 'an Enterprise')}
SOON = 3 * 86400
MAC = sys.platform == 'darwin'
WIN = sys.platform == 'win32'
# usage numbers a status line may keep across sessions; after a swap they are the old account's
STATUS = [] if WIN else [f'/tmp/.claude_limits_teams.{os.getuid()}.json',
                         f'/tmp/.claude_usage_teams.{os.getuid()}.json',
                         f'/tmp/.claude_usage_teams.{os.getuid()}.json.pending']
NAME = re.compile(r'(teams|ent)(\d*)')
# macOS keeps the login in the Keychain, and Windows can keep it in Credential Manager, under the
# names that Claude Code uses
ITEM = 'Claude Code-credentials'
ACCOUNT = 'claude-code-user'
if MAC:
  import pwd
  try:
    USER = os.environ.get('USER') or pwd.getpwuid(os.getuid()).pw_name
  except KeyError:
    USER = ''
  ACCOUNT = USER if re.fullmatch(r'[a-zA-Z0-9._-]+', USER) else ACCOUNT


def load(path):
  try:
    with open(path, encoding='utf-8') as f:
      return json.load(f)
  except (OSError, ValueError):
    return None


def save(path, data):
  # a new file renamed into place, so a session never reads half a file
  fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
  with os.fdopen(fd, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2)
  os.replace(tmp, path)


if MAC:
  def secure(item):
    r = subprocess.run(['security', 'find-generic-password', '-a', ACCOUNT, '-w', '-s', item],
                       capture_output=True, text=True)
    try:
      return json.loads(r.stdout) if r.returncode == 0 and r.stdout.strip() else None
    except ValueError:
      return None

  def secure_save(item, data):
    # as Claude Code does it: hex on the stdin of security, so the login is not on a command line
    hexed = json.dumps(data, separators=(',', ':')).encode().hex()
    line = f'add-generic-password -U -a "{ACCOUNT}" -s "{item}" -X "{hexed}"\n'
    if len(line) <= 4032:
      r = subprocess.run(['security', '-i'], input=line, capture_output=True, text=True)
    else:
      r = subprocess.run(['security', 'add-generic-password', '-U', '-a', ACCOUNT, '-s', item, '-X', hexed],
                         capture_output=True, text=True)
    return r.returncode == 0

  def secure_delete(item):
    subprocess.run(['security', 'delete-generic-password', '-a', ACCOUNT, '-s', item], capture_output=True)

if WIN:
  import ctypes
  from ctypes import wintypes

  class CREDENTIAL(ctypes.Structure):
    _fields_ = [('Flags', wintypes.DWORD), ('Type', wintypes.DWORD), ('TargetName', wintypes.LPWSTR),
                ('Comment', wintypes.LPWSTR), ('LastWritten', wintypes.FILETIME),
                ('CredentialBlobSize', wintypes.DWORD), ('CredentialBlob', ctypes.POINTER(ctypes.c_char)),
                ('Persist', wintypes.DWORD), ('AttributeCount', wintypes.DWORD),
                ('Attributes', ctypes.c_void_p), ('TargetAlias', wintypes.LPWSTR),
                ('UserName', wintypes.LPWSTR)]

  ADVAPI = ctypes.WinDLL('advapi32', use_last_error=True)
  ADVAPI.CredReadW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD,
                               ctypes.POINTER(ctypes.POINTER(CREDENTIAL))]
  ADVAPI.CredWriteW.argtypes = [ctypes.POINTER(CREDENTIAL), wintypes.DWORD]
  ADVAPI.CredDeleteW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD]
  ADVAPI.CredFree.argtypes = [ctypes.c_void_p]
  # print in UTF-8, as the code page of a pipe can lack letters of a name
  sys.stdout.reconfigure(encoding='utf-8')
  sys.stderr.reconfigure(encoding='utf-8')
  # Claude Code splits a value over 2400 bytes into base64 parts #0, #1, ..., listed in #m
  CHUNK = 2400

  def cred_get(service, name):
    # one entry as Claude Code keeps it: target "<service>/<name>", the value in UTF-8
    p = ctypes.POINTER(CREDENTIAL)()
    if not ADVAPI.CredReadW(f'{service}/{name}', 1, 0, ctypes.byref(p)):
      return None
    try:
      return ctypes.string_at(p.contents.CredentialBlob, p.contents.CredentialBlobSize).decode()
    finally:
      ADVAPI.CredFree(p)

  def cred_set(service, name, value):
    blob = value.encode()
    buf = ctypes.create_string_buffer(blob, len(blob))
    cred = CREDENTIAL(Type=1, TargetName=f'{service}/{name}', UserName=name, Persist=3)
    cred.CredentialBlobSize = len(blob)
    cred.CredentialBlob = ctypes.cast(buf, ctypes.POINTER(ctypes.c_char))
    if not ADVAPI.CredWriteW(ctypes.byref(cred), 0):
      raise OSError(ctypes.get_last_error(), 'Credential Manager refused the write')

  def cred_del(service, name):
    ADVAPI.CredDeleteW(f'{service}/{name}', 1, 0)

  def parts(service):
    try:
      m = json.loads(cred_get(service, f'{ACCOUNT}#m') or 'null')
      n, size = m['n'], m['l']
    except (ValueError, TypeError, KeyError):
      return None
    valid = type(n) is int and type(size) is int and 0 < n <= 256 and 0 < size <= n * CHUNK
    return (n, size) if valid else None

  def secure(item):
    try:
      split = parts(item)
      if split:
        coded = [cred_get(item, f'{ACCOUNT}#{i}') for i in range(split[0])]
        if None in coded or len(''.join(coded)) != split[1]:
          return None
        text = base64.b64decode(''.join(coded)).decode()
      else:
        text = cred_get(item, ACCOUNT)
      return json.loads(text) if text else None
    except ValueError:
      return None

  def secure_save(item, data):
    # in the same order as Claude Code, so a write that stops halfway can be cleaned up
    text = json.dumps(data, separators=(',', ':'))
    old = (parts(item) or (0, 0))[0]
    try:
      if len(text.encode()) <= CHUNK:
        cred_set(item, ACCOUNT, text)
        if old:
          cred_set(item, f'{ACCOUNT}#p', str(old))
          for part in ['m', *range(old), 'p']:
            cred_del(item, f'{ACCOUNT}#{part}')
        return True
      coded = base64.b64encode(text.encode()).decode()
      count = -(-len(coded) // CHUNK)
      if count > 256:
        return False
      cred_set(item, f'{ACCOUNT}#p', str(max(old, count)))
      for i in range(count):
        cred_set(item, f'{ACCOUNT}#{i}', coded[i * CHUNK:(i + 1) * CHUNK])
      cred_set(item, f'{ACCOUNT}#m', json.dumps({'n': count, 'l': len(coded)}, separators=(',', ':')))
      cred_del(item, ACCOUNT)
      for part in [*range(count, old), 'p']:
        cred_del(item, f'{ACCOUNT}#{part}')
      return True
    except OSError:
      return False

  def secure_delete(item):
    count = (parts(item) or (0, 0))[0]
    for part in ['', '#m', '#p', *[f'#{i}' for i in range(count)]]:
      cred_del(item, ACCOUNT + part)


def secure_on(state):
  # Windows uses Credential Manager only when Claude Code has it switched on
  if WIN:
    flags = (state or {}).get('cachedGrowthBookFeatures') or {}
    return (os.environ.get('CLAUDE_CODE_FORCE_WINDOWS_CREDMAN') == '1'
            or flags.get('tengu_windows_credman') is True)
  return MAC


def read_creds():
  # Claude Code reads the secure store first, and the file when the store has no login
  data = secure(ITEM) if SECURE else None
  return data if data is not None else load(CREDS) or {}


def write_creds(data):
  # where Claude Code reads it: the secure store when in use, else the file
  if SECURE and secure_save(ITEM, data):
    if os.path.exists(CREDS):
      # an old fallback file would hide the change from running sessions
      os.remove(CREDS)
    return
  if SECURE and secure(ITEM) is not None:
    where = 'the macOS Keychain' if MAC else 'Windows Credential Manager'
    sys.exit(f'Could not write the login to {where}. Nothing changed, please try again')
  save(CREDS, data)


def label(name):
  kind, num = NAME.fullmatch(name).groups()
  return f'{PLANS[kind][1]} {num}'.strip()


def plan(login):
  return ((login or {}).get('claudeAiOauth') or {}).get('subscriptionType')


def who(login):
  # the account and the organization; one person can be in several organizations
  acct = (login or {}).get('oauthAccount') or {}
  return (acct['accountUuid'], acct.get('organizationUuid')) if acct.get('accountUuid') else None


def ends(login):
  ms = ((login or {}).get('claudeAiOauth') or {}).get('refreshTokenExpiresAt')
  return ms / 1000 if ms else None


def owner(login, saved):
  # the name a login is saved under: same account, same organization, same plan
  for name, other in saved.items():
    if who(login) and who(other) == who(login) and plan(other) == plan(login):
      return name
  return None


def browser_login(want, saved):
  # in a scratch folder, so the login in use is not touched
  tmp = tempfile.mkdtemp()
  try:
    subprocess.run([shutil.which('claude') or 'claude', 'auth', 'login'] + EXTRA,
                   env=dict(os.environ, CLAUDE_CONFIG_DIR=tmp))
    found = load(f'{tmp}/.credentials.json')
    if MAC or WIN:
      # the new login can be in a secure store entry named after the scratch folder; take it and
      # remove the entry
      item = f"{ITEM}-{hashlib.sha256(unicodedata.normalize('NFC', tmp).encode()).hexdigest()[:8]}"
      found = secure(item) or found
      secure_delete(item)
    new = {'claudeAiOauth': (found or {}).get('claudeAiOauth'),
           'oauthAccount': (load(f'{tmp}/.claude.json') or {}).get('oauthAccount')}
  finally:
    shutil.rmtree(tmp)
  kind = NAME.fullmatch(want).group(1)
  if plan(new) != PLANS[kind][0] or not who(new):
    sys.exit(f'No {label(want)} login was saved: the login did not finish, or was not for '
             f'{PLANS[kind][2]} account. Nothing changed')
  other = owner(new, {k: v for k, v in saved.items() if k != want})
  if other:
    sys.exit(f'That login is the {label(other)} account, so it was not saved as {label(want)}. '
             'Nothing changed')
  save(f'{STORE}/{want}.json', new)
  return new


def notes(saved, now, live):
  # one line per saved login: when it ends, and what to do when that is soon or past
  out = []
  for name in sorted(saved, key=lambda n: (NAME.fullmatch(n).group(1), int(NAME.fullmatch(n).group(2) or 0))):
    end = ends(live) if name == now else ends(saved[name])
    if not end:
      continue
    when = time.strftime('%a %d %b %H:%M', time.localtime(end))
    if end < time.time():
      out.append((True, f'{label(name)} login ended {when} - the next ~/claude_{name} asks for a new login'))
    elif end < time.time() + SOON:
      out.append((True, f'{label(name)} login ends {when} - run ~/claude_{name} --login to renew it'))
    else:
      out.append((False, f'{label(name)} login until {when}'))
  return out


saved = {n[:-5]: load(f'{STORE}/{n}') for n in (os.listdir(STORE) if os.path.isdir(STORE) else [])
         if n.endswith('.json') and NAME.fullmatch(n[:-5])}
state = load(STATE)
SECURE = secure_on(state)
creds = read_creds()
live = {'claudeAiOauth': creds.get('claudeAiOauth'), 'oauthAccount': (state or {}).get('oauthAccount')}
now = owner(live, saved) if live['claudeAiOauth'] else None

if sys.argv[1:] == ['--check']:
  # for a SessionStart hook: print nothing, or one warning for the user. The login in use is
  # left out, as Claude Code warns about that one itself
  warn = [text for soon, text in notes({k: v for k, v in saved.items() if k != now}, now, live) if soon]
  if warn:
    print(json.dumps({'systemMessage': 'Claude logins: ' + '. '.join(warn)}))
  sys.exit(0)

args = sys.argv[1:]
m = NAME.fullmatch(os.path.basename(sys.argv[0]).removeprefix('claude_'))
if not m and args and NAME.fullmatch(args[0].removeprefix('claude_')):
  # a .cmd file on Windows passes its own name first
  m = NAME.fullmatch(args.pop(0).removeprefix('claude_'))
if not m:
  sys.exit('Run this as ~/claude_teams, ~/claude_teams2 (any number), ~/claude_ent or ~/claude_ent2')
WANT = m.group(0)
FORCE = '--login' in args
EXTRA = [a for a in args if a != '--login']
if state is None:
  sys.exit(f'Could not read {STATE}. Nothing changed, please try again')
os.makedirs(STORE, mode=0o700, exist_ok=True)
if (now is None and live['claudeAiOauth'] and WANT not in saved and who(live)
    and plan(live) == PLANS[m.group(1)][0] and not any(who(s) == who(live) for s in saved.values())):
  # the first run for the account in use: keep its login under this name
  now = WANT
if now:
  # keep the newest copy of the login in use, as Claude Code renews its tokens now and then
  saved[now] = live
  save(f'{STORE}/{now}.json', live)
if now != WANT or FORCE:
  if now is None and live['claudeAiOauth']:
    acct = live['oauthAccount'] or {}
    print(f"The login in use ({acct.get('emailAddress', 'unknown account')}) is not saved under a name, "
          f"so no copy of it is kept")
  new = saved.get(WANT)
  end = ends(new)
  if FORCE or not plan(new) or (end and end < time.time()):
    new = browser_login(WANT, saved)
    saved[WANT] = new
  # only the account login is swapped; other logins in the file, such as MCP servers, stay
  creds = read_creds()
  creds['claudeAiOauth'] = new['claudeAiOauth']
  write_creds(creds)
  state = load(STATE) or state
  if new.get('oauthAccount'):
    state['oauthAccount'] = new['oauthAccount']
  else:
    state.pop('oauthAccount', None)
  save(STATE, state)
  for path in STATUS:
    if os.path.exists(path):
      os.remove(path)
  live = new
acct = live['oauthAccount'] or {}
print(f"{'Already on' if now == WANT and not FORCE else 'Swapped to'} the {label(WANT)} login: "
      f"{acct.get('emailAddress')} ({acct.get('organizationName')})")
for soon, text in notes(saved, WANT, live):
  print(('! ' if soon else '  ') + text)
```

<!-- After a change to the script, update its sha256 in step 6 -->
