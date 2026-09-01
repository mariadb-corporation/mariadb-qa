# Rename this Claude session and the screen it runs in. Pass the new name.
import json, os, subprocess, sys, tempfile


def up(pid):
  # the parent of a process, 0 when it has none
  try:
    out = subprocess.run(['ps', '-o', 'ppid=', '-p', str(pid)], capture_output=True, text=True).stdout
    return int(out.strip())
  except (ValueError, OSError):
    return 0


def comm(pid):
  try:
    with open(f'/proc/{pid}/comm') as f:
      return f.read().strip()
  except OSError:
    return ''


def find(names, start):
  # the nearest process above this one whose name is in names, None when there is none
  p = start
  for _ in range(10):
    if p <= 1:
      return None
    if comm(p) in names:
      return p
    p = up(p)
  return None


def rename_session(name):
  pid = find({'claude'}, os.getppid())
  if pid is None:
    return 'no claude process above this one, so the session keeps its name'
  path = f'{os.path.expanduser("~")}/.claude/sessions/{pid}.json'
  try:
    with open(path) as f:
      rec = json.load(f)
  except (OSError, ValueError) as e:
    return f'{path} unreadable ({e}), so the session keeps its name'
  was = rec.get('name') or '-'
  rec['name'], rec['nameSource'] = name, 'user'
  fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
  with os.fdopen(fd, 'w') as f:
    json.dump(rec, f, separators=(',', ':'))
  os.chmod(tmp, os.stat(path).st_mode & 0o7777)  # mkstemp makes a 0600 file, the record is not
  os.replace(tmp, path)
  return f'session {was} -> {name}'


def rename_screen(name):
  pid = find({'screen', 'SCREEN'}, os.getppid())
  if pid is None:
    return 'not running in a screen, so nothing to rename there'
  out = subprocess.run([f'{os.path.expanduser("~")}/sren', str(pid), name], capture_output=True, text=True)
  return (out.stdout + out.stderr).strip()


if len(sys.argv) != 2 or not sys.argv[1]:
  print('Assert: pass the new name. No action was taken.')
  sys.exit(1)
print(rename_session(sys.argv[1]))
print(rename_screen(sys.argv[1]))
