#!/usr/bin/env python3
"""Export historical test failures from the cross-reference API.
Original work by Razvan-Liviu Varzaru
https://gist.github.com/RazvanLiviuVarzaru/e0ca03588f730cef3eeba99a8cbb5e36
Extended by Susil
Sample Usages:
os.path.basename(__file__) --test-name 'galera.*' --from-date 2026-08-03 --until-date 2026-07-26 --format json
os.path.basename(__file__) --test-name 'rpl.*,binlog.*,multi_source.*,binlog_encryption.*' --from-date 2026-08-03 --until-date 2026-07-26 --format json

The report printed at the end is one JSON object with, at the same level:
  top_fail_tests_all_suites  the most failing tests, with a breakdown per release branch,
                             except the ones in not_merged_to_all_yet
  not_merged_to_all_yet      the tests among the top failing ones that already have an MDEV
                             (jira.mariadb.org) with a fix commit (GitHub) that is merged to
                             some release branches but has not reached a branch the test still
                             fails on. A record is the entry the test would have had in the
                             ranking, and the MDEV, the fix commit and which branches have the
                             fix and which do not. The ranking is not refilled, so it can come
                             up short of the number of tests asked for. The merge state is the
                             one at the time of the run, whatever date range was asked for.
An MDEV is taken to be about a test when the test name, suite included, is in its summary.
GitHub allows 60 requests an hour to anonymous clients, which a run with several fixed MDEVs
can use up: set GITHUB_TOKEN (or GH_TOKEN) to a GitHub token to lift that. Nothing else is
needed, and nothing is written to Jira or GitHub.
"""

from __future__ import annotations

import argparse
import csv
import html
import json
import os
import re
import sys
import time
from datetime import datetime, timedelta, timezone
from functools import lru_cache
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qsl, quote, urlencode, urlsplit, urlunsplit
from urllib.request import Request, urlopen
from collections import Counter
from difflib import SequenceMatcher


DEFAULT_BASE_URL = "http://buildbot.mariadb.org/cr/api/testfailures/"
# Endpoint the reported 'fail_url' links point at, independent of --base-url
FAIL_URL_BASE = "https://buildbot.mariadb.org/cr/api/testfailures/"
MAX_LIMIT = 200
TOP_FAIL_TESTS_COUNT = 10
# The cross-reference API is slow and occasionally stalls outright, in particular on the
# unbounded fail_url queries, so every request gets a few attempts with a growing timeout
# and a backoff in between before it is given up on.
REQUEST_TIMEOUT = 60
REQUEST_ATTEMPTS = 3
RETRY_BACKOFF = 5
# nginx 504s these are worth another go; anything else (404, 400, ...) will not fix itself
RETRYABLE_HTTP_CODES = frozenset((429, 500, 502, 503, 504))
# Rows per fail_url request. A busy test asked for MAX_LIMIT rows in one go makes the API
# exceed nginx's gateway timeout and answer 504 (measured: 100 rows answers in under a
# second, 150 and 200 both time out), so the per-branch lookup pages instead.
FAIL_URL_LIMIT = 100
# Ceiling on the rows one per-branch breakdown is built from. The signature grouping is
# quadratic in the number of failures, so this bounds the report's runtime as well.
FAIL_ROWS_MAX = 1000
# Version-like branches, e.g. 10.6, 11.4, 12.0, 13.1, main. Entries on any other branch
# (refs/pull/5403/head and the like) are dropped from the per-branch breakdown.
VERSION_REGEX = re.compile(r"^(((10|11|12|13)\.\d+)|main)$")
# Per-run details masked out of failure_text before failures are compared: the mtr worker
# id on the header line, timestamps (the 'Test ended at' line and the .result/.reject diff
# header), and the buildbot worker's paths, which carry both its hostname and worker id.
WORKER_ID_REGEX = re.compile(r"\bw\d+\b")
TIMESTAMP_REGEX = re.compile(r"\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}")
BUILD_PATH_REGEX = re.compile(r"\S*?/build/mysql-test/")
WORKER_VARDIR_REGEX = re.compile(r"/var/\d+/")
# Two masked failure_texts more similar than this are taken to be the same failure, so
# reports that only differ in a few values (row counts, ids, a single diff line) do not
# each show up as a distinct failure. Only a similarity of 60% or less makes two failures
# distinct.
SIMILARITY_THRESHOLD = 0.60
# A fix is pushed to the oldest branch it applies to and merged up from there (10.11 -> 11.4
# -> ... -> main), which can lag by weeks. Until a branch has merged it, a test keeps failing
# on that branch although the MDEV that fixed it is closed. The 'not_merged_to_all_yet' report
# finds those tests, and takes them out of the ranking of the top failing tests: Jira says which
# MDEV fixed a test, GitHub says which branches have the fix.
JIRA_URL = "https://jira.mariadb.org"
GITHUB_API_URL = "https://api.github.com"
GITHUB_REPO = "MariaDB/server"
JIRA_MAX_RESULTS = 50
GITHUB_PAGE_SIZE = 100
# Only MDEVs resolved this recently are looked at. It bounds how many tickets, and with them
# GitHub requests (60 an hour without a token), one run spends. It assumes that a merge-up
# takes less than this: it has been seen to take over four weeks, not four months.
MERGE_LOOKBACK_DAYS = 120
# A fix is pushed around the time its MDEV is resolved, a few days either side, so its commit is
# searched for from FIX_COMMIT_LOOKBACK_DAYS before the resolution (never before the MDEV was
# created) until FIX_COMMIT_SLACK_DAYS after it. Measured from the creation instead, an MDEV
# that sat open for years before it was fixed would have the search cover all of them.
FIX_COMMIT_LOOKBACK_DAYS = 30
FIX_COMMIT_SLACK_DAYS = 14
# Pages of GITHUB_PAGE_SIZE commits searched per branch for the fix commit. The window above
# is small enough for this to be plenty; hitting it is reported rather than taken for "no fix".
FIX_COMMIT_PAGES = 5
# 10.11.20 -> 10.11. Fix Version/s that name no release branch ('N/A', '10.4(EOL)') do not match.
FIX_VERSION_REGEX = re.compile(r"^(\d+\.\d+)(?:\.\d+)?$")
# What a test name may be made of to go into a JQL phrase as is: suite.test, as MTR names it
TEST_NAME_REGEX = re.compile(r"^[\w.+-]+$")
OUTPUT_FORMATS = ("csv", "html", "json", "both", "all")
CSV_FIELDS = [
    "dt",
    "builder_name",
    "commit",
    "branch",
    "test_name",
    "test_variant",
    "info_text",
    "failure_text",
]
DISTINCT_FAILURE_FIELDS = [
    "builder_name",
    "commit",
    "branch",
    "dt",
    "test_name",
    "info_text",
    "failure_text",
]
DATE_FORMATS = (
    "%Y-%m-%d",
    "%Y-%m-%dT%H:%M",
    "%Y-%m-%dT%H:%M:%S",
    "%Y-%m-%dT%H:%M:%SZ",
    "%Y-%m-%d %H:%M:%S",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Fetch test failures by test_name from the cross-reference API, "
            "paging backwards in 200-row chunks, and save them to CSV, HTML, and/or JSON."
        )
    )
    parser.add_argument(
        "--test-name",
        "--test_name",
        dest="test_name",
        action="append",
        required=True,
        help=(
            "Test name filter accepted by the API, e.g. main.sp-error, rpl.*, galera.*. "
            "May be repeated, and/or given as a comma-separated list, to fetch several "
            "suites in one run; each filter is exported to its own set of files and all "
            "of them feed the final 'top_fail_tests_all_suites' and 'not_merged_to_all_yet' "
            "reports."
        ),
    )
    parser.add_argument(
        "--until-date",
        "--until_date",
        dest="until_date",
        required=True,
        help=(
            "Oldest date to fetch through. Accepted formats include YYYY-MM-DD, "
            "YYYY-MM-DDTHH:MM:SS, and YYYY-MM-DDTHH:MM:SSZ."
        ),
    )
    parser.add_argument(
        "--from-date",
        "--from_date",
        dest="from_date",
        help=(
            "Newest date to start fetching from. If omitted, starts from the latest "
            "available failures. Accepted formats include YYYY-MM-DD, "
            "YYYY-MM-DDTHH:MM:SS, and YYYY-MM-DDTHH:MM:SSZ."
        ),
    )
    parser.add_argument(
        "--branch",
        help="Optional branch filter accepted by the API, e.g. 10.11, main, =10.11.",
    )
    parser.add_argument(
        "--builder",
        help=(
            "Optional builder/platform filter accepted by the API, "
            "e.g. amd64-ubasan-clang-20-debug."
        ),
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        help=(
            "Output CSV path. Defaults to test_failures_<test_name>_<until_date>.csv. "
            "Only valid with a single --test-name filter."
        ),
    )
    parser.add_argument(
        "--html-output",
        type=Path,
        help="Output HTML path. Defaults to the CSV output path with an .html suffix.",
    )
    parser.add_argument(
        "--json-output",
        type=Path,
        help="Output JSON path. Defaults to the CSV output path with a .json suffix.",
    )
    parser.add_argument(
        "--format",
        choices=OUTPUT_FORMATS,
        default="both",
        help=(
            "Export format: csv, html, json, both (csv and html), or all. "
            "Defaults to both."
        ),
    )
    parser.add_argument(
        "--base-url",
        default=DEFAULT_BASE_URL,
        help=f"API endpoint URL. Defaults to {DEFAULT_BASE_URL}",
    )
    parser.add_argument(
        "--sleep",
        type=float,
        default=0.1,
        help="Seconds to sleep between API requests. Defaults to 0.1.",
    )
    return parser.parse_args()


def parse_api_date(value: str) -> datetime:
    normalized = value
    if normalized.endswith("Z"):
        normalized = normalized[:-1] + "+00:00"

    try:
        parsed = datetime.fromisoformat(normalized)
        if parsed.tzinfo is not None:
            return parsed.astimezone(timezone.utc).replace(tzinfo=None)
        return parsed
    except ValueError:
        pass

    for date_format in DATE_FORMATS:
        try:
            return datetime.strptime(value, date_format)
        except ValueError:
            continue

    raise ValueError(f"Unsupported date format: {value}")


def format_api_date(value: datetime) -> str:
    if value.tzinfo is not None:
        value = value.astimezone(timezone.utc).replace(tzinfo=None)
    return value.replace(microsecond=0).isoformat()


def output_path_for(test_name: str, until_date: str) -> Path:
    safe_test_name = "".join(
        char if char.isalnum() or char in ("-", "_", ".") else "_" for char in test_name
    ).strip("._")
    safe_until_date = until_date.replace(":", "").replace(" ", "T")
    return Path(f"test_failures_{safe_test_name}_{safe_until_date}.csv")


def html_path_for(csv_path: Path) -> Path:
    return csv_path.with_suffix(".html")


def json_path_for(csv_path: Path) -> Path:
    return csv_path.with_suffix(".json")


def split_test_names(values: list[str]) -> list[str]:
    """Flatten repeated and/or comma-separated --test-name values, keeping order
    and dropping duplicates (a duplicate filter would only re-fetch the same rows)."""
    test_names: list[str] = []
    for value in values:
        for test_name in value.split(","):
            test_name = test_name.strip()
            if test_name and test_name not in test_names:
                test_names.append(test_name)
    return test_names


def top_fail_tests(counts: Counter, limit: int = TOP_FAIL_TESTS_COUNT) -> dict[str, int]:
    return dict(counts.most_common(limit))


def fail_url_for(test_name: str, until_date: str, from_date: str | None) -> str:
    """API query listing the failures behind one reported test, over the run's date range.
    Same parameter names export_failures() pages with: min_date/max_date are the only date
    bounds this endpoint honours - dt/max_dt are accepted and then silently ignored, which
    turns the query into an all-history scan the API answers with a 504."""
    params: dict[str, Any] = {
        "test_name": test_name,
        "min_date": format_api_date(parse_api_date(until_date)),
        "limit": FAIL_URL_LIMIT,
        "sort_order": "desc",
    }
    if from_date:
        params["max_date"] = format_api_date(parse_api_date(from_date))
    return f"{FAIL_URL_BASE}?{urlencode(params)}"


def fail_url_rows(fail_url: str) -> list[dict[str, Any]]:
    """The failures behind one fail_url, fetched in FAIL_URL_LIMIT-row pages. Paging walks
    max_date back over the oldest row of each page, the way export_failures() does, because
    the API has no offset parameter. Stops at FAIL_ROWS_MAX rows, which a suite-wide filter
    over a long date range can reach; that is reported rather than passed over quietly."""
    split = urlsplit(fail_url)
    params = dict(parse_qsl(split.query))
    params["limit"] = str(FAIL_URL_LIMIT)
    # The oldest date the fail_url asks for; rows older than it are not ours to report
    until_dt = parse_api_date(params["min_date"]) if params.get("min_date") else None

    rows: list[dict[str, Any]] = []
    seen: set[tuple[Any, ...]] = set()
    while True:
        page = fetch_json(urlunsplit(split._replace(query=urlencode(params))))
        if not page:
            break

        dated = sorted(
            ((parse_api_date(str(row["dt"])), row) for row in page if row.get("dt")),
            key=lambda item: item[0],
            reverse=True,
        )
        if not dated:
            break

        oldest_dt = dated[-1][0]
        new_rows = 0
        for row_dt, row in dated:
            if until_dt is not None and row_dt < until_dt:
                continue
            identity = row_identity(row)
            if identity in seen:
                continue
            seen.add(identity)
            rows.append(row)
            new_rows += 1

        if len(rows) >= FAIL_ROWS_MAX:
            print(
                f"Stopped at {len(rows)} failures for {fail_url}; the per-branch "
                f"breakdown does not cover the rest of the date range",
                file=sys.stderr,
            )
            break
        if len(page) < FAIL_URL_LIMIT or (until_dt is not None and oldest_dt <= until_dt):
            break
        # max_date is inclusive, so without this the boundary row repeats forever
        if new_rows == 0:
            oldest_dt = oldest_dt - timedelta(seconds=1)
        params["max_date"] = format_api_date(oldest_dt)

    return rows


def normalize_failure_text(failure_text: str) -> str:
    """failure_text reduced to a comparison key, so that the same failure seen on
    different workers at different times compares equal: the per-run details are masked
    out, and blank lines and trailing whitespace - which vary between otherwise identical
    reports - are dropped. The worker id is only masked on the header line, to leave any
    wNN in the query output alone. Only ever used to group failures; never reported."""
    header, newline, body = failure_text.partition("\n")
    failure_text = WORKER_ID_REGEX.sub("w<id>", header) + newline + body
    failure_text = TIMESTAMP_REGEX.sub("<timestamp>", failure_text)
    failure_text = BUILD_PATH_REGEX.sub("<basedir>/mysql-test/", failure_text)
    failure_text = WORKER_VARDIR_REGEX.sub("/var/<id>/", failure_text)
    return "\n".join(line.rstrip() for line in failure_text.splitlines() if line.strip())


def failure_similarity(left: str, right: str) -> float:
    """Similarity of two masked failure_texts, 0.0 (nothing in common) to 1.0 (equal).
    autojunk is off: it would write off characters appearing in more than 1% of a long
    failure_text as noise, which is exactly the opposite of what we want here."""
    if left == right:
        return 1.0
    matcher = SequenceMatcher(None, left, right, autojunk=False)
    # Both bounds are cheap and never underestimate, so an early no is free
    if matcher.real_quick_ratio() <= SIMILARITY_THRESHOLD:
        return matcher.real_quick_ratio()
    if matcher.quick_ratio() <= SIMILARITY_THRESHOLD:
        return matcher.quick_ratio()
    return matcher.ratio()


def matching_signature(
    signatures: list[dict[str, Any]], normalized: str
) -> dict[str, Any] | None:
    """The signature this failure_text belongs to, i.e. the one it is most similar to,
    provided that similarity is above SIMILARITY_THRESHOLD. None if it matches none of
    them, in which case the caller has found a distinct failure."""
    best: dict[str, Any] | None = None
    best_similarity = SIMILARITY_THRESHOLD
    for signature in signatures:
        similarity = failure_similarity(signature["text"], normalized)
        if similarity > best_similarity:
            best = signature
            best_similarity = similarity
    return best


def is_version_branch(row: dict[str, Any]) -> bool:
    """Whether a failure is on a version-like branch (10.x/11.x/12.x/13.x, main) rather
    than a feature or pull-request branch (bb-13.1-bar-MDEV-39563, refs/pull/5566/head).
    Only failures that pass this are worth ranking: a test that fails exclusively on a
    development branch is that branch's problem, not a regression in a release branch."""
    return bool(VERSION_REGEX.match(str(row.get("branch", ""))))


def branch_failures(fail_url: str) -> dict[str, dict[str, Any]]:
    """filter_testfailures.py logic applied to one fail_url: keep only entries on a
    version-like branch (10.x/11.x/12.x/13.x, main) and drop the rest (refs/pull/... and
    friends), then summarise per branch. Failures of a branch are expected to share one
    failure_text once the per-run details are masked and near-identical reports (more than
    SIMILARITY_THRESHOLD alike) are folded together; distinct_failure_texts carries one
    record per signature seen, most frequent first, so more than one entry means the
    branch is hitting several genuinely different failures."""
    # branch -> [{"text": masked failure_text, "count": how often, "row": first row seen}]
    per_branch: dict[str, list[dict[str, Any]]] = {}
    for row in fail_url_rows(fail_url):
        if not is_version_branch(row):
            continue
        branch = str(row.get("branch", ""))
        normalized = normalize_failure_text(str(row.get("failure_text", "")))
        signatures = per_branch.setdefault(branch, [])
        signature = matching_signature(signatures, normalized)
        if signature is not None:
            signature["count"] += 1
        else:
            # The first row of a signature both represents it and is what gets reported
            signatures.append({"text": normalized, "count": 1, "row": row})

    branches: dict[str, dict[str, Any]] = {}
    for branch, signatures in sorted(per_branch.items()):
        # sorted() is stable, so equally frequent signatures stay in the order seen
        ranked = sorted(signatures, key=lambda signature: signature["count"], reverse=True)
        branches[branch] = {
            "failure_count": sum(signature["count"] for signature in ranked),
            "distinct_failure_texts": [
                distinct_failure_record(signature["row"]) for signature in ranked
            ],
        }
    return branches


def distinct_failure_record(row: dict[str, Any]) -> dict[str, Any]:
    """One distinct failure, reported as the first row that showed that signature. The
    masking only decides which rows count as the same failure - the row is reported as
    the API returned it, raw failure_text included."""
    return {field: row.get(field, "") for field in DISTINCT_FAILURE_FIELDS}


def top_fail_tests_list(
    counts: Counter,
    until_date: str,
    from_date: str | None,
    limit: int = TOP_FAIL_TESTS_COUNT,
) -> list[dict[str, Any]]:
    """Same ranking as top_fail_tests(), as an array of records instead of a mapping. The
    counts it is given cover version-like branches only (see is_version_branch), so every
    entry has a non-empty per-branch breakdown."""
    return [
        {
            "test_name": test_name,
            "fail_count": fail_count,
            "fail_url": fail_url_for(test_name, until_date, from_date),
        }
        for test_name, fail_count in counts.most_common(limit)
    ]


class ApiError(RuntimeError):
    """An API request the server answered with an error. Still a RuntimeError, like every
    other failure of fetch_json(), so the callers' 'except RuntimeError' catches it; it also
    keeps the HTTP status and whether the cause was a spent rate limit, for the callers that
    act on those (a 404 from GitHub means there is no such branch, a spent quota means no
    later request of the run will get through either)."""

    def __init__(
        self, message: str, status: int | None = None, rate_limited: bool = False
    ) -> None:
        super().__init__(message)
        self.status = status
        self.rate_limited = rate_limited


def fetch_page(base_url: str, params: dict[str, Any]) -> list[dict[str, Any]]:
    return fetch_json(f"{base_url}?{urlencode(params)}")


def fetch_json(
    url: str, headers: dict[str, str] | None = None, expect: type = list
) -> Any:
    """One API request, retried on a timeout or a transport error. Every failure mode ends
    up as a RuntimeError: a bare TimeoutError from the socket read is not a URLError, so
    without this it would escape the callers' 'except RuntimeError' and abort the report.
    The buildbot API answers with a JSON list; Jira and GitHub's compare answer with an
    object, which is what 'expect' is for."""
    request = Request(url, headers={"Accept": "application/json", **(headers or {})})
    payload = None

    for attempt in range(1, REQUEST_ATTEMPTS + 1):
        # A stalled request is retried with a longer deadline rather than the same one
        timeout = REQUEST_TIMEOUT * attempt
        try:
            with urlopen(request, timeout=timeout) as response:
                charset = response.headers.get_content_charset() or "utf-8"
                payload = response.read().decode(charset)
            break
        except HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            if exc.headers.get("X-RateLimit-Remaining") == "0":
                # The quota is refilled on the hour; no backoff here gets a retry through
                raise ApiError(
                    f"API rate limit exhausted ({url}): {body}", exc.code, rate_limited=True
                ) from exc
            if exc.code not in RETRYABLE_HTTP_CODES or attempt == REQUEST_ATTEMPTS:
                raise ApiError(f"API returned HTTP {exc.code}: {body}", exc.code) from exc
            print(
                f"API returned HTTP {exc.code}, retrying in {RETRY_BACKOFF}s "
                f"[attempt {attempt}/{REQUEST_ATTEMPTS}]",
                file=sys.stderr,
            )
            time.sleep(RETRY_BACKOFF)
        except (TimeoutError, URLError) as exc:
            # URLError wraps a socket timeout on connect; TimeoutError is raised directly
            # once the connection is up and the response body is what times out
            reason = getattr(exc, "reason", exc) or exc
            if isinstance(exc, TimeoutError) or isinstance(reason, TimeoutError):
                reason = f"read timed out after {timeout}s"
            if attempt == REQUEST_ATTEMPTS:
                raise RuntimeError(
                    f"Could not reach API after {REQUEST_ATTEMPTS} attempts "
                    f"({url}): {reason}"
                ) from exc
            print(
                f"API request failed ({reason}), retrying in {RETRY_BACKOFF}s "
                f"[attempt {attempt}/{REQUEST_ATTEMPTS}]",
                file=sys.stderr,
            )
            time.sleep(RETRY_BACKOFF)

    if payload is None:
        # Not reachable: the last attempt either breaks with a payload or raises
        raise RuntimeError(f"No response from API: {url}")

    try:
        data = json.loads(payload)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"API returned invalid JSON: {exc}") from exc

    if not isinstance(data, expect):
        raise RuntimeError(
            f"Expected a JSON {expect.__name__} from API, got {type(data).__name__}"
        )

    return data


def parse_jira_date(value: str) -> datetime:
    """A Jira timestamp (2026-09-03T09:23:38.000+0000) as UTC. strptime rather than
    fromisoformat, which only takes a zone offset without a colon from Python 3.11 on."""
    return datetime.strptime(value, "%Y-%m-%dT%H:%M:%S.%f%z").astimezone(timezone.utc)


def github_date(value: datetime) -> str:
    return value.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def branch_sort_key(branch: str) -> tuple[int, int, int]:
    """Orders version-like branches the way a fix travels through them: oldest release first
    and 'main', which everything is merged up into, last."""
    if branch == "main":
        return (1, 0, 0)
    major, minor = branch.split(".")
    return (0, int(major), int(minor))


def fix_version_branches(fix_versions: list[str]) -> list[str]:
    """The release branches the Fix Version/s of a ticket point at, oldest first:
    ['10.11.20', '11.4.14', 'N/A'] -> ['10.11', '11.4']."""
    branches = set()
    for version in fix_versions:
        match = FIX_VERSION_REGEX.match(version)
        if match and VERSION_REGEX.match(match.group(1)):
            branches.add(match.group(1))
    return sorted(branches, key=branch_sort_key)


def jira_fixed_tickets(test_name: str) -> list[dict[str, Any]]:
    """The MDEVs resolved as Fixed in the last MERGE_LOOKBACK_DAYS that name a test in their
    summary, most recently resolved first. The name is searched as an exact phrase: JQL's
    plain 'text ~' splits it on the dots and underscores and ORs the pieces, which matches
    every ticket that merely shares a common word with it. Anonymous, read-only: MDEV is a
    public project.

    Precision matters more than recall here, as a test taken to have a fix leaves the ranking.
    So the summary only: a description that lists the test (an umbrella such as 'Tests failing
    on macOS') says nothing about whether the fix is for this test's failure. And the whole
    suite.test name only: the bare test name matches unrelated tickets, and the same test name
    in other suites. Measured on the most frequent failures of five suites, the description
    only added matches through one umbrella ticket (MDEV-33616), and the bare name only
    unrelated tickets: rename and partition matched on the common word, and tmp_space_usage
    matched a ticket about main.tmp_space_usage for galera.tmp_space_usage."""
    if not TEST_NAME_REGEX.match(test_name):
        # Not a name MTR would produce; keep it out of the query rather than escape it
        return []
    phrase = f'"\\"{test_name}\\""'
    jql = (
        f"project = MDEV AND resolution = Fixed AND resolved >= -{MERGE_LOOKBACK_DAYS}d "
        f"AND summary ~ {phrase} ORDER BY resolutiondate DESC"
    )
    params = {
        "jql": jql,
        "fields": "summary,created,resolutiondate,fixVersions",
        "maxResults": JIRA_MAX_RESULTS,
    }
    data = fetch_json(f"{JIRA_URL}/rest/api/2/search?{urlencode(params)}", expect=dict)

    tickets = []
    for issue in data.get("issues", []):
        fields = issue["fields"]
        if not fields.get("resolutiondate"):
            continue
        tickets.append(
            {
                "key": issue["key"],
                "summary": fields["summary"],
                "created": parse_jira_date(fields["created"]),
                "resolved": parse_jira_date(fields["resolutiondate"]),
                "fix_versions": [version["name"] for version in fields["fixVersions"]],
            }
        )
    return tickets


def github_json(path: str, params: dict[str, Any], expect: type) -> Any:
    """One request to the MariaDB/server repository. GITHUB_TOKEN (or GH_TOKEN) is optional
    and only there to lift the 60 requests an hour that anonymous clients get."""
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "mariadb-qa-build_mtr_test_failures_report",
    }
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    url = f"{GITHUB_API_URL}/repos/{GITHUB_REPO}/{path}?{urlencode(params)}"
    return fetch_json(url, headers=headers, expect=expect)


@lru_cache(maxsize=None)
def find_fix_commit(key: str, branch: str, since: str, until: str) -> dict[str, str] | None:
    """The newest commit on a branch, committed between since and until, whose subject line
    names the MDEV key; None if there is none. GitHub lists newest first, so the first hit is
    the last commit of the fix (a ticket can have follow-ups): a branch has the whole fix once
    it has that one. The subject only: a body that mentions a key is usually about something
    else, and 'MDEV-41017' must not match 'MDEV-410170', hence the lookahead."""
    key_regex = re.compile(rf"(?<![\w-]){re.escape(key)}(?!\d)")
    for page in range(1, FIX_COMMIT_PAGES + 1):
        commits = github_json(
            "commits",
            {
                "sha": branch,
                "since": since,
                "until": until,
                "per_page": GITHUB_PAGE_SIZE,
                "page": page,
            },
            list,
        )
        for commit in commits:
            subject = commit["commit"]["message"].split("\n", 1)[0]
            if key_regex.search(subject):
                return {
                    "branch": branch,
                    "sha": commit["sha"],
                    "date": commit["commit"]["committer"]["date"],
                    "url": f"https://github.com/{GITHUB_REPO}/commit/{commit['sha']}",
                    "subject": subject,
                }
        if len(commits) < GITHUB_PAGE_SIZE:
            return None
    raise RuntimeError(
        f"More than {FIX_COMMIT_PAGES * GITHUB_PAGE_SIZE} commits on {branch} between "
        f"{since} and {until}; the commit of {key} was not looked for any further"
    )


@lru_cache(maxsize=None)
def branch_contains(sha: str, branch: str) -> bool | None:
    """Whether a commit has been merged to a branch, i.e. is in its history. Comparing the
    commit with the branch tells: 'ahead' (the branch has gone on from the commit) and
    'identical' mean it is, 'diverged' (the branch went its own way) and 'behind' mean it is
    not. Jira's Fix Version/s cannot answer this: they are filled in when the fix is pushed,
    for every branch it is meant to reach, merged or not. None if there is no such branch."""
    try:
        comparison = github_json(
            f"compare/{sha}...{quote(branch, safe='')}", {"per_page": 1}, dict
        )
    except ApiError as exc:
        if exc.status == 404:
            return None
        raise
    return comparison.get("status") in ("ahead", "identical")


def fix_merge_state(
    ticket: dict[str, Any], failing_branches: set[str]
) -> dict[str, Any] | None:
    """Where the fix of a ticket has got to, for a test failing on failing_branches. None
    unless the fix is merged to some branches and the test fails on one that is yet to get it.

    The fix commit is searched for on the oldest branch of the ticket's Fix Version/s only: a
    fix is pushed there and merged up from there, and it is also the quietest branch to search.
    A fix with no commit under the MDEV's key there (a Galera library update, say) cannot be
    followed, and that is all the search costs. The branches that count are the Fix Version/s
    branches and the ones the test fails on, from that oldest one upwards, as a merge never
    goes down."""
    fix_branches = fix_version_branches(ticket["fix_versions"])
    if not fix_branches:
        return None
    origin = fix_branches[0]
    since = github_date(
        max(ticket["created"], ticket["resolved"] - timedelta(days=FIX_COMMIT_LOOKBACK_DAYS))
    )
    until = github_date(ticket["resolved"] + timedelta(days=FIX_COMMIT_SLACK_DAYS))

    try:
        fix_commit = find_fix_commit(ticket["key"], origin, since, until)
    except ApiError as exc:
        if exc.status == 404:
            return None  # the branch no longer exists
        raise
    if fix_commit is None:
        return None

    branches = sorted(
        {
            branch
            for branch in (*fix_branches, *failing_branches)
            if branch_sort_key(branch) > branch_sort_key(origin)
        },
        key=branch_sort_key,
    )
    if not branches:
        return None
    # A fix is merged up one branch at a time, so the highest branch having it means they all
    # do. That one request settles most tickets: the fix is old news, nothing is pending.
    if branch_contains(fix_commit["sha"], branches[-1]):
        return None

    merged, not_merged = [origin], []
    for branch in branches:
        has_fix = branch_contains(fix_commit["sha"], branch)
        if has_fix is None:
            continue  # no such branch
        (merged if has_fix else not_merged).append(branch)
    # A failure on a branch that has the fix is not explained by a merge still to come
    if not set(not_merged) & failing_branches:
        return None
    return {"fix_commit": fix_commit, "merged_to": merged, "not_merged_to": not_merged}


def not_merged_to_all_yet(
    entries: list[dict[str, Any]], sleep_seconds: float
) -> list[dict[str, Any]]:
    """The ranked tests whose MDEV is fixed but not merged to every branch yet: still failing
    on a branch the fix has not reached. One record per test and MDEV, made of the ranking
    entry of the test and what is known about the fix: the caller takes these tests out of
    the ranking, so the record keeps everything the entry had. A lookup that fails is reported
    and skipped, as with the per-branch lookups: it must not cost us the report."""
    reported: list[dict[str, Any]] = []
    for entry in entries:
        failing = set(entry["branches"])
        if not failing:
            continue
        try:
            tickets = jira_fixed_tickets(entry["test_name"])
        except RuntimeError as exc:
            print(f"Could not look up MDEVs for {entry['test_name']}: {exc}", file=sys.stderr)
            continue

        for ticket in tickets:
            try:
                state = fix_merge_state(ticket, failing)
            except RuntimeError as exc:
                print(
                    f"Could not check whether {ticket['key']} is merged to all branches "
                    f"yet: {exc}",
                    file=sys.stderr,
                )
                if isinstance(exc, ApiError) and exc.rate_limited:
                    print(
                        "Not checking any further; set GITHUB_TOKEN (or GH_TOKEN) to a "
                        "GitHub token to lift the limit",
                        file=sys.stderr,
                    )
                    return reported
                continue
            if state is None:
                continue
            reported.append(
                {
                    "test_name": entry["test_name"],
                    "fail_count": entry["fail_count"],
                    "fail_url": entry["fail_url"],
                    "mdev": {
                        "key": ticket["key"],
                        "url": f"{JIRA_URL}/browse/{ticket['key']}",
                        "summary": ticket["summary"],
                        "fix_versions": ticket["fix_versions"],
                    },
                    "fix_commit": state["fix_commit"],
                    "merged_to": state["merged_to"],
                    "not_merged_to": state["not_merged_to"],
                    "branches": entry["branches"],
                }
            )
        time.sleep(sleep_seconds)
    return reported


def row_identity(row: dict[str, Any]) -> tuple[Any, ...]:
    return (
        row.get("dt"),
        row.get("builder_name"),
        row.get("commit"),
        row.get("branch"),
        row.get("test_name"),
        row.get("test_variant"),
        row.get("failure_text"),
    )


def normalize_row(row: dict[str, Any]) -> dict[str, Any]:
    return {field: row.get(field, "") for field in CSV_FIELDS}


def write_html_header(
    html_file: Any,
    *,
    test_name: str,
    until_dt: datetime,
    from_dt: datetime | None,
    branch: str | None,
    builder: str | None,
    generated_at: datetime,
) -> None:
    title = f"Test failures for {test_name}"
    html_file.write(
        f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>{html.escape(title)}</title>
  <style>
    body {{
      margin: 0;
      color: #202124;
      background: #f7f8fa;
      font: 14px/1.45 system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }}
    header {{
      position: sticky;
      top: 0;
      z-index: 1;
      padding: 16px 24px;
      border-bottom: 1px solid #d8dde6;
      background: #ffffff;
    }}
    h1 {{
      margin: 0 0 6px;
      font-size: 20px;
      font-weight: 650;
    }}
    .meta {{
      color: #5f6368;
      font-size: 13px;
    }}
    main {{
      padding: 16px 24px 32px;
    }}
    details {{
      margin: 0 0 10px;
      border: 1px solid #d8dde6;
      border-radius: 6px;
      background: #ffffff;
    }}
    details[open] {{
      border-color: #aeb7c4;
    }}
    summary {{
      display: grid;
      grid-template-columns: minmax(160px, 220px) minmax(120px, 1fr) minmax(80px, 110px) minmax(180px, 1.4fr);
      gap: 12px;
      padding: 10px 12px;
      cursor: pointer;
      align-items: center;
    }}
    summary::-webkit-details-marker {{
      display: none;
    }}
    .summary-cell {{
      overflow-wrap: anywhere;
    }}
    .label {{
      display: block;
      color: #6f7782;
      font-size: 11px;
      text-transform: uppercase;
    }}
    .value {{
      font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, "Liberation Mono", monospace;
    }}
    .detail-body {{
      border-top: 1px solid #e6e9ef;
      padding: 12px;
    }}
    dl {{
      display: grid;
      grid-template-columns: 120px minmax(0, 1fr);
      gap: 6px 12px;
      margin: 0 0 12px;
    }}
    dt {{
      color: #6f7782;
    }}
    dd {{
      margin: 0;
      overflow-wrap: anywhere;
    }}
    pre {{
      margin: 0;
      padding: 12px;
      overflow: auto;
      max-height: 70vh;
      border: 1px solid #d8dde6;
      border-radius: 4px;
      background: #101418;
      color: #eef2f6;
      white-space: pre-wrap;
      overflow-wrap: anywhere;
      font: 12px/1.45 ui-monospace, SFMono-Regular, Menlo, Consolas, "Liberation Mono", monospace;
    }}
    @media (max-width: 760px) {{
      header,
      main {{
        padding-left: 12px;
        padding-right: 12px;
      }}
      summary {{
        grid-template-columns: 1fr;
        gap: 6px;
      }}
      dl {{
        grid-template-columns: 1fr;
      }}
    }}
  </style>
</head>
<body>
  <header>
    <h1>{html.escape(title)}</h1>
    <div class="meta">
      Oldest requested date: {html.escape(format_api_date(until_dt))} |
      Newest requested date: {html.escape(format_api_date(from_dt)) if from_dt is not None else "latest"} |
      Branch: {html.escape(branch) if branch else "any"} |
      Builder: {html.escape(builder) if builder else "any"} |
      Generated at: {html.escape(format_api_date(generated_at))}
    </div>
  </header>
  <main>
"""
    )


def write_html_row(html_file: Any, row: dict[str, Any], row_number: int) -> None:
    normalized = normalize_row(row)
    escaped = {
        key: html.escape(str(value) if value is not None else "")
        for key, value in normalized.items()
    }
    title = (
        f"{escaped['dt']} | {escaped['branch']} | {escaped['builder_name']} | "
        f"{escaped['test_name']}"
    )
    html_file.write(
        f"""    <details>
      <summary aria-label="{title}">
        <span class="summary-cell"><span class="label">Date</span><span class="value">{escaped['dt']}</span></span>
        <span class="summary-cell"><span class="label">Test</span><span class="value">{escaped['test_name']}</span></span>
        <span class="summary-cell"><span class="label">Branch</span><span class="value">{escaped['branch']}</span></span>
        <span class="summary-cell"><span class="label">Builder</span><span class="value">{escaped['builder_name']}</span></span>
      </summary>
      <div class="detail-body">
        <dl>
          <dt>Row</dt><dd>{row_number}</dd>
          <dt>Commit</dt><dd><span class="value">{escaped['commit']}</span></dd>
          <dt>Variant</dt><dd><span class="value">{escaped['test_variant']}</span></dd>
          <dt>Info</dt><dd>{escaped['info_text']}</dd>
        </dl>
        <pre>{escaped['failure_text']}</pre>
      </div>
    </details>
"""
    )


def write_html_footer(html_file: Any, total: int) -> None:
    html_file.write(
        f"""  </main>
  <script>
    document.querySelector(".meta").insertAdjacentText("beforeend", " | Rows: {total}");
  </script>
</body>
</html>
"""
    )


def write_json_row(json_file: Any, row: dict[str, Any], *, is_first: bool) -> None:
    if not is_first:
        json_file.write(",\n")
    json.dump(normalize_row(row), json_file, ensure_ascii=False, indent=2)


def export_failures(
    base_url: str,
    test_name: str,
    until_dt: datetime,
    from_dt: datetime | None,
    branch: str | None,
    builder: str | None,
    csv_output_path: Path | None,
    html_output_path: Path | None,
    json_output_path: Path | None,
    sleep_seconds: float,
    all_seen: set[tuple[Any, ...]] | None = None,
    all_counts: Counter | None = None,
) -> tuple[int, Counter]:
    # all_seen/all_counts are shared by every --test-name filter of the run, so a row
    # matched by two overlapping filters is counted once across all suites (it is still
    # exported in full to the files of both filters). They only take failures on a
    # version-like branch; everything else is exported but left out of the ranking.
    max_dt = from_dt
    seen: set[tuple[Any, ...]] = set()
    total = 0
    counts: Counter = Counter()

    csv_file = None
    html_file = None
    json_file = None
    writer = None
    json_is_first_row = True

    try:
        if csv_output_path is not None:
            csv_output_path.parent.mkdir(parents=True, exist_ok=True)
            csv_file = csv_output_path.open("w", newline="", encoding="utf-8")
            writer = csv.DictWriter(csv_file, fieldnames=CSV_FIELDS)
            writer.writeheader()

        if html_output_path is not None:
            html_output_path.parent.mkdir(parents=True, exist_ok=True)
            html_file = html_output_path.open("w", encoding="utf-8")
            write_html_header(
                html_file,
                test_name=test_name,
                until_dt=until_dt,
                from_dt=from_dt,
                branch=branch,
                builder=builder,
                generated_at=datetime.utcnow(),
            )

        if json_output_path is not None:
            json_output_path.parent.mkdir(parents=True, exist_ok=True)
            json_file = json_output_path.open("w", encoding="utf-8")
            json_file.write("[\n")

        while True:
            params = {
                "test_name": test_name,
                "min_date": format_api_date(until_dt),
                "limit": MAX_LIMIT,
                "sort_order": "desc",
            }
            if branch:
                params["branch"] = branch
            if builder:
                params["builder_name"] = builder
            if max_dt is not None:
                params["max_date"] = format_api_date(max_dt)

            rows = fetch_page(base_url, params)
            if not rows:
                break

            rows_with_dt = []
            for row in rows:
                if "dt" not in row:
                    raise RuntimeError(
                        "API response does not include 'dt'. Deploy the API serializer "
                        "change from this repository before running the exporter."
                    )
                rows_with_dt.append((parse_api_date(str(row["dt"])), row))

            rows_with_dt.sort(key=lambda item: item[0], reverse=True)
            oldest_dt = rows_with_dt[-1][0]
            new_rows = 0

            for row_dt, row in rows_with_dt:
                if row_dt < until_dt:
                    continue

                identity = row_identity(row)
                if identity in seen:
                    continue

                seen.add(identity)
                total += 1
                new_rows += 1
                row_test_name = str(row.get("test_name", ""))
                counts[row_test_name] += 1
                # The pooled ranking only counts failures on a version-like branch, so a
                # test that only ever fails on a feature or pull-request branch does not
                # reach top_fail_tests_all_suites at all. The per-suite counts above, and
                # the exported files, still carry every row the filter matched.
                if is_version_branch(row) and all_seen is not None:
                    if identity not in all_seen:
                        all_seen.add(identity)
                        if all_counts is not None:
                            all_counts[row_test_name] += 1
                if writer is not None:
                    writer.writerow(normalize_row(row))
                if html_file is not None:
                    write_html_row(html_file, row, total)
                if json_file is not None:
                    write_json_row(json_file, row, is_first=json_is_first_row)
                    json_is_first_row = False

            ##print(
            ##    f"Fetched {len(rows):>3} rows, wrote {new_rows:>3} new rows, "
            ##    f"oldest page timestamp {format_api_date(oldest_dt)}",
            ##    file=sys.stderr,
            ##)

            if len(rows) < MAX_LIMIT or oldest_dt <= until_dt:
                break

            if new_rows == 0:
                oldest_dt = oldest_dt - timedelta(seconds=1)

            max_dt = oldest_dt
            time.sleep(sleep_seconds)

        if html_file is not None:
            write_html_footer(html_file, total)
        if json_file is not None:
            json_file.write("\n]\n")
    finally:
        if csv_file is not None:
            csv_file.close()
        if html_file is not None:
            html_file.close()
        if json_file is not None:
            json_file.close()

    return total, counts


def main() -> int:
    args = parse_args()

    test_names = split_test_names(args.test_name)
    if not test_names:
        print("--test-name must contain at least one test filter", file=sys.stderr)
        return 2

    explicit_outputs = (args.output, args.html_output, args.json_output)
    if len(test_names) > 1 and any(path is not None for path in explicit_outputs):
        print(
            "--output/--html-output/--json-output cannot be used with multiple "
            "--test-name filters; drop them to use the per-filter default paths",
            file=sys.stderr,
        )
        return 2

    try:
        until_dt = parse_api_date(args.until_date)
        from_dt = parse_api_date(args.from_date) if args.from_date else None
    except ValueError as exc:
        print(exc, file=sys.stderr)
        return 2

    if from_dt is not None and from_dt < until_dt:
        print("--from-date must be newer than or equal to --until-date", file=sys.stderr)
        return 2

    # Version-like-branch failure counts of every filter fetched in this run, pooled
    # across suites
    all_counts: Counter = Counter()
    all_seen: set[tuple[Any, ...]] = set()

    for test_name in test_names:
        default_csv_path = output_path_for(test_name, args.until_date)
        csv_output_path = args.output or default_csv_path
        html_output_path = args.html_output or html_path_for(csv_output_path)
        json_output_path = args.json_output or json_path_for(csv_output_path)

        if args.format == "csv":
            html_output_path = None
            json_output_path = None
        elif args.format == "html":
            csv_output_path = None
            json_output_path = None
        elif args.format == "json":
            csv_output_path = None
            html_output_path = None
        elif args.format == "both":
            json_output_path = None

        try:
            total, counts = export_failures(
                base_url=args.base_url,
                test_name=test_name,
                until_dt=until_dt,
                from_dt=from_dt,
                branch=args.branch,
                builder=args.builder,
                csv_output_path=csv_output_path,
                html_output_path=html_output_path,
                json_output_path=json_output_path,
                sleep_seconds=args.sleep,
                all_seen=all_seen,
                all_counts=all_counts,
            )
        except RuntimeError as exc:
            print(exc, file=sys.stderr)
            return 1

        outputs = [
            str(path)
            for path in (csv_output_path, html_output_path, json_output_path)
            if path is not None
        ]
        print(
            f"Wrote {total} rows for {test_name} to {', '.join(outputs)}",
            file=sys.stderr,
        )

        # Per-suite report, one per --test-name filter
        final_rpt = dict()
        final_rpt['top_fail_tests'] = top_fail_tests(counts)
        final_rpt['unique_fail_tests'] = sorted(counts)
        print(json.dumps(final_rpt))

    print("\nTop failing tests pooled across every suite fetched in this run\n")
    top_all_suites = top_fail_tests_list(all_counts, args.until_date, args.from_date)
    for entry in top_all_suites:
        try:
            entry['branches'] = branch_failures(entry['fail_url'])
        except RuntimeError as exc:
            # A per-branch lookup failing must not cost us the whole report
            print(f"Could not fetch {entry['fail_url']}: {exc}", file=sys.stderr)
            entry['branches'] = {}
        time.sleep(args.sleep)
    try:
        not_merged = not_merged_to_all_yet(top_all_suites, args.sleep)
    except Exception as exc:
        # The ranking took the whole run to build: an unexpected reply from Jira or GitHub
        # must not cost us that. Nothing is taken out of it then.
        print(f"Could not work out not_merged_to_all_yet: {exc!r}", file=sys.stderr)
        not_merged = []
    # A test with a fix on its way is reported as that, not as one of the top failing tests.
    # The ranking is not refilled: it is the top tests minus these, so it can come up short.
    not_merged_tests = {record['test_name'] for record in not_merged}
    top_all_suites = [
        entry for entry in top_all_suites if entry['test_name'] not in not_merged_tests
    ]
    print(
        json.dumps(
            {
                'top_fail_tests_all_suites': top_all_suites,
                'not_merged_to_all_yet': not_merged,
            },
            indent=4,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
