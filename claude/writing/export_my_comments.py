#!/usr/bin/env python3
"""Write your own Jira comments to a text file, newest first.

The token comes from JIRA_PAT, else from the file JIRA_PAT_FILE names
(default ~/.config/mariadb-qa/jira.pat). JIRA_URL names the server
(default https://jira.mariadb.org). Standard library only.

Code, noformat and quote blocks are replaced by a short marker unless
--keep-blocks is given, so the file holds prose.
"""

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

DEFAULT_URL = "https://jira.mariadb.org"
DEFAULT_PAT_FILE = "~/.config/mariadb-qa/jira.pat"
DEFAULT_JQL = (
  "(reporter = currentUser() OR assignee = currentUser() OR "
  "watcher = currentUser() OR creator = currentUser()) ORDER BY updated DESC"
)
PAGE = 50
BLOCK_RE = re.compile(r"\{(code|noformat|quote)(?::[^}]*)?\}.*?\{\1\}", re.S)


def load_pat():
  pat = os.environ.get("JIRA_PAT", "").strip()
  if pat:
    return pat
  path = os.path.expanduser(os.environ.get("JIRA_PAT_FILE", DEFAULT_PAT_FILE))
  try:
    with open(path, encoding="utf-8") as fh:
      return fh.read().strip()
  except OSError:
    return ""


def get(url, pat, params=None):
  if params:
    url = url + "?" + urllib.parse.urlencode(params)
  req = urllib.request.Request(url, headers={
    "Authorization": "Bearer " + pat,
    "Accept": "application/json",
  })
  try:
    with urllib.request.urlopen(req, timeout=60) as resp:
      return json.load(resp)
  except urllib.error.HTTPError as err:
    body = err.read().decode("utf-8", "replace")[:300]
    if err.code == 401:
      sys.exit("Jira rejected the token (HTTP 401). Check JIRA_PAT or the token file.")
    sys.exit("Jira returned HTTP %d for %s\n%s" % (err.code, url, body))
  except urllib.error.URLError as err:
    sys.exit("Cannot reach %s: %s" % (url, err.reason))


def strip_blocks(text):
  def marker(match):
    return "[%s block removed]" % match.group(1)
  return BLOCK_RE.sub(marker, text)


def all_comments(base, pat, issue):
  field = issue.get("fields", {}).get("comment") or {}
  comments = list(field.get("comments") or [])
  total = field.get("total", len(comments))
  start = len(comments)
  while start < total:
    page = get(base + "/rest/api/2/issue/%s/comment" % issue["key"], pat,
               {"startAt": start, "maxResults": 100})
    got = page.get("comments") or []
    if not got:
      break
    comments.extend(got)
    start += len(got)
  return comments


def main():
  ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
  ap.add_argument("--out", default="my_jira_comments.txt", help="output file")
  ap.add_argument("--max", type=int, default=200, help="comments to keep, newest first")
  ap.add_argument("--max-issues", type=int, default=800, help="issues to scan at most")
  ap.add_argument("--jql", default=DEFAULT_JQL, help="issue search; comments are filtered to yours")
  ap.add_argument("--keep-blocks", action="store_true", help="keep code, noformat and quote blocks")
  ap.add_argument("--holdout", default="", help="write four evenly spaced comments to this file and leave them out of --out")
  ap.add_argument("--url", default=os.environ.get("JIRA_URL", DEFAULT_URL), help="Jira base URL")
  args = ap.parse_args()

  base = args.url.rstrip("/")
  pat = load_pat()
  if not pat:
    sys.exit(
      "No token. Set JIRA_PAT, or store a Personal Access Token in %s (mode 600).\n"
      "Create one in Jira: your profile, then Personal Access Tokens, then Create token."
      % os.path.expanduser(os.environ.get("JIRA_PAT_FILE", DEFAULT_PAT_FILE)))

  me = get(base + "/rest/api/2/myself", pat)
  me_ids = {me.get("name"), me.get("key")} - {None}

  found = []
  scanned = 0
  start = 0
  while scanned < args.max_issues and len(found) < args.max:
    page = get(base + "/rest/api/2/search", pat, {
      "jql": args.jql, "startAt": start, "maxResults": PAGE,
      "fields": "comment,summary",
    })
    issues = page.get("issues") or []
    if not issues:
      break
    for issue in issues:
      scanned += 1
      for c in all_comments(base, pat, issue):
        author = c.get("author") or {}
        if author.get("name") in me_ids or author.get("key") in me_ids:
          body = (c.get("body") or "").replace("\r\n", "\n").strip()
          if not args.keep_blocks:
            body = strip_blocks(body)
          if body:
            found.append((c.get("created", ""), issue["key"], body))
      if scanned >= args.max_issues:
        break
    start += len(issues)
    if start >= page.get("total", 0):
      break

  found.sort(key=lambda t: t[0], reverse=True)
  found = found[:args.max]

  holdout = []
  if args.holdout and len(found) >= 8:
    n = len(found)
    picks = {n // 8, 3 * n // 8, 5 * n // 8, 7 * n // 8}
    holdout = [c for i, c in enumerate(found) if i in picks]
    found = [c for i, c in enumerate(found) if i not in picks]

  def write(path, comments):
    with open(path, "w", encoding="utf-8") as out:
      for created, key, body in comments:
        out.write("=== %s  %s ===\n%s\n\n" % (key, created[:10], body))

  write(args.out, found)
  if holdout:
    write(args.holdout, holdout)
    print("held out: %d comments  file: %s" % (len(holdout), args.holdout), file=sys.stderr)

  print("user: %s  issues scanned: %d  comments written: %d  file: %s"
        % (me.get("displayName") or me.get("name"), scanned, len(found), args.out),
        file=sys.stderr)
  if len(found) < 50 and len(found) < args.max:
    print("fewer than 50 comments: the voice profile will come out generic. "
          "Raise --max-issues, widen --jql, or add other prose of yours to the file by hand.",
          file=sys.stderr)


if __name__ == "__main__":
  main()
