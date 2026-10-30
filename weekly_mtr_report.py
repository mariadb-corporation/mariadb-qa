#!/usr/bin/env python3
"""weekly_mtr_report.py - weekly MTR failure report for the MariaDB buildbot, meant to run from cron.

It does the same job as the cloud routine "Weekly MTR failure report (galera)", without an AI step,
so it needs no Claude login and no token:
  1. Runs build_mtr_test_failures_report.py for the suite groups (--suite-groups, comma separated) over the
     7 UTC days before today. Every job has a label (--label); the run date (UTC) names the report folder
     REPORT_ROOT/<label>/<run date>/.
  2. For every ranked test (top_fail_tests_all_suites + not_merged_to_all_yet) it works out the failures
     per release branch, the last commit per branch, the top builders, the dominant failure text and a
     builder verdict (every failure on one builder = likely builder/environment problem).
  3. Looks every test up on jira.mariadb.org (anonymous, read-only, exact-phrase JQL; a test named after
     its own MDEV is fetched by key) and sorts it into "needs a bug", "fixed in Jira but still failing",
     "known, open MDEV" or "only closed tickets". A ticket whose title names the test is the link only when
     its text holds the failure line; a namesake about another failure is listed as "only mentioned". When
     the failures follow a rarely mentioned builder platform (all on Fedora 45 and Ubuntu 26.10 builders) the
     platform is looked up too, for a ticket fixed shortly before the failures began that still fails on its
     fix branches. For such a fixed ticket GitHub says which release branches have the fix ("Fixed only in 11.8
     and below"): Jira's Fix Version/s are filled in for every branch the fix is meant for, merged or not.
     GitHub gives anonymous clients 60 requests an hour; set GITHUB_TOKEN (or GH_TOKEN) in the crontab to lift it.
  4. Writes report.md and report.html, and the rows of every failing run (gzipped), to the run folder. The
     report opens with a "Single-slide summary": the top SLIDE_TESTS tests as plain lines to paste onto a slide.
  5. Emails RECIPIENT the report: report.html is the HTML body of the email and the plain-text part holds the
     report location and a short headline. When a step failed a failure notice is sent instead.
Nothing is written to Jira, GitHub or this repository.

Cron (the system timezone of qa-susil-1 is UTC, so 02:15 is 07:45 IST): galera on Mondays, replication on Fridays
  15 2 * * 1  /usr/bin/python3 /home/susil_behera/mariadb-qa/weekly_mtr_report.py --label galera --suite-groups 'galera.*' >> /home/susil_behera/mtr-weekly-reports/galera/cron.log 2>&1
  15 2 * * 5  /usr/bin/python3 /home/susil_behera/mariadb-qa/weekly_mtr_report.py --label replication --suite-groups 'rpl.*,binlog.*,binlog_encryption.*,multi_source.*' >> /home/susil_behera/mtr-weekly-reports/replication/cron.log 2>&1

Usage: weekly_mtr_report.py [--label NAME] [--suite-groups LIST] [--no-email] [--reuse-dir DIR]
                            [--from-date D] [--until-date D] [--report-root DIR]
  --label         job name, used for the report folder, the lock and the email subject (default galera)
  --suite-groups  comma separated --test-name filters of the pull script (default 'galera.*')
  --no-email      build the report, print the alert instead of sending it
  --reuse-dir     analyse a finished pull in DIR (stdout_1.txt, stderr_1.txt and the rows json) instead of pulling
"""

from __future__ import annotations

import argparse
import fcntl
import gzip
import html
import importlib.util
import json
import re
import shutil
import socket
import subprocess
import sys
import time
import traceback
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

# ---------------------------------------------------------------------------------------------
# User-configurable
# ---------------------------------------------------------------------------------------------
REPORT_ROOT = Path.home() / "mtr-weekly-reports"
# Defaults of --label and --suite-groups; the cron lines pass both explicitly
LABEL = "galera"
SUITE_GROUPS = ["galera.*"]
RECIPIENT = "susil.behera@mariadb.com"
EMAIL_SCRIPT = Path.home() / ".claude" / "skills" / "email" / "send_email.py"
# The galera.* pull took 54 minutes on 2026-10-26 (rows in under a minute, then the per-branch and GitHub lookups);
# the replication job pulls four suites, so allow 4 hours
PULL_TIMEOUT_SECONDS = 240 * 60
WINDOW_DAYS = 7
TOP_BUILDERS = 3
# Tests listed in the single-slide summary at the top of the report
SLIDE_TESTS = 10
JIRA_URL = "https://jira.mariadb.org"
JIRA_SLEEP_SECONDS = 1.0
# A test whose failures sit (nearly) all on a few platforms, e.g. the new Fedora 45 and Ubuntu 26.10 builders, is also
# looked up by platform: PLATFORM_SHARE of its failures must sit on at most PLATFORM_MAX platforms, the ticket must have
# been fixed no more than PLATFORM_FIX_DAYS before the first failure of the test, and no more than PLATFORM_MAX_HITS
# tickets may mention the platform (a phrase like Debian 12 or Ubuntu 22.04 is in hundreds and points at nothing)
PLATFORM_SHARE = 0.9
PLATFORM_MAX = 3
PLATFORM_FIX_DAYS = 60
PLATFORM_MAX_HITS = 10
# GitHub failures (a quota spent counts at once; a fix commit that is simply not there does not count) after which the
# run stops asking which branches have a fix
GIT_MAX_FAILURES = 2

# ---------------------------------------------------------------------------------------------
# Internal, do not change
# ---------------------------------------------------------------------------------------------
REPO = Path(__file__).resolve().parent
PULL_SCRIPT = REPO / "build_mtr_test_failures_report.py"
POOLED_MARKER = "Top failing tests pooled across every suite fetched in this run"
VERSION_REGEX = re.compile(r"^(((10|11|12|13)\.\d+)|main)$")
FIX_VERSION_REGEX = re.compile(r"^(\d+\.\d+)(?:\.\d+)?$")
KEY_IN_NAME_REGEX = re.compile(r"(?i)(?:^|[._])mdev[-_](\d+)")
# Builder names read <arch>-<os>-<version>[-<flavour>]: amd64-fedora-45, aarch64-ubuntu-2610, x86-debian-12-fulltest
BUILDER_PLATFORM_REGEX = re.compile(r"^(?:amd64|aarch64|ppc64le|s390x|x86)-(fedora|ubuntu|debian|rhel|freebsd|centos|almalinux|rocky|opensuse|alpine)-(\d+)\b")
PLATFORM_NAMES = {"rhel": "RHEL", "freebsd": "FreeBSD", "almalinux": "AlmaLinux", "opensuse": "openSUSE"}
JIRA_FIELDS = "summary,status,resolution,resolutiondate,created,fixVersions,issuelinks"
# MTR framing that says nothing about what failed; never used as a search fragment
GENERIC_FRAGMENTS = {
    "result length mismatch",
    "result content mismatch",
    "mysqltest failed but provided no output",
}
WORKER_REGEX = re.compile(r"\bw\d+\b")
TIME_REGEX = re.compile(r"\d{4}-\d\d-\d\d[ T]\d\d:\d\d:\d\d(?:\.\d+)?(?:Z| ?[+-]\d{4})?")
FRAMING_REGEX = re.compile(
    r"^(?:\S+\s+(?:'[^']+'\s+)?wN\s+\[\s*[\w-]+\s*\]|\s*Test ended at|CURRENT_TEST:|--- |\+\+\+ |@@ )"
)
RUN_LOG: Path | None = None
# platform -> (tickets that mention it, those that are Closed/Fixed); the same platform comes up for every test of a
# platform-wide failure, so each question goes to Jira once per run
PLATFORM_TICKETS: dict[str, tuple[int, list[dict]]] = {}
# The pull script as a module (its GitHub helpers), loaded on first use; and why GitHub is not asked any more this run
PULL_MODULE = None
GIT_BLOCKED = ""
GIT_FAILURES = 0


class StepError(Exception):
    """A step of the run failed in a way that deserves a failure notice."""


class JiraError(Exception):
    """A Jira lookup failed (HTTP error, timeout, bad JSON)."""


class GitError(Exception):
    """The branches that have a fix could not be worked out (no fix commit found, no Fix Version/s branch)."""


def log(message: str) -> None:
    line = f"{datetime.now(timezone.utc):%Y-%m-%dT%H:%M:%SZ} {message}"
    print(line, flush=True)
    if RUN_LOG is not None:
        with open(RUN_LOG, "a", encoding="utf-8") as handle:
            handle.write(line + "\n")


def parse_time(text: str) -> datetime:
    """Buildbot rows ('2026-10-19T08:32:44Z') and Jira ('2024-07-26T10:33:12.000+0000') as aware datetimes."""
    text = text.strip()
    for fmt in ("%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%M:%S.%f%z", "%Y-%m-%dT%H:%M:%S%z"):
        try:
            value = datetime.strptime(text, fmt)
        except ValueError:
            continue
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    raise ValueError(f"unparsable time {text!r}")


# ---------------------------------------------------------------------------------------------
# Failure text helpers
# ---------------------------------------------------------------------------------------------
def mask(text: str) -> str:
    """Worker ids and timestamps replaced, so the same failure reads the same on every run."""
    return TIME_REGEX.sub("<time>", WORKER_REGEX.sub("wN", text or ""))


def changed_or_content_lines(text: str) -> list[str]:
    """The changed lines of a result diff; for any other failure the lines that are not MTR framing."""
    lines = [l.rstrip() for l in (text or "").splitlines() if l.strip()]
    changed = [l.strip() for l in lines if l.startswith(("+", "-")) and not l.startswith(("+++", "---"))]
    if changed:
        return changed
    content = [l.strip() for l in lines if not FRAMING_REGEX.match(l)]
    return content or [l.strip() for l in lines[:1]]


def excerpt(text: str, limit: int = 120) -> str:
    joined = " / ".join(changed_or_content_lines(text)[:2])
    joined = re.sub(r"\s+", " ", joined).strip()
    return joined if len(joined) <= limit else joined[: limit - 3] + "..."


def fragment(text: str) -> str | None:
    """A short distinctive line without paths, numbers or timestamps (an error message), else None."""
    for line in changed_or_content_lines(text):
        if line.startswith(("+", "-")):
            continue
        if not 12 <= len(line) <= 90 or line.lower() in GENERIC_FRAGMENTS:
            continue
        if re.fullmatch(r"[A-Za-z _.:'()-]+", line):
            return line
    return None


# ---------------------------------------------------------------------------------------------
# Pull and parse
# ---------------------------------------------------------------------------------------------
def run_pull(run_dir: Path, from_date: str, until_date: str) -> None:
    command = [
        sys.executable, str(PULL_SCRIPT),
        "--test-name", ",".join(SUITE_GROUPS),
        "--from-date", from_date, "--until-date", until_date,
        "--format", "json",
    ]
    log("pull: " + " ".join(command))
    with open(run_dir / "pull_stdout.txt", "w") as out, open(run_dir / "pull_stderr.txt", "w") as err:
        try:
            done = subprocess.run(command, cwd=run_dir, stdout=out, stderr=err, timeout=PULL_TIMEOUT_SECONDS)
        except subprocess.TimeoutExpired:
            raise StepError(f"the report script did not finish within {PULL_TIMEOUT_SECONDS // 60} minutes")
    if done.returncode != 0:
        raise StepError(f"the report script exited with code {done.returncode}")


def parse_pooled(stdout_text: str) -> dict:
    marker = stdout_text.find(POOLED_MARKER)
    if marker < 0:
        raise StepError("the report script output has no pooled summary (the run failed or was cut short)")
    start = stdout_text.find("{", marker)
    if start < 0:
        raise StepError("the pooled summary has no JSON object")
    try:
        pooled, _ = json.JSONDecoder().raw_decode(stdout_text[start:])
    except ValueError as exc:
        raise StepError(f"the pooled summary is not valid JSON: {exc}")
    return pooled


def load_rows(run_dir: Path) -> list[dict]:
    rows: list[dict] = []
    for path in sorted(run_dir.glob("test_failures_*.json")):
        with open(path, encoding="utf-8") as handle:
            rows += json.load(handle)
    return rows


def compress_rows(run_dir: Path) -> list[str]:
    names = []
    for path in sorted(run_dir.glob("test_failures_*.json")):
        target = path.with_name("rows_" + path.name[len("test_failures_"):] + ".gz")
        with open(path, "rb") as src, gzip.open(target, "wb") as dst:
            shutil.copyfileobj(src, dst)
        path.unlink()
        names.append(target.name)
    return names


# ---------------------------------------------------------------------------------------------
# Per-test analysis (no network)
# ---------------------------------------------------------------------------------------------
def builder_platform(name: str) -> str | None:
    """The platform the way a ticket writes it: 'Fedora 45' for amd64-fedora-45, 'Ubuntu 26.10' for aarch64-ubuntu-2610."""
    match = BUILDER_PLATFORM_REGEX.match(name)
    if not match:
        return None
    distro, version = match.groups()
    if distro == "ubuntu" and len(version) == 4:
        version = f"{version[:2]}.{version[2:]}"
    return f"{PLATFORM_NAMES.get(distro, distro.capitalize())} {version}"


def failing_platforms(builders: Counter) -> list[str]:
    """The few platforms that hold PLATFORM_SHARE of the failures; none when they are spread wider or on unnamed builders."""
    total = sum(builders.values())
    per_platform: Counter = Counter()
    for name, count in builders.items():
        per_platform[builder_platform(name)] += count
    chosen, covered = [], 0
    for platform, count in per_platform.most_common(PLATFORM_MAX):
        if platform is None:
            return []
        chosen.append(platform)
        covered += count
        if covered >= PLATFORM_SHARE * total:
            return chosen
    return []


def analyse(entry: dict, rows_by_test: dict[str, list[dict]]) -> dict:
    test = entry["test_name"]
    release = [r for r in rows_by_test.get(test, []) if VERSION_REGEX.match(r["branch"])]
    per_branch = Counter(r["branch"] for r in release)
    last: dict[str, tuple[str, str]] = {}
    for row in sorted(release, key=lambda r: r["dt"]):
        last[row["branch"]] = (row["commit"], row["dt"])
    builders = Counter(r["builder_name"] for r in release)
    busiest = per_branch.most_common(1)[0][0] if per_branch else None
    text = ""
    if busiest:
        records = ((entry.get("branches") or {}).get(busiest) or {}).get("distinct_failure_texts") or []
        if records:
            text = records[0].get("failure_text") or ""
    if not text:
        texts = Counter(r.get("failure_text") or "" for r in release if r.get("failure_text"))
        text = texts.most_common(1)[0][0] if texts else ""
    text = mask(text)
    top = ", ".join(f"{name} ({count})" for name, count in builders.most_common(TOP_BUILDERS))
    if len(builders) == 1:
        verdict = (f"every failure ({sum(builders.values())}) comes from {next(iter(builders))}: "
                   "a likely builder or environment problem, not a code regression")
    elif builders:
        verdict = (f"{len(builders)} builders and {len(per_branch)} branch(es) fail ({top}): "
                   "points at the test or the branch, not at one builder")
    else:
        verdict = "no release-branch rows in the pulled data"
    return {
        "test": test,
        "failures": entry.get("fail_count", len(release)),
        "release_rows": len(release),
        "per_branch": per_branch,
        "last": last,
        "builders": builders,
        "top_builders": top,
        "platforms": failing_platforms(builders),
        "onset": min((parse_time(r["dt"]) for r in release), default=None),
        "text": text,
        "excerpt": excerpt(text),
        "verdict": verdict,
        "entry": entry,
        "not_merged": None,
        "jira": None,
    }


# ---------------------------------------------------------------------------------------------
# Jira (anonymous, read-only)
# ---------------------------------------------------------------------------------------------
def jira_json(path: str, params: dict | None = None) -> dict:
    url = JIRA_URL + path + ("?" + urlencode(params) if params else "")
    request = Request(url, headers={"Accept": "application/json", "User-Agent": "weekly-mtr-report"})
    for attempt in range(3):
        try:
            with urlopen(request, timeout=60) as response:
                return json.load(response)
        except HTTPError as exc:
            if exc.code in (429, 500, 502, 503, 504) and attempt < 2:
                time.sleep(5 * (attempt + 1))
                continue
            raise JiraError(f"HTTP {exc.code} for {path}")
        except (URLError, TimeoutError, ValueError, OSError) as exc:
            if attempt < 2:
                time.sleep(5 * (attempt + 1))
                continue
            raise JiraError(f"{type(exc).__name__} for {path}: {exc}")
    raise JiraError(f"no answer for {path}")


def issue_row(issue: dict) -> dict:
    fields = issue.get("fields") or {}
    links = []
    for link in fields.get("issuelinks") or []:
        direction = "outward" if "outwardIssue" in link else "inward"
        other = link.get(direction + "Issue") or {}
        links.append({"type": (link.get("type") or {}).get("name", ""), "direction": direction, "key": other.get("key", "")})
    return {
        "key": issue["key"],
        "summary": fields.get("summary") or "",
        "status": (fields.get("status") or {}).get("name") or "?",
        "resolution": (fields.get("resolution") or {}).get("name") or "",
        "resolutiondate": fields.get("resolutiondate") or "",
        "created": fields.get("created") or "",
        "fixversions": [v["name"] for v in fields.get("fixVersions") or []],
        "links": links,
        "via": "",
        "dup_of": "",
        "same_failure": None,
    }


def jira_search(term: str) -> list[dict]:
    # The escaped inner quotes make JQL match the exact phrase; without them it ORs the tokens
    jql = 'project = MDEV AND text ~ "\\"%s\\"" ORDER BY created DESC' % term
    data = jira_json("/rest/api/2/search", {"jql": jql, "fields": JIRA_FIELDS, "maxResults": 20})
    return [issue_row(i) for i in data.get("issues", [])]


def jira_issue(key: str, fields: str = JIRA_FIELDS) -> dict:
    return jira_json(f"/rest/api/2/issue/{key}", {"fields": fields})


def follow_duplicates(row: dict) -> dict:
    """A match that was closed as a Duplicate is reported as the ticket it duplicates."""
    for _ in range(3):
        if row["resolution"] != "Duplicate":
            break
        originals = [l["key"] for l in row["links"] if l["type"] == "Duplicate" and l["direction"] == "outward" and l["key"]]
        if not originals:
            break
        time.sleep(JIRA_SLEEP_SECONDS)
        original = issue_row(jira_issue(originals[0]))
        original["dup_of"] = row["key"]
        original["via"] = row["via"]
        row = original
    return row


def after_fix_failures(ticket: dict, release_rows: list[dict]) -> Counter:
    """Failures on a fix-version branch dated after the ticket was resolved (Closed/Fixed tickets only)."""
    if ticket["status"] != "Closed" or ticket["resolution"] != "Fixed" or not ticket["resolutiondate"]:
        return Counter()
    branches = set()
    for version in ticket["fixversions"]:
        match = FIX_VERSION_REGEX.match(version)
        if match and VERSION_REGEX.match(match.group(1)):
            branches.add(match.group(1))
    resolved = parse_time(ticket["resolutiondate"])
    return Counter(r["branch"] for r in release_rows if r["branch"] in branches and parse_time(r["dt"]) > resolved)


def pull_module():
    """The pull script as a module. Its GitHub helpers (token, retries, quota) are the ones its not_merged_to_all_yet
    list is built with, so a fix is looked for the same way in both."""
    global PULL_MODULE
    if PULL_MODULE is None:
        spec = importlib.util.spec_from_file_location("build_mtr_test_failures_report", PULL_SCRIPT)
        module = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = module
        spec.loader.exec_module(module)
        PULL_MODULE = module
    return PULL_MODULE


def branch_order(branch: str) -> tuple[int, int, int]:
    """Release branches oldest first, and main, which everything is merged up into, last."""
    if branch == "main":
        return (1, 0, 0)
    major, minor = branch.split(".")
    return (0, int(major), int(minor))


def fix_scope(merged: list[str], missing: list[str]) -> str:
    """Where a fix is, to read after 'Fixed': 'only in 11.8 and below' when the branches that have it run on from the
    bottom, 'in all branches' when none lacks it. When they do not run on from the bottom (13.0 lacks what 12.3 and 13.1
    have), the shorter of the two lists: 'in all branches except 13.0, main' or 'only in 10.11, 11.8'."""
    if not merged:
        return "in no release branch"
    if not missing:
        return "in all branches"
    top = max(merged, key=branch_order)
    if not any(branch_order(branch) < branch_order(top) for branch in missing):
        return f"only in {top} and below"
    if len(missing) < len(merged):
        return "in all branches except " + ", ".join(sorted(missing, key=branch_order))
    return "only in " + ", ".join(sorted(merged, key=branch_order))


def fix_branches_state(ticket: dict, failing: set[str]) -> dict:
    """Which release branches have the fix of a Closed/Fixed ticket, from GitHub. Jira's Fix Version/s say where the fix is
    meant to go, not where it has got to: they are filled in for every branch when it is pushed. The fix commit is looked
    for as the pull script does for not_merged_to_all_yet, on the oldest Fix Version/s branch (a fix is pushed there and
    merged up), by the MDEV key in the commit subject, around the date the ticket was resolved. Then it is compared with
    the head of every Fix Version/s branch and of every branch the test fails on. Raises GitError when no commit is found."""
    pull = pull_module()
    fix_branches = pull.fix_version_branches(ticket["fixversions"])
    if not fix_branches:
        raise GitError(f"{ticket['key']} has no release branch among its Fix Version/s ({', '.join(ticket['fixversions']) or 'none'})")
    resolved = parse_time(ticket["resolutiondate"])
    since = pull.github_date(max(parse_time(ticket["created"]), resolved - timedelta(days=pull.FIX_COMMIT_LOOKBACK_DAYS)))
    until = pull.github_date(resolved + timedelta(days=pull.FIX_COMMIT_SLACK_DAYS))
    commit = pull.find_fix_commit(ticket["key"], fix_branches[0], since, until)
    if commit is None:
        raise GitError(f"no commit naming {ticket['key']} on {fix_branches[0]} between {since} and {until}")
    merged: list[str] = []
    not_merged: list[str] = []
    for branch in sorted({*fix_branches, *failing}, key=branch_order):
        has_fix = pull.branch_contains(commit["sha"], branch)
        if has_fix is not None:  # None: no such branch
            (merged if has_fix else not_merged).append(branch)
    return {"fix_commit": commit, "merged_to": merged, "not_merged_to": not_merged}


def checked_fix_state(ticket: dict, failing: set[str]) -> tuple[dict | None, str]:
    """fix_branches_state() that never raises: (state, "") or (None, why). A spent GitHub quota is remembered, as every later
    request of the run would fail the same way."""
    global GIT_BLOCKED, GIT_FAILURES
    if GIT_BLOCKED:
        return None, GIT_BLOCKED
    try:
        return fix_branches_state(ticket, failing), ""
    except Exception as exc:  # GitHub down, out of quota or the pull script changed: the Jira result must survive that
        reason = (str(exc) if isinstance(exc, GitError) else f"{type(exc).__name__}: {exc}")[:300]
        if not isinstance(exc, GitError):
            # The pull script's requests retry for minutes: a GitHub that does not answer must not stall every test
            GIT_FAILURES += 1
            if getattr(exc, "rate_limited", False) or GIT_FAILURES >= GIT_MAX_FAILURES:
                GIT_BLOCKED = reason
        return None, reason


def words(text: str) -> str:
    """Only the lower-case words, so a failure line that a ticket quotes with escaped quotes or JSON \\n still matches."""
    return " " + re.sub(r"[^a-z0-9]+", " ", re.sub(r"\\[nrt]", " ", text.lower())).strip() + " "


def same_failure(ticket: dict, sig: str) -> bool | None:
    """Is the failure line in the ticket (title, description or a comment)? None when there is no line to compare."""
    if not sig or sig.startswith(("+", "-")) or not words(sig).strip():
        return None
    fields = jira_issue(ticket["key"], "summary,description,comment").get("fields") or {}
    time.sleep(JIRA_SLEEP_SECONDS)
    comments = " ".join(c.get("body") or "" for c in (fields.get("comment") or {}).get("comments") or [])
    return words(sig) in words(" ".join([fields.get("summary") or "", fields.get("description") or "", comments]))


def platform_tickets(platform: str) -> tuple[int, list[dict]]:
    """How many tickets mention the platform (exact phrase), and those of them that are Closed/Fixed, a duplicate as the
    ticket it duplicates. A phrase that more than PLATFORM_MAX_HITS tickets carry gives no tickets."""
    if platform not in PLATFORM_TICKETS:
        jql = 'project = MDEV AND text ~ "\\"%s\\"" ORDER BY created DESC' % platform
        data = jira_json("/rest/api/2/search", {"jql": jql, "fields": JIRA_FIELDS, "maxResults": PLATFORM_MAX_HITS})
        time.sleep(JIRA_SLEEP_SECONDS)
        tickets: list[dict] = []
        if data.get("total", 0) <= PLATFORM_MAX_HITS:
            for issue in data.get("issues", []):
                ticket = follow_duplicates(issue_row(issue))
                if ticket["status"] == "Closed" and ticket["resolution"] == "Fixed" and ticket["key"] not in {t["key"] for t in tickets}:
                    tickets.append(ticket)
        PLATFORM_TICKETS[platform] = (data.get("total", 0), tickets)
    return PLATFORM_TICKETS[platform]


def lookup_jira(info: dict, rows_by_test: dict[str, list[dict]]) -> dict:
    test = info["test"]
    result = {"failed": False, "errors": [], "queries": [], "tickets": [], "mentioned": [], "own": None, "fixed": None, "fix_status": "",
              "git": None, "git_error": "", "after_fix": Counter()}
    release = [r for r in rows_by_test.get(test, []) if VERSION_REGEX.match(r["branch"])]
    terms = [("test name", test)]
    if "." in test:
        terms.append(("bare test name", test.split(".", 1)[1]))
    frag = fragment(info["text"])
    if frag:
        terms.append(("failure text", frag))
    sig = changed_or_content_lines(info["text"])[0] if info["text"] else ""
    seen: set[str] = set()
    try:
        for how, term in terms:
            if not re.fullmatch(r"[\w .+:'()-]+", term):
                continue
            rows = jira_search(term)
            result["queries"].append((how, term, len(rows)))
            time.sleep(JIRA_SLEEP_SECONDS)
            found = False
            for row in rows:
                if row["key"] in seen:
                    continue
                seen.add(row["key"])
                row["via"] = how
                if term.lower() not in row["summary"].lower():
                    result["mentioned"].append(row)
                    continue
                ticket = follow_duplicates(row)
                ticket["same_failure"] = same_failure(ticket, sig)
                # A title that names the test is not enough: a ticket whose text lacks this failure line is about another failure
                if ticket["same_failure"] is False:
                    result["mentioned"].append(ticket)
                else:
                    result["tickets"].append(ticket)
                    found = True
            if found:
                break
        # A test named after a ticket (galera.MDEV-40727) is not found by the phrase search: fetch the key. It is the
        # test's own ticket whatever its text says, so it is never listed as only mentioned
        key = KEY_IN_NAME_REGEX.search(test)
        if key:
            own = issue_row(jira_issue(f"MDEV-{key.group(1)}"))
            time.sleep(JIRA_SLEEP_SECONDS)
            own["via"] = "key in the test name"
            if own["status"] == "Closed":
                own["same_failure"] = same_failure(own, sig)
            result["own"] = own
            result["after_fix"] = after_fix_failures(own, release)
            if result["after_fix"]:
                result["fixed"] = own
            result["tickets"] = [own] + [t for t in result["tickets"] if t["key"] != own["key"]]
            result["mentioned"] = [t for t in result["mentioned"] if t["key"] != own["key"]]
        # Failures that follow the platform (here all of them on Fedora 45 and Ubuntu 26.10 builders) are often one environment
        # change whose ticket never names the test or the failure line: look for a ticket that mentions the platform, was fixed
        # shortly before the failures began and still fails on its fix branches. Not when an open ticket, the test's own
        # ticket or a fix that is not merged everywhere already explains the test.
        if info["platforms"] and not info["not_merged"] and not result["fixed"] and all(t["status"] == "Closed" for t in result["tickets"]):
            since = (info["onset"] - timedelta(days=PLATFORM_FIX_DAYS)).date().isoformat()
            for platform in info["platforms"]:
                mentions, fixed_tickets = platform_tickets(platform)
                result["queries"].append(("builder OS", platform, mentions))
                for ticket in fixed_tickets:
                    after = after_fix_failures(ticket, release) if ticket["resolutiondate"][:10] >= since else Counter()
                    if after and ticket["key"] not in {t["key"] for t in result["tickets"]}:
                        ticket = dict(ticket, via=f"builder OS '{platform}'")
                        result["tickets"].append(ticket)
                        if not result["fixed"]:
                            result["fixed"], result["after_fix"] = ticket, after
        # Which release branches have the fix of that ticket. Not for a fix the pull script found (its record says already),
        # and not when an open ticket wins, as the test is then not listed as fixed.
        if result["fixed"] and not info["not_merged"] and all(t["status"] == "Closed" for t in result["tickets"]):
            result["git"], result["git_error"] = checked_fix_state(result["fixed"], set(info["per_branch"]))
        # The Jira state of the fix that the pull script found but that is not merged everywhere yet (the slide summary names it)
        fix_key = nm_mdev(info["not_merged"])["key"] if info["not_merged"] else ""
        if fix_key:
            result["fix_status"] = issue_row(jira_issue(fix_key))["status"]
            time.sleep(JIRA_SLEEP_SECONDS)
        # The namesakes about another failure come first among the tickets that are only mentioned
        result["mentioned"].sort(key=lambda t: t["same_failure"] is not False)
    except JiraError as exc:
        result["failed"] = True
        result["errors"].append(str(exc))
    except Exception as exc:  # a surprise in one lookup must not cost the report
        result["failed"] = True
        result["errors"].append(f"{type(exc).__name__}: {exc}")
    return result


def category(info: dict) -> str:
    jira = info["jira"]
    if info["not_merged"]:
        return "fixed_but_failing"
    if jira["failed"] and not jira["tickets"]:
        return "lookup_failed"
    # An open ticket about the test wins over a closed namesake: galera.mdev-22063 fails for an
    # unrelated reason, MDEV-22063 itself was fixed long ago
    if any(t["status"] != "Closed" for t in jira["tickets"]):
        return "open"
    if jira["after_fix"]:
        return "fixed_but_failing"
    if jira["tickets"]:
        return "closed"
    return "needs_bug"


# ---------------------------------------------------------------------------------------------
# Report content
# ---------------------------------------------------------------------------------------------
def ticket_link(key: str) -> str:
    return f"[{key}]({JIRA_URL}/browse/{key})"


def ticket_text(ticket: dict) -> str:
    status = ticket["status"] + (f"/{ticket['resolution']}" if ticket["resolution"] else "")
    text = f"{ticket_link(ticket['key'])} {status}"
    if ticket["dup_of"]:
        text += f" (original of {ticket['dup_of']})"
    if ticket["via"] == "failure text":
        text += " (same failure text, other test)"
    elif ticket["via"] == "key in the test name":
        text += " (the test's own ticket)"
    elif ticket["via"].startswith("builder OS"):
        text += f" (found by {ticket['via']}: the ticket does not name this test, confirm by hand)"
    return text


def mention_text(ticket: dict) -> str:
    """A ticket that only mentions the test: how it ended and when, so an old closed namesake reads as one."""
    ended = ticket["resolution"] or ticket["status"]
    return f"{ticket_link(ticket['key'])} ({ended}{' ' + ticket['resolutiondate'][:4] if ticket['resolutiondate'] else ''})"


def nm_mdev(record: dict) -> dict:
    """The MDEV of a not_merged_to_all_yet record as {key, url, summary}; it is an object there, but accept a plain key too."""
    mdev = record.get("mdev") or {}
    if isinstance(mdev, str):
        return {"key": mdev, "url": f"{JIRA_URL}/browse/{mdev}", "summary": ""}
    return {"key": mdev.get("key", ""), "url": mdev.get("url", ""), "summary": mdev.get("summary", "")}


def nm_fix_commit_text(record: dict) -> str:
    fix = record.get("fix_commit")
    if isinstance(fix, dict) and fix.get("sha"):
        return f"[{fix['sha'][:12]}]({fix.get('url', '')}) on {fix.get('branch', '?')} ({(fix.get('date') or '')[:10]})"
    return str(fix or "unknown")


def status_text(info: dict) -> str:
    jira = info["jira"]
    parts = []
    fixed_key = nm_mdev(info["not_merged"])["key"] if info["not_merged"] else ""
    if info["not_merged"]:
        parts.append(f"{ticket_link(fixed_key)} fixed, not merged everywhere" if fixed_key else "fix not merged everywhere")
    parts += [ticket_text(t) for t in jira["tickets"] if t["key"] != fixed_key][:3]
    if jira["git"]:
        parts.append("fixed " + fix_scope(jira["git"]["merged_to"], jira["git"]["not_merged_to"]))
    if jira["after_fix"] and not info["not_merged"]:
        parts.append("still failing after the fix on " + ", ".join(sorted(jira["after_fix"])))
    if jira["failed"] and not parts:
        return "Jira lookup failed"
    if not parts and jira["mentioned"]:
        return "only mentioned in " + ", ".join(mention_text(t) for t in jira["mentioned"][:3])
    # Shown, not dropped: the failure line may be in the ticket in other words
    namesakes = [t for t in jira["mentioned"] if t["same_failure"] is False and t["key"] != fixed_key][:2]
    if parts and namesakes:
        parts.append("also names the test, but its text lacks this failure line: " + ", ".join(mention_text(t) for t in namesakes))
    return "; ".join(parts) or "No MDEV"


def branches_text(info: dict, with_commit: bool = False) -> str:
    if with_commit:
        return ", ".join(f"{b}: {info['per_branch'][b]} (last {info['last'][b][0][:12]} at {info['last'][b][1]})"
                         for b, _ in info["per_branch"].most_common())
    return ", ".join(f"{b}: {c}" for b, c in info["per_branch"].most_common())


def slide_jira(info: dict) -> str:
    """The Jira line of the single-slide summary: the section the test falls in, then its ticket."""
    jira, kind = info["jira"], category(info)
    if kind == "needs_bug":
        return "Needs a bug (no MDEV found)"
    if kind == "lookup_failed":
        return "Jira lookup failed"
    if kind == "open":
        return "Known, open " + ", ".join([t["key"] for t in jira["tickets"] if t["status"] != "Closed"][:3])
    if kind == "fixed_but_failing":
        # Where the fix is: the pull script's record says for a fix it found, GitHub for the others (None: could not ask)
        if info["not_merged"]:
            nm = info["not_merged"]
            ticket = " ".join(filter(None, [jira["fix_status"].lower(), nm_mdev(nm)["key"]]))
            if not nm.get("merged_to"):
                return "not_merged_to_all_yet" + (f", {ticket}" if ticket else "")
            return f"Fixed {fix_scope(nm['merged_to'], nm.get('not_merged_to') or [])}. {ticket}"
        fixed = jira["fixed"]
        ticket = f"closed {fixed['key']}"
        if not jira["git"]:
            return f"Fixed in Jira but still failing, {ticket}"
        where = fix_scope(jira["git"]["merged_to"], jira["git"]["not_merged_to"])
        return f"Fixed {where}{', still failing' if where == 'in all branches' else ''}. {ticket}"
    return "Only closed tickets: " + ", ".join(t["key"] for t in jira["tickets"][:3])


def slide_text(infos: list[dict]) -> str:
    """The single-slide summary: the top SLIDE_TESTS ranked tests as plain lines to paste onto a slide."""
    lines = []
    for number, info in enumerate(infos[:SLIDE_TESTS], 1):
        lines += [f"{number}.",
                  f"{info['test']}: {info['failures']}",
                  "Affected branches: " + "|".join(branch for branch, _ in info["per_branch"].most_common()),
                  "Fail text: " + info["excerpt"],
                  "Jira: " + slide_jira(info)]
    return "\n".join(lines)


def build_blocks(ctx: dict) -> tuple[list, dict]:
    infos = ctx["infos"]
    from_date, until_date = ctx["from_date"], ctx["until_date"]
    cats: dict[str, list[dict]] = {}
    for info in infos:
        cats.setdefault(category(info), []).append(info)
    needs = [i["test"] for i in cats.get("needs_bug", [])]
    headline = [
        f"{len(infos)} ranked tests, {sum(i['failures'] for i in infos)} failures on release branches; "
        f"{len(needs)} without an MDEV, {len(cats.get('fixed_but_failing', []))} fixed in Jira but still failing, "
        f"{len(cats.get('open', []))} with an open MDEV, {len(cats.get('closed', []))} with only closed tickets"
        + (f", {len(cats.get('lookup_failed', []))} Jira lookups failed" if cats.get("lookup_failed") else "") + ".",
    ]
    if infos:
        top = infos[0]
        headline.append(f"Most failing: {top['test']} ({top['failures']} failures; {branches_text(top)}).")
    if needs:
        headline.append("Without an MDEV: " + ", ".join(needs[:5]) + (f" (+{len(needs) - 5} more)" if len(needs) > 5 else "") + ".")

    blocks: list = [
        ("title", f"Weekly MTR failure report ({LABEL}): {', '.join(SUITE_GROUPS)}"),
        ("p", f"Window {until_date} to {from_date} (UTC), generated {datetime.now(timezone.utc):%Y-%m-%d %H:%M}Z on {socket.gethostname()}. "
              "Release branches only (10.x to 13.x and main); PR and bb-* branches are not ranked."),
        ("p", f"Saved on {socket.gethostname()} in `{ctx['run_dir']}/`: report.md, report.html (this report) and rows_*.json.gz (every failing run of the window)."),
    ]
    if infos:
        blocks += [("h2", "Single-slide summary"), ("pre", slide_text(infos))]
    blocks += [
        ("h2", "Summary"),
        ("ul", [
            f"Suite groups: {', '.join(SUITE_GROUPS)}",
            f"Rows fetched: {ctx['rows_all']} on all branches, {ctx['rows_release']} on release branches",
            f"Distinct failing tests: {ctx['tests_all']} on all branches, {ctx['tests_release']} on release branches",
        ] + headline),
    ]
    if infos:
        blocks += [("h2", "Top failing tests"), ("table",
            ["Rank", "Test", "Failures", "Branches", "Builders (top 3)", "Failure excerpt", "MDEV status"],
            [[str(n), f"`{i['test']}`", str(i["failures"]), branches_text(i), i["top_builders"], f"`{i['excerpt']}`" if i["excerpt"] else "", status_text(i)]
             for n, i in enumerate(infos, 1)])]
    for info in cats.get("needs_bug", []):
        if info is cats["needs_bug"][0]:
            blocks.append(("h2", "Needs a bug (no MDEV found)"))
        blocks += [("h3", f"`{info['test']}`"), ("ul", [
            f"Branches (last commit): {branches_text(info, True)}",
            f"Builders: {info['top_builders']}",
            f"Verdict: {info['verdict']}",
            "Jira: " + status_text(info) + " (searched: " + "; ".join(f"{how} '{term}' = {n}" for how, term, n in info["jira"]["queries"]) + ")",
        ]), ("pre", "\n".join(info["text"].splitlines()[:8]))]
    if cats.get("lookup_failed"):
        blocks.append(("h2", "Jira lookup failed (not known whether these have an MDEV)"))
        blocks.append(("ul", [f"`{i['test']}`: {'; '.join(i['jira']['errors'])}" for i in cats["lookup_failed"]]))
    if cats.get("fixed_but_failing"):
        rows = []
        for info in cats["fixed_but_failing"]:
            if info["not_merged"]:
                nm = info["not_merged"]
                fixed = nm_mdev(nm)
                detail = (f"fix commit {nm_fix_commit_text(nm)}; merged to {', '.join(nm.get('merged_to') or []) or '-'}; "
                          f"not merged to {', '.join(nm.get('not_merged_to') or []) or '-'}")
                mdev = ticket_link(fixed["key"]) if fixed["key"] else "-"
                summary = fixed["summary"]
            else:
                fixed = info["jira"]["fixed"]
                detail = f"closed Fixed {fixed['resolutiondate'][:10]}, still failing after the fix on " + ", ".join(f"{b} ({n})" for b, n in sorted(info["jira"]["after_fix"].items()))
                git = info["jira"]["git"]
                if git:
                    detail += (f"; fix commit {nm_fix_commit_text(git)}; merged to {', '.join(git['merged_to']) or '-'}; "
                               f"not merged to {', '.join(git['not_merged_to']) or '-'}")
                if fixed["via"].startswith("builder OS"):
                    detail += f"; found by {fixed['via']} (the failures sit on {' / '.join(info['platforms'])} builders), the ticket does not name this test"
                mdev, summary = ticket_link(fixed["key"]), fixed["summary"]
            rows.append([f"`{info['test']}`", mdev, summary, detail, branches_text(info)])
        blocks += [("h2", "Fixed in Jira but still failing"), ("table", ["Test", "MDEV", "Summary", "Fix state", "Failing branches"], rows)]
    if cats.get("open"):
        rows = []
        for info in cats["open"]:
            closed = [t for t in info["jira"]["tickets"] if t["status"] == "Closed"]
            also = "; ".join(ticket_text(t) + (" still failing after the fix on " + ", ".join(sorted(info["jira"]["after_fix"]))
                                                if t["via"] == "key in the test name" and info["jira"]["after_fix"] else "") for t in closed[:2])
            for t in [t for t in info["jira"]["tickets"] if t["status"] != "Closed"][:3]:
                rows.append([f"`{info['test']}`", ticket_link(t["key"]), t["status"], t["summary"], t["via"], also or "-"])
        blocks += [("h2", "Known, open MDEV"), ("table", ["Test", "MDEV", "Status", "Summary", "Found by", "Closed tickets of the same test"], rows)]
    if cats.get("closed"):
        rows = []
        for info in cats["closed"]:
            for t in info["jira"]["tickets"][:3]:
                same = {True: "the failure line is in the ticket text", False: "the failure line is not in the ticket text, check by hand", None: "not compared"}[t["same_failure"]]
                rows.append([f"`{info['test']}`", ticket_link(t["key"]), t["resolution"] or t["status"], ", ".join(t["fixversions"]) or "-", t["resolutiondate"][:10] or "-", same])
        blocks += [("h2", "Only closed tickets found"), ("table", ["Test", "MDEV", "Resolution", "Fix versions", "Resolved", "Same failure?"], rows)]
    blocks += [("h2", "Notes"), ("ul", ctx["notes"])]
    return blocks, {"headline": headline, "needs_bug": needs}


# ---------------------------------------------------------------------------------------------
# Rendering (the same blocks to Markdown and HTML)
# ---------------------------------------------------------------------------------------------
INLINE_REGEX = re.compile(r"(\[[^\]]+\]\(https?://[^)\s]+\)|`[^`]+`)")
# Inline styles only, no <style> block: the same document is the report.html file and the HTML body of the
# email, and mail clients drop or rewrite embedded style sheets
HTML_STYLES = {
    "body": "font-family:Arial,Helvetica,sans-serif;font-size:14px;color:#222;margin:0;padding:8px",
    "h1": "font-size:22px;margin:12px 0 8px",
    "h2": "font-size:18px;margin:18px 0 6px;border-bottom:1px solid #ddd;padding-bottom:3px",
    "h3": "font-size:15px;margin:14px 0 4px",
    "p": "margin:6px 0",
    "ul": "margin:6px 0 6px 20px;padding:0",
    "table": "border-collapse:collapse;margin:8px 0;font-size:13px",
    "th": "border:1px solid #bbb;padding:4px 8px;text-align:left;vertical-align:top;background:#eee",
    "td": "border:1px solid #bbb;padding:4px 8px;text-align:left;vertical-align:top",
    "pre": "background:#f6f6f6;padding:8px;font-size:12px;white-space:pre-wrap;word-break:break-all",
    "code": "background:#f0f0f0;padding:0 3px;font-family:Consolas,monospace;font-size:12px",
}


def tag(name: str, content: str) -> str:
    return f'<{name} style="{HTML_STYLES[name]}">{content}</{name}>'


def inline_html(text: str) -> str:
    out = []
    for token in INLINE_REGEX.split(text):
        link = re.fullmatch(r"\[([^\]]+)\]\((https?://[^)\s]+)\)", token)
        if link:
            out.append(f'<a href="{html.escape(link.group(2))}">{html.escape(link.group(1))}</a>')
        elif len(token) > 1 and token.startswith("`") and token.endswith("`"):
            out.append(tag("code", html.escape(token[1:-1])))
        else:
            out.append(html.escape(token))
    return "".join(out)


def render_md(blocks: list) -> str:
    out = []
    for block in blocks:
        kind = block[0]
        if kind == "title":
            out.append(f"# {block[1]}\n")
        elif kind == "h2":
            out.append(f"\n## {block[1]}\n")
        elif kind == "h3":
            out.append(f"\n### {block[1]}\n")
        elif kind == "p":
            out.append(block[1] + "\n")
        elif kind == "ul":
            out += [f"- {item}" for item in block[1]] + [""]
        elif kind == "pre":
            out += ["```text", block[1], "```", ""]
        elif kind == "table":
            cell = lambda s: re.sub(r"\s+", " ", s).replace("|", "\\|")
            out.append("| " + " | ".join(cell(h) for h in block[1]) + " |")
            out.append("|" + "---|" * len(block[1]))
            out += ["| " + " | ".join(cell(c) for c in row) + " |" for row in block[2]] + [""]
    return "\n".join(out)


def render_html(blocks: list) -> str:
    out = ["<!doctype html><html><head><meta charset='utf-8'><title>Weekly MTR failure report</title></head>",
           f'<body style="{HTML_STYLES["body"]}">']
    for block in blocks:
        kind = block[0]
        if kind == "title":
            out.append(tag("h1", inline_html(block[1])))
        elif kind in ("h2", "h3"):
            out.append(tag(kind, inline_html(block[1])))
        elif kind == "p":
            out.append(tag("p", inline_html(block[1])))
        elif kind == "ul":
            out.append(tag("ul", "".join(f"<li>{inline_html(i)}</li>" for i in block[1])))
        elif kind == "pre":
            out.append(tag("pre", html.escape(block[1])))
        elif kind == "table":
            rows = ["<tr>" + "".join(tag("th", inline_html(h)) for h in block[1]) + "</tr>"]
            rows += ["<tr>" + "".join(tag("td", inline_html(c)) for c in row) + "</tr>" for row in block[2]]
            out.append(tag("table", "".join(rows)))
    out.append("</body></html>")
    return "\n".join(out)


# ---------------------------------------------------------------------------------------------
# Email
# ---------------------------------------------------------------------------------------------
def send_mail(subject: str, body: str, dry_run: bool, html_path: Path | None = None) -> bool:
    """body is the plain-text part; html_path, when given, becomes the HTML part of the message."""
    if dry_run:
        log("email not sent (--no-email). Subject: " + subject + (f" (HTML part: {html_path})" if html_path else ""))
        print("-----\n" + body + "\n-----", flush=True)
        return True
    command = [sys.executable, str(EMAIL_SCRIPT), "--to", RECIPIENT, "--subject", subject, "--body-file", "-"]
    if html_path is not None:
        command += ["--html-file", str(html_path)]
    try:
        done = subprocess.run(command, input=body, text=True, encoding="utf-8", capture_output=True, timeout=180)
    except Exception as exc:
        log(f"email failed: {exc!r}")
        return False
    log("email: " + ((done.stdout or done.stderr).strip().splitlines() or ["(no output)"])[-1])
    return done.returncode == 0


def alert_body(run_dir: Path, from_date: str, until_date: str, summary: dict, row_files: list[str]) -> str:
    lines = [
        f"The weekly MTR failure report {LABEL} ({', '.join(SUITE_GROUPS)}; {until_date} to {from_date}, UTC) is ready on {socket.gethostname()}.",
        "The full report is the HTML part of this email (switch to the HTML view if you only see this text).",
        "",
        f"Report folder: {run_dir}/",
        "  report.md    - read in a terminal or an editor",
        "  report.html  - the same report as in this email, for a browser (copy it to your computer first)",
    ] + [f"  {name} - every failing run of the window" for name in row_files] + [""] + summary["headline"]
    return "\n".join(lines) + "\n"


def failure_body(run_dir: Path, from_date: str, reason: str) -> str:
    tail = ""
    err = run_dir / "pull_stderr.txt"
    if err.exists():
        tail = "\n".join(err.read_text(encoding="utf-8", errors="replace").splitlines()[-20:])
    return (f"The weekly MTR failure report {LABEL} ({', '.join(SUITE_GROUPS)}; {from_date}) did not complete on {socket.gethostname()}.\n\n"
            f"What failed: {reason}\nRun folder: {run_dir}/\nLog: {run_dir}/run.log (and the cron log {REPORT_ROOT}/{LABEL}/cron.log)\n\n"
            f"Last lines of the report script's stderr:\n{tail or '(none)'}\n")


# ---------------------------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------------------------
def build(args, run_dir: Path, from_date: str, until_date: str) -> tuple[dict, list[str]]:
    if args.reuse_dir:
        source = Path(args.reuse_dir)
        log(f"reusing the finished pull in {source}")
        for name, target in (("stdout_1.txt", "pull_stdout.txt"), ("stderr_1.txt", "pull_stderr.txt")):
            shutil.copy(source / name, run_dir / target)
        for path in source.glob("test_failures_*.json"):
            shutil.copy(path, run_dir / path.name)
    else:
        run_pull(run_dir, from_date, until_date)
    pooled = parse_pooled((run_dir / "pull_stdout.txt").read_text(encoding="utf-8", errors="replace"))
    rows = load_rows(run_dir)
    if not rows:
        raise StepError("the pull produced no rows file")
    rows_by_test: dict[str, list[dict]] = {}
    for row in rows:
        rows_by_test.setdefault(row["test_name"], []).append(row)
    release = [r for r in rows if VERSION_REGEX.match(r["branch"])]
    log(f"rows: {len(rows)} on all branches, {len(release)} on release branches")

    ranked = list(pooled.get("top_fail_tests_all_suites") or [])
    not_merged = {rec["test_name"]: rec for rec in pooled.get("not_merged_to_all_yet") or []}
    ranked += [rec for rec in not_merged.values() if rec["test_name"] not in {e["test_name"] for e in ranked}]
    infos = [analyse(entry, rows_by_test) for entry in ranked]
    for info in infos:
        info["not_merged"] = not_merged.get(info["test"])
    infos.sort(key=lambda i: (-i["failures"], i["test"]))
    notes = []
    for number, info in enumerate(infos, 1):
        log(f"jira lookup {number}/{len(infos)}: {info['test']}")
        info["jira"] = lookup_jira(info, rows_by_test)
        if info["jira"]["failed"]:
            notes.append(f"Jira lookup problem for {info['test']}: {'; '.join(info['jira']['errors'])}")
        if info["failures"] != info["release_rows"]:
            notes.append(f"{info['test']}: the ranking counts {info['failures']} failures, the rows file has {info['release_rows']} release-branch rows.")
    # One note per ticket and reason, not per test: a spent GitHub quota would otherwise repeat for every row
    git_errors: dict[tuple[str, str], list[str]] = {}
    for info in infos:
        if info["jira"]["git_error"]:
            git_errors.setdefault((info["jira"]["fixed"]["key"], info["jira"]["git_error"]), []).append(info["test"])
    for (key, error), tests in git_errors.items():
        notes.append(f"Git check of {key} failed for {len(tests)} test(s), e.g. {tests[0]}: {error}. Those rows keep Jira's wording."
                     + (" Set GITHUB_TOKEN (or GH_TOKEN) in the crontab to lift GitHub's 60 requests an hour." if "rate limit" in error else ""))

    stderr_lines = [l for l in (run_dir / "pull_stderr.txt").read_text(encoding="utf-8", errors="replace").splitlines() if l.strip() and not l.startswith("Wrote ")]
    notes += [f"Report script warning: {l}" for l in stderr_lines[:10]]
    head = subprocess.run(["git", "-C", str(REPO), "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
    notes += [f"mariadb-qa commit {head or 'unknown'} on {socket.gethostname()}.",
              "Jira lookups are anonymous and read-only; a ticket counts as a match when its title contains the test name (or the failure line) and its text holds this failure line. "
              "A title match whose text lacks the failure line is listed as only mentioned. A test whose failures sit on a few platforms that few tickets mention is also looked up by platform (a ticket fixed shortly before the first failure). "
              "For a fixed ticket GitHub says which branches have the fix: its commit (the MDEV key in the subject, on the oldest Fix Version/s branch) is compared with every branch head, as Jira's Fix Version/s say where a fix is meant to go and not where it has got to. "
              "Generated without an AI step."]
    ctx = {"infos": infos, "from_date": from_date, "until_date": until_date, "notes": notes, "run_dir": run_dir,
           "rows_all": len(rows), "rows_release": len(release),
           "tests_all": len({r["test_name"] for r in rows}), "tests_release": len({r["test_name"] for r in release})}
    blocks, summary = build_blocks(ctx)
    (run_dir / "report.md").write_text(render_md(blocks), encoding="utf-8")
    (run_dir / "report.html").write_text(render_html(blocks), encoding="utf-8")
    row_files = compress_rows(run_dir)
    log(f"report written to {run_dir}")
    return summary, row_files


def main() -> int:
    global RUN_LOG, REPORT_ROOT, LABEL
    parser = argparse.ArgumentParser(description="Weekly MTR failure report")
    parser.add_argument("--label", default=LABEL)
    parser.add_argument("--suite-groups", default=",".join(SUITE_GROUPS))
    parser.add_argument("--no-email", action="store_true")
    parser.add_argument("--reuse-dir")
    parser.add_argument("--from-date")
    parser.add_argument("--until-date")
    parser.add_argument("--report-root")
    args = parser.parse_args()

    if args.report_root:
        REPORT_ROOT = Path(args.report_root)
    if not re.fullmatch(r"[\w-]+", args.label):
        parser.error("--label may only hold letters, digits, _ and -")
    LABEL = args.label
    SUITE_GROUPS[:] = [g.strip() for g in args.suite_groups.split(",") if g.strip()]
    if not SUITE_GROUPS:
        parser.error("--suite-groups is empty")
    today = datetime.now(timezone.utc).date()
    from_date = args.from_date or today.isoformat()
    until_date = args.until_date or (today - timedelta(days=WINDOW_DAYS)).isoformat()
    job_dir = REPORT_ROOT / LABEL
    run_dir = job_dir / from_date
    run_dir.mkdir(parents=True, exist_ok=True)
    RUN_LOG = run_dir / "run.log"

    lock = open(job_dir / ".lock", "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        log("another run holds the lock, exiting")
        return 3
    log(f"start: {LABEL} ({','.join(SUITE_GROUPS)}), window {until_date} to {from_date}, folder {run_dir}")
    try:
        summary, row_files = build(args, run_dir, from_date, until_date)
    except Exception as exc:
        reason = str(exc) if isinstance(exc, StepError) else f"{type(exc).__name__}: {exc}"
        log("FAILED: " + reason)
        if not isinstance(exc, StepError):
            log(traceback.format_exc())
        send_mail(f"[MTR weekly] FAILED {LABEL} {from_date}", failure_body(run_dir, from_date, reason), args.no_email)
        return 1
    subject = (f"[MTR weekly] {LABEL} {until_date} to {from_date}: report ready "
               f"({len(summary['needs_bug'])} without an MDEV)")
    send_mail(subject, alert_body(run_dir, from_date, until_date, summary, row_files), args.no_email, run_dir / "report.html")
    log("done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
