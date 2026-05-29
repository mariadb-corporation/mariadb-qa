#!/usr/bin/env python3
"""
compare.py — run every SELECT in a MariaDB MTR .test file against both
MariaDB (live, via socket or TCP) and PostgreSQL, translating the SQL
where dialects diverge, and write a side-by-side diff report.

Usage:  compare.py --test PATH --mariadb-socket PATH ... [other options]
See `compare.py --help` for the full CLI.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import List, Optional, Set

SECTION_RE = re.compile(r"^--echo # Section (\d+):")


# --------------------------------------------------------------------------
# Config
# --------------------------------------------------------------------------

@dataclass
class Config:
    """Every knob the runner needs.  Built from CLI args in main() and
    threaded through the helpers, so the module stays free of globals
    for paths and connection settings."""
    test_file: Path
    report: Path
    report_title: str
    sections: Optional[Set[int]]            # None = include everything
    dump_scripts_dir: Optional[Path]
    fresh: bool
    reset: bool

    # MariaDB connection
    mariadb_client: Path
    mariadb_db: str
    mariadb_socket: Optional[Path]
    mariadb_host: Optional[str]
    mariadb_port: Optional[int]
    mariadb_user: Optional[str]

    # PostgreSQL connection (passed to psql).  --pg-host accepts either a
    # hostname or a /path-style UNIX socket directory; psql interprets a
    # leading slash as the latter.
    pg_bin: Path
    pg_db: str
    pg_host: Optional[str]
    pg_port: Optional[int]
    pg_user: Optional[str]


# --------------------------------------------------------------------------
# Parser
# --------------------------------------------------------------------------

@dataclass
class Block:
    """One SQL statement plus the directives that prefix it."""
    section: int
    lineno: int
    sql: str                       # MariaDB dialect (verbatim from file)
    directives: List[str] = field(default_factory=list)
    comment: str = ""              # Nearest preceding --echo # comment

    @property
    def expect_error(self) -> bool:
        return any(d.startswith("--error") for d in self.directives)

    @property
    def kind(self) -> str:
        """Classify the statement for the comparison driver."""
        s = self.sql.lower().lstrip()
        if s.startswith("select") or s.startswith("with") or s.startswith("("):
            return "select"
        if s.startswith("explain") or s.startswith("show"):
            return "explain"
        return "other"


def parse_test_file(path: Path, sections: Optional[set] = None) -> List[Block]:
    """Read the .test file and yield one Block per SQL statement."""
    blocks: List[Block] = []
    current_section = 0
    pending_directives: List[str] = []
    pending_comment = ""
    cur_sql: List[str] = []
    cur_start = 0
    delimiter = ";"

    lines = path.read_text().splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        # Section tracking
        m = SECTION_RE.match(line)
        if m:
            current_section = int(m.group(1))

        # Section filter
        if sections and current_section not in sections and current_section != 0:
            i += 1
            continue

        # MTR directives
        if stripped.startswith("--"):
            pending_directives.append(stripped)
            if stripped.startswith("--echo"):
                # Capture the most recent --echo as human context, but skip
                # decorative divider lines (e.g. "===== ... =====").
                txt = stripped[len("--echo"):].lstrip("# ").strip()
                if txt and not re.fullmatch(r"=+", txt):
                    pending_comment = txt
            if stripped.lower().startswith("delimiter"):
                # Legacy in-line DELIMITER (unused in full_join.test; supported below)
                pass
            i += 1
            continue

        # Whole-line # comments
        if stripped.startswith("#"):
            i += 1
            continue

        # Blank line
        if not stripped:
            i += 1
            continue

        # DELIMITER directive (also supported without leading `--`).
        # Form: `delimiter <new><current>` — strip the current delimiter
        # from the end of the token to recover <new>.
        m = re.match(r"^delimiter\s+(.+?)\s*$", stripped, re.I)
        if m:
            new_d = m.group(1)
            if new_d.endswith(delimiter):
                new_d = new_d[: -len(delimiter)] or delimiter
            delimiter = new_d
            i += 1
            continue

        # Gather up to current delimiter
        if not cur_sql:
            cur_start = i + 1
        cur_sql.append(line)
        joined = "\n".join(cur_sql)
        # Statement terminator check — delimiter must be at end, ignoring
        # trailing whitespace.
        if joined.rstrip().endswith(delimiter):
            # Strip trailing delimiter
            sql = joined.rstrip()
            sql = sql[: -len(delimiter)].rstrip()
            if sql:
                blocks.append(Block(
                    section=current_section,
                    lineno=cur_start,
                    sql=sql,
                    directives=pending_directives,
                    comment=pending_comment,
                ))
            cur_sql = []
            pending_directives = []
        i += 1

    return blocks


# --------------------------------------------------------------------------
# Translator (MariaDB -> PostgreSQL)
# --------------------------------------------------------------------------

@dataclass
class Translation:
    sql: str
    notes: List[str] = field(default_factory=list)   # Known-diff tags
    skip: bool = False                               # Do not send to PG at all


def _split_top_level(s: str, sep: str = ",") -> List[str]:
    """Split s on sep at paren-depth 0.  Used to walk a CREATE TABLE body
    so that commas inside type definitions like varchar(10) don't break
    the column / constraint list."""
    parts: List[str] = []
    depth = 0
    cur: List[str] = []
    for c in s:
        if c == "(":
            depth += 1
            cur.append(c)
        elif c == ")":
            depth -= 1
            cur.append(c)
        elif c == sep and depth == 0:
            parts.append("".join(cur))
            cur = []
        else:
            cur.append(c)
    if cur:
        parts.append("".join(cur))
    return parts


_CT_HEAD_RE = re.compile(
    r"\s*create\s+table\s+(?:if\s+not\s+exists\s+)?(\w+)\s*\(",
    re.I,
)
_KEY_PART_RE = re.compile(
    r"^(?P<u>unique\s+)?(?:key|index)(?:\s+(?P<n>\w+))?\s*\((?P<c>.+)\)\s*$",
    re.I | re.S,
)
# Matches a bare VECTOR(col[,col...]) index clause inside CREATE TABLE.
# MariaDB lets you declare a vector index with just `vector(v)`, with no
# operator class.  pgvector needs `USING hnsw|ivfflat (v op_class)`, so
# we can't translate this one-to-one.  The index has no semantic effect
# on FULL JOIN result rows, so we drop the clause.
_VECTOR_INDEX_RE = re.compile(r"^vector\s*\(.+\)\s*$", re.I | re.S)


def _rewrite_create_table_indexes(sql: str, notes: List[str]) -> str:
    """Extract [UNIQUE] KEY/INDEX [name] (cols) clauses from a CREATE TABLE
    body into separate CREATE [UNIQUE] INDEX statements appended after the
    CREATE TABLE.  Returns the (possibly multi-statement) SQL.  PRIMARY
    KEY constraints are left in place because PG accepts that syntax."""
    head_m = _CT_HEAD_RE.match(sql)
    if not head_m:
        return sql
    table_name = head_m.group(1)
    body_start = head_m.end()                # Just after the opening paren

    # Find the matching closing paren by counting depth, so nested parens
    # in column types like varchar(10) don't confuse us.
    depth = 1
    i = body_start
    while i < len(sql) and depth > 0:
        c = sql[i]
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
        i += 1
    if depth != 0:
        return sql
    body_end = i - 1                         # Position of closing paren
    head = sql[:body_start]                  # Including the opening paren
    body = sql[body_start:body_end]
    tail = sql[body_end + 1:]                # Anything after the close paren

    kept: List[str] = []
    indexes: List[tuple] = []                # (is_unique, name_or_None, cols)
    dropped_vec = 0
    for part in _split_top_level(body):
        stripped = part.strip()
        m = _KEY_PART_RE.match(stripped)
        if m:
            indexes.append((bool(m.group("u")), m.group("n"),
                            m.group("c").strip()))
        elif _VECTOR_INDEX_RE.match(stripped):
            dropped_vec += 1
        else:
            kept.append(part)

    if not indexes and not dropped_vec:
        return sql

    new_ct = f"{head}{','.join(kept)}){tail}"
    stmts = [new_ct]
    named = 0
    synth = 0
    for is_unique, idx_name, cols in indexes:
        if idx_name is None:
            synth += 1
            idx_name = f"{table_name}_idx_{synth}"
        else:
            named += 1
        kw = "unique index" if is_unique else "index"
        stmts.append(f"create {kw} {idx_name} on {table_name}({cols})")

    if named:
        notes.append(f"extracted {named} named KEY/INDEX clause(s) "
                     f"to CREATE INDEX")
    if synth:
        notes.append(f"extracted {synth} unnamed KEY/INDEX clause(s) "
                     f"to CREATE INDEX (synthesized names)")
    if dropped_vec:
        notes.append(f"dropped {dropped_vec} VECTOR(...) index clause(s) "
                     f"(pgvector needs explicit USING + operator class)")
    return ";\n".join(stmts)


def translate_for_pg(sql: str) -> Translation:
    out = sql
    notes: List[str] = []

    # MariaDB's STRAIGHT_JOIN is a join-order hint with no PG analogue.
    # It appears in two shapes:
    #   1.  As a SELECT modifier (`SELECT STRAIGHT_JOIN ...`).  Drop the
    #       keyword outright; PG ignores join-order hints anyway.
    #   2.  As a join keyword between two tables (`t1 STRAIGHT_JOIN t2`),
    #       behaving like INNER JOIN with the join order fixed.  Rewrite
    #       to plain JOIN — PG can't honor the order constraint, but the
    #       result rows are identical.
    # The SELECT pass runs first so the modifier form is consumed before
    # the catch-all rewrites any remaining occurrences to JOIN.
    out2, n = re.subn(r"(\bselect)\s+straight_join\b", r"\1", out, flags=re.I)
    if n:
        notes.append(f"dropped {n} STRAIGHT_JOIN keyword(s) after SELECT")
        out = out2
    out2, n = re.subn(r"\bstraight_join\b", "join", out, flags=re.I)
    if n:
        notes.append(f"STRAIGHT_JOIN -> JOIN as join keyword ({n})")
        out = out2

    # MariaDB lets `[INNER] JOIN` omit ON; PG requires it.  Per Dave's hint,
    # rewrite "JOIN <table>" with no ON to "JOIN <table> ON TRUE".
    # Skip when preceded by natural/full/left/right/outer (those have their
    # own join semantics) or when the next token IS already ON.
    JOIN_PRE_SKIP = {"natural", "full", "left", "right", "outer"}
    join_pat = re.compile(
        r"((?:inner\s+|cross\s+)?join\s+\w+)([\s)])",
        re.I,
    )
    def fix_join(orig):
        result = []
        last = 0
        added = 0
        for m in join_pat.finditer(orig):
            # Look at the token immediately before this match.
            pre_text = orig[:m.start()].rstrip()
            pre_tok = re.split(r"\s+", pre_text)[-1].lower() if pre_text else ""
            if pre_tok in JOIN_PRE_SKIP:
                continue
            # Look at what follows the join-and-table.
            tail = orig[m.end():].lstrip()
            next_tok = re.match(r"(\w+|\)|;)", tail)
            if next_tok and next_tok.group(1).lower() == "on":
                continue
            # Insert " on true" between m.group(1) and the trailing whitespace/paren.
            result.append(orig[last:m.start()])
            result.append(m.group(1))
            result.append(" on true")
            result.append(m.group(2))
            last = m.end()
            added += 1
        if added == 0:
            return orig, 0
        result.append(orig[last:])
        return "".join(result), added

    new_out, added = fix_join(out)
    if added:
        notes.append(f"added ON TRUE to {added} bare JOIN(s)")
        out = new_out

    # MariaDB allows bare-join shorthand inside parens: `(t2 join t3)`.
    # PG rejects this without an ON.  These appear only as cross products
    # in our tests, so rewrite to CROSS JOIN.
    out2, n = re.subn(r"\((\s*\w+\s+)join(\s+\w+\s*)\)", r"(\1cross join\2)", out, flags=re.I)
    if n:
        notes.append(f"(t join t) -> (t cross join t) ({n})")
        out = out2

    # MariaDB's comma operator inside parens is shorthand for CROSS JOIN
    # at the join scope: `(A, B) FULL JOIN C` parses as
    # `(A CROSS JOIN B) FULL JOIN C`.  PG rejects a parenthesised comma
    # list of table references in FROM, so rewrite to explicit CROSS
    # JOINs.  We only fire when a JOIN keyword follows the closing paren
    # so we don't disturb INSERT column lists, row constructors, or
    # function-argument lists that happen to have the same shape.
    def _comma_to_cross(m):
        parts = [p.strip() for p in m.group(1).split(",")]
        return "(" + " cross join ".join(parts) + ")"
    out2, n = re.subn(
        r"\(\s*(\w+(?:\s*,\s*\w+)+)\s*\)"
        r"(?=\s*(?:full|left|right|inner|cross|natural|outer|join)\b)",
        _comma_to_cross,
        out,
        flags=re.I,
    )
    if n:
        notes.append(f"comma operator (A,B) -> (A CROSS JOIN B) ({n})")
        out = out2

    # MariaDB lets `CROSS JOIN ... ON cond`; PG forbids that.  Rewrite to
    # `INNER JOIN ... ON cond`.  Restrict the (.*?) to non-paren chars so
    # we don't span across a parenthesised join.
    out2, n = re.subn(r"\bcross\s+join\b([^()]*?)\bon\b", r"inner join\1on", out,
                      flags=re.I | re.S)
    if n:
        notes.append(f"CROSS JOIN ... ON -> INNER JOIN ... ON ({n})")
        out = out2

    # MariaDB quotes identifiers with backticks; PG uses double quotes.
    if "`" in out:
        out = out.replace("`", '"')
        notes.append("backtick identifier quoting -> double quotes")

    # MariaDB's NULL-safe equality <=> -> PG's IS NOT DISTINCT FROM.
    # Restricted to simple `expr <=> expr` to keep the regex honest.
    def repl_null_safe(m):
        notes.append("<=> rewritten as IS NOT DISTINCT FROM")
        return f"({m.group(1).strip()} IS NOT DISTINCT FROM {m.group(2).strip()})"

    # Match "X <=> Y" where X and Y are simple terms (table.col, col, NULL, literal).
    out = re.sub(
        r"([A-Za-z_][A-Za-z0-9_.]*)\s*<=>\s*([A-Za-z_][A-Za-z0-9_.]*|NULL)",
        repl_null_safe,
        out,
        flags=re.IGNORECASE,
    )

    # MariaDB spells boolean literals `true`/`false`; PG accepts both.
    # Nothing to do.

    # Strip ENGINE=<x>
    if re.search(r"\bengine\s*=\s*\w+", out, re.I):
        out = re.sub(r"\s*\bengine\s*=\s*\w+", "", out, flags=re.I)
        notes.append("stripped ENGINE= clause")

    # MariaDB lets KEY [name] (cols) live inside CREATE TABLE; PG rejects
    # the syntax.  Extract each [UNIQUE] KEY/INDEX [name] (cols) clause out
    # of the CREATE TABLE body into a separate CREATE [UNIQUE] INDEX
    # statement that runs right after.  PRIMARY KEY is left in place.
    if out.lower().lstrip().startswith("create table"):
        out = _rewrite_create_table_indexes(out, notes)

    # AUTO_INCREMENT -> GENERATED ALWAYS AS IDENTITY (only when attached to PK column).
    if re.search(r"\bauto_increment\b", out, re.I):
        out = re.sub(
            r"\bauto_increment\b",
            "generated always as identity",
            out,
            flags=re.I,
        )
        notes.append("AUTO_INCREMENT -> GENERATED ALWAYS AS IDENTITY")

    # GROUP_CONCAT(x [ORDER BY y]) -> STRING_AGG(x::text, ',' [ORDER BY y])
    def repl_gc(m):
        inner = m.group(1)
        notes.append("GROUP_CONCAT -> STRING_AGG")
        # If ORDER BY appears, keep it; otherwise add a plain separator
        if re.search(r"\border\s+by\b", inner, re.I):
            return f"string_agg(({inner.split(' order by ', 1)[0]})::text, ',' order by {inner.split(' order by ', 1)[1]})"
        return f"string_agg(({inner})::text, ',')"
    out = re.sub(r"group_concat\((.*?)\)", repl_gc, out, flags=re.I | re.S)

    # MariaDB sequence engine -> PG generate_series.  The Sequence engine
    # exposes virtual tables named seq_<from>_to_<to>[_step_<step>] with a
    # single column called seq.  PG has no such engine; the equivalent set-
    # returning function is generate_series(start, stop[, step]).  Alias
    # the result as s(seq) so existing column references still resolve.
    def _seq_sub(m):
        a = int(m.group(1))
        b = int(m.group(2))
        step = m.group(3)
        if step is not None:
            args = f"{a}, {b}, {int(step)}"
        elif a > b:
            # MariaDB auto-flips the step for descending ranges; PG does not.
            args = f"{a}, {b}, -1"
        else:
            args = f"{a}, {b}"
        return f"generate_series({args}) as s(seq)"
    out2, n = re.subn(
        r"\bseq_(-?\d+)_to_(-?\d+)(?:_step_(-?\d+))?\b",
        _seq_sub,
        out,
        flags=re.I,
    )
    if n:
        notes.append(f"seq_X_to_Y -> generate_series(...) as s(seq) ({n})")
        out = out2

    # MariaDB vector type and conversion functions -> pgvector equivalents.
    # MariaDB:  v VECTOR(N), vec_fromtext('[1,0]'), vec_totext(v)
    # pgvector: v vector(N), '[1,0]'::vector,       v::text
    # The VECTOR(N) column type spelling is already identical, so no
    # rewrite is needed there.
    out2, n = re.subn(
        r"\bvec_fromtext\s*\(\s*('[^']*')\s*\)",
        r"\1::vector",
        out,
        flags=re.I,
    )
    if n:
        notes.append(f"vec_fromtext('...') -> '...'::vector ({n})")
        out = out2
    out2, n = re.subn(
        r"\bvec_totext\s*\(\s*([^()]+?)\s*\)",
        r"(\1)::text",
        out,
        flags=re.I,
    )
    if n:
        notes.append(f"vec_totext(expr) -> (expr)::text ({n})")
        out = out2

    # Any statement that touches a vector type, vector index spec, or one
    # of the vector conversion functions needs the pgvector extension
    # loaded.  Inspect the ORIGINAL input (before the rewrites above
    # erased the vec_* function names) and prepend a
    # CREATE EXTENSION IF NOT EXISTS so the statement is self-contained;
    # the idempotent form makes prepending on every vector-using
    # statement harmless.
    if re.search(r"\bvector\s*\(|\bvec_fromtext\b|\bvec_totext\b",
                 sql, re.I):
        out = "create extension if not exists vector;\n" + out
        notes.append("loaded pgvector extension")

    # SET @foo = ... — not supported in PG the same way; skip silently.
    # PREPARE/EXECUTE/DEALLOCATE — syntax differs; Phase 1 doesn't touch these.
    # DELIMITER and CREATE PROCEDURE — not in Phase 1 scope.

    # TRUNCATE <table> (no TABLE keyword) — PG accepts both; no change needed.

    return Translation(sql=out, notes=notes)


# --------------------------------------------------------------------------
# Execution
# --------------------------------------------------------------------------

def _mariadb_cmd(cfg: Config, db: Optional[str] = None) -> List[str]:
    """Build a MariaDB client invocation for the configured connection."""
    cmd = [str(cfg.mariadb_client), "--batch", "--skip-column-names"]
    if cfg.mariadb_socket:
        cmd.append(f"--socket={cfg.mariadb_socket}")
    if cfg.mariadb_host:
        cmd.append(f"--host={cfg.mariadb_host}")
    if cfg.mariadb_port is not None:
        cmd.append(f"--port={cfg.mariadb_port}")
    if cfg.mariadb_user:
        cmd.append(f"--user={cfg.mariadb_user}")
    if db is not None:
        cmd.append(db)
    return cmd


def _psql_cmd(cfg: Config, db: Optional[str] = None) -> List[str]:
    """Build a psql invocation for the configured connection."""
    cmd = [
        str(cfg.pg_bin),
        "-q", "-A", "-t",
        "-F", "\t",
        "--pset=null=NULL",
        "-v", "ON_ERROR_STOP=0",
    ]
    cmd.extend(["-d", db if db is not None else cfg.pg_db])
    if cfg.pg_user:
        cmd.extend(["-U", cfg.pg_user])
    if cfg.pg_host:
        cmd.extend(["-h", cfg.pg_host])
    if cfg.pg_port is not None:
        cmd.extend(["-p", str(cfg.pg_port)])
    return cmd


def run_mariadb_block(cfg: Config, sql: str) -> dict:
    r = subprocess.run(_mariadb_cmd(cfg, db=cfg.mariadb_db),
                       input=sql + ";\n", capture_output=True, text=True)
    return {
        "rows": [ln for ln in (r.stdout or "").splitlines() if ln != ""],
        "errors": [ln for ln in (r.stderr or "").splitlines() if ln.strip()],
        "rc": r.returncode,
    }


def run_postgres_block(cfg: Config, sql: str) -> dict:
    r = subprocess.run(_psql_cmd(cfg), input=sql + ";\n",
                       capture_output=True, text=True)
    rows = [ln for ln in (r.stdout or "").splitlines() if ln != ""]
    # psql prints NOTICE/WARNING/ERROR/HINT etc. on stderr.
    errors = [ln for ln in (r.stderr or "").splitlines()
              if ln.strip() and not ln.startswith("NOTICE")]
    return {"rows": rows, "errors": errors, "rc": r.returncode}


# --------------------------------------------------------------------------
# Reset
# --------------------------------------------------------------------------

def reset_mariadb(cfg: Config) -> None:
    """Drop and recreate the target database on MariaDB."""
    sql = (f"drop database if exists {cfg.mariadb_db};\n"
           f"create database {cfg.mariadb_db};\n")
    # Connect without a default database, since we're about to drop it.
    r = subprocess.run(_mariadb_cmd(cfg), input=sql,
                       capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"error: MariaDB reset failed: {(r.stderr or '').strip()}")


def reset_postgres(cfg: Config) -> None:
    """Drop and recreate the public schema in the target PG database."""
    sql = "drop schema if exists public cascade;\ncreate schema public;\n"
    r = subprocess.run(_psql_cmd(cfg), input=sql,
                       capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"error: PostgreSQL reset failed: {(r.stderr or '').strip()}")


# --------------------------------------------------------------------------
# Differ
# --------------------------------------------------------------------------

ORDER_BY_RE = re.compile(r"\border\s+by\b", re.I)


def has_order_by(sql: str) -> bool:
    """Trivial heuristic: ORDER BY appears in the statement."""
    # Strip string literals so 'order by' in data doesn't fool us.
    sanitized = re.sub(r"'[^']*'", "", sql)
    return bool(ORDER_BY_RE.search(sanitized))


def canonicalize(rows: List[str], sort: bool) -> List[str]:
    rows = [r for r in rows if r != ""]
    return sorted(rows) if sort else rows


@dataclass
class Result:
    """The outcome of comparing one SELECT between MariaDB and PostgreSQL.

    A Result is produced for every comparable SELECT, whether it matches
    or not.  The `setup_m` / `setup_p` lists are the DDL/DML statements
    that established the current database state (since the last DROP),
    included so each entry is self-contained for manual replay.
    """
    block: Block
    index: int
    translation: Translation
    m_rows: List[str]
    p_rows: List[str]
    m_err: List[str]
    p_err: List[str]
    setup_m: List[str]             # MariaDB setup DDL/DML
    setup_p: List[str]             # PostgreSQL setup DDL/DML (translated)
    classification: str = "matches"

    @property
    def is_match(self) -> bool:
        return (not self.m_err
                and not self.p_err
                and self.m_rows == self.p_rows)

    def classify(self) -> str:
        if self.is_match:
            return "matches"
        for e in self.p_err:
            if "FULL JOIN is only supported with merge-joinable" in e:
                return "expected: PG only supports equi-condition FULL JOIN"
            if "must appear in the GROUP BY clause" in e:
                return "expected: PG enforces strict GROUP BY"
            if "operator does not exist" in e and (
                "integer = character varying" in e
                or "character varying = integer" in e
            ):
                return "expected: PG strict typing (no implicit int<->varchar)"
            if "syntax error" in e:
                return "translator: PG syntax error after rewrite"
        # Decimal-precision-only differences (MariaDB X.0000 vs PG X.000…0)
        if (len(self.m_rows) == len(self.p_rows)
                and not self.m_err and not self.p_err
                and self._numeric_precision_only()):
            return "expected: decimal precision formatting"
        # Case-only string comparison differences (collation).  Catches
        # the easy case where row sets only differ in letter casing.
        if (not self.m_err and not self.p_err
                and self._case_collation_only()):
            return "expected: collation (MariaDB default is case-insensitive)"
        # Author-annotated hint: a test author can tag a query's
        # preceding --echo comment with one of the recognised phrases
        # below to mark it as a known dialect difference that the
        # value-based heuristics above cannot detect on their own.
        # See README.md "Author-annotated expected hints" for the
        # current vocabulary.
        comment = (self.block.comment or "").lower()
        if "case-sensitive match depends on collation" in comment:
            return "expected: collation (MariaDB default is case-insensitive)"
        return "semantic"

    def _numeric_precision_only(self) -> bool:
        # Treat rows as equal if they match after collapsing trailing zeros
        # in numeric-looking fields.
        def norm(rows):
            out = []
            for r in rows:
                cells = []
                for c in r.split("\t"):
                    if re.fullmatch(r"-?\d+\.\d+", c):
                        c = c.rstrip("0").rstrip(".")
                    cells.append(c)
                out.append("\t".join(cells))
            return sorted(out)
        return norm(self.m_rows) == norm(self.p_rows)

    def _case_collation_only(self) -> bool:
        # Compare lowercased rows.
        norm = lambda rows: sorted(r.lower() for r in rows)
        return norm(self.m_rows) == norm(self.p_rows)


DROP_TABLE_RE = re.compile(r"^\s*drop\s+table\b", re.I)


def compare(cfg: Config, blocks: List[Block]) -> tuple:
    """Run each block on both engines and return (results, total_selects).

    `results` contains a Result for every comparable SELECT, matching or
    not.  The setup DDL/DML that established the table state for each
    SELECT is snapshotted in the Result for self-contained reporting.
    The setup buffer is cleared after a DROP TABLE so a query's setup
    list reflects only the tables it can actually see.
    """
    results: List[Result] = []
    selects = 0
    setup_m: List[str] = []        # MariaDB-dialect setup, accumulated
    setup_p: List[str] = []        # PG-dialect setup, accumulated
    for idx, b in enumerate(blocks):
        tr = translate_for_pg(b.sql)
        if b.expect_error:
            continue                                    # Skip --error blocks.
        if b.kind == "explain":
            continue                                    # Skip EXPLAIN.

        m_res = run_mariadb_block(cfg, b.sql)
        p_res = {"rows": [], "errors": ["skipped"], "rc": -1} if tr.skip \
                else run_postgres_block(cfg, tr.sql)

        if b.kind != "select":
            # Non-SELECT statement — contribute to setup unless it's a
            # DROP TABLE, in which case it terminates the current setup
            # scope (tables listed no longer exist).
            if DROP_TABLE_RE.match(b.sql):
                setup_m = []
                setup_p = []
            else:
                setup_m.append(b.sql)
                setup_p.append(tr.sql if not tr.skip else b.sql)
            continue

        selects += 1
        sort = not has_order_by(b.sql)
        mc = canonicalize(m_res["rows"], sort)
        pc = canonicalize(p_res["rows"], sort)

        results.append(Result(
            block=b,
            index=idx,
            translation=tr,
            m_rows=mc,
            p_rows=pc,
            m_err=m_res["errors"],
            p_err=p_res["errors"],
            setup_m=list(setup_m),
            setup_p=list(setup_p),
        ))
    return results, selects


# --------------------------------------------------------------------------
# Report
# --------------------------------------------------------------------------

def _format_entry(r: Result) -> List[str]:
    """Emit the Markdown lines for one Result (match or diff)."""
    out: List[str] = []
    out.append("---")
    if r.block.section:
        out.append(f"### [{r.classification}] Section {r.block.section} "
                   f"— line {r.block.lineno}")
    else:
        out.append(f"### [{r.classification}] line {r.block.lineno}")
    if r.block.comment:
        out.append(f"_Context:_ {r.block.comment}")
    out.append("")

    # Setup for MariaDB and PG.  If identical, show once; else both.
    if r.setup_m or r.setup_p:
        if r.setup_m == r.setup_p:
            out.append("**Setup (MariaDB and PostgreSQL):**")
            out.append("```sql")
            out.extend(s.rstrip(";") + ";" for s in r.setup_m)
            out.append("```")
        else:
            out.append("**Setup (MariaDB):**")
            out.append("```sql")
            out.extend(s.rstrip(";") + ";" for s in r.setup_m)
            out.append("```")
            out.append("**Setup (PostgreSQL):**")
            out.append("```sql")
            out.extend(s.rstrip(";") + ";" for s in r.setup_p)
            out.append("```")

    # Always show both queries, even if identical, so readers don't
    # have to reason about whether a translation fired.
    out.append("**Query (MariaDB):**")
    out.append("```sql")
    out.append(r.block.sql.strip().rstrip(";") + ";")
    out.append("```")
    out.append("**Query (PostgreSQL):**")
    out.append("```sql")
    out.append(r.translation.sql.strip().rstrip(";") + ";")
    out.append("```")
    if r.translation.notes:
        out.append("**Translator notes:**")
        for n in r.translation.notes:
            out.append(f"- {n}")
        out.append("")

    if r.m_err or r.p_err:
        out.append("**Errors:**")
        if r.m_err:
            out.append("- MariaDB: " + "; ".join(r.m_err))
        if r.p_err:
            out.append("- PostgreSQL: " + "; ".join(r.p_err))
        out.append("")

    if r.is_match:
        out.append(f"**Result:** both engines returned {len(r.m_rows)} "
                   f"identical row(s).")
        out.append("")
    else:
        out.append(f"**MariaDB rows ({len(r.m_rows)}):**")
        out.append("```")
        out.extend(r.m_rows or ["(empty)"])
        out.append("```")
        out.append(f"**PostgreSQL rows ({len(r.p_rows)}):**")
        out.append("```")
        out.extend(r.p_rows or ["(empty)"])
        out.append("```")
        out.append("")
    return out


def write_report(results: List[Result], total_selects: int, outfile: Path,
                 title: str, sections: Optional[List[int]],
                 append: bool = True) -> None:
    # Tag each result first.
    for r in results:
        r.classification = r.classify()
    matches = [r for r in results if r.classification == "matches"]
    expected = [r for r in results if r.classification.startswith("expected")]
    translator = [r for r in results if r.classification.startswith("translator")]
    bugs = [r for r in results if r.classification.startswith("bug")]
    semantic = [r for r in results if r.classification == "semantic"]

    lines: List[str] = []
    if not append or not outfile.exists():
        lines.append(f"# {title}\n")
    lines.append("")
    run_label = (f"sections {sections}" if sections else "all sections")
    lines.append(f"## Run: {run_label}\n")
    lines.append(f"- Comparable SELECT blocks: {total_selects}")
    lines.append(f"- Summary: {len(matches)} matches, "
                 f"{len(bugs)} bug, {len(semantic)} semantic, "
                 f"{len(translator)} translator, {len(expected)} expected\n")

    # Order: bugs first (real defects), then semantic (unclassified diffs),
    # then translator issues, then expected divergences, finally matches
    # (the bulk of the report, but least interesting).
    ordered = bugs + semantic + translator + expected + matches
    for r in ordered:
        lines.extend(_format_entry(r))

    text = "\n".join(lines)
    if append and outfile.exists():
        with outfile.open("a") as f:
            f.write(text)
    else:
        outfile.write_text(text)


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------

def _resolve_binary(explicit: Optional[str], default_name: str,
                    flag_name: str) -> Path:
    """Resolve a CLI-supplied path or fall back to PATH lookup.  Exits
    with a friendly message when neither is usable."""
    if explicit:
        p = Path(explicit).expanduser()
        if not p.is_file() or not os.access(p, os.X_OK):
            sys.exit(f"error: {flag_name} {p} is not an executable file")
        return p
    found = shutil.which(default_name)
    if not found:
        sys.exit(f"error: cannot find `{default_name}` on PATH; "
                 f"pass {flag_name} explicitly")
    return Path(found)


def _build_config(args: argparse.Namespace) -> Config:
    """Validate CLI args and assemble the Config."""
    test_file = Path(args.test).expanduser()
    if not test_file.is_file():
        sys.exit(f"error: test file not found: {test_file}")

    mariadb_client = _resolve_binary(args.mariadb_client, "mariadb",
                                     "--mariadb-client")
    pg_bin = _resolve_binary(args.pg_bin, "psql", "--pg-bin")

    mariadb_socket = Path(args.mariadb_socket).expanduser() \
        if args.mariadb_socket else None
    if mariadb_socket and not mariadb_socket.exists():
        sys.exit(f"error: MariaDB socket not found: {mariadb_socket}")

    # Default report path: <test-basename>.diff.md in the current dir.
    if args.report:
        report = Path(args.report).expanduser()
    else:
        report = Path.cwd() / f"{test_file.stem}.diff.md"

    # Default title from the test file basename.
    title = args.report_title \
        or f"{test_file.name} — MariaDB vs PostgreSQL"

    sections: Optional[Set[int]] = set(args.sections) if args.sections else None

    dump_dir = Path(args.dump_scripts).expanduser() if args.dump_scripts else None
    if dump_dir and not dump_dir.is_dir():
        sys.exit(f"error: --dump-scripts dir does not exist: {dump_dir}")

    return Config(
        test_file=test_file,
        report=report,
        report_title=title,
        sections=sections,
        dump_scripts_dir=dump_dir,
        fresh=args.fresh,
        reset=args.reset,
        mariadb_client=mariadb_client,
        mariadb_db=args.mariadb_db,
        mariadb_socket=mariadb_socket,
        mariadb_host=args.mariadb_host,
        mariadb_port=args.mariadb_port,
        mariadb_user=args.mariadb_user,
        pg_bin=pg_bin,
        pg_db=args.pg_db,
        pg_host=args.pg_host,
        pg_port=args.pg_port,
        pg_user=args.pg_user,
    )


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Compare row sets between MariaDB and PostgreSQL for "
                    "every SELECT in a MariaDB MTR test file.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )

    ap.add_argument("--test", required=True,
                    help="Path to the MariaDB MTR .test file to drive the run.")

    # MariaDB connection
    mg = ap.add_argument_group("MariaDB connection")
    conn = mg.add_mutually_exclusive_group()
    conn.add_argument("--mariadb-socket", default=None,
                      help="UNIX socket path.  Mutually exclusive with --mariadb-host.")
    conn.add_argument("--mariadb-host", default=None,
                      help="TCP hostname.  Mutually exclusive with --mariadb-socket.")
    mg.add_argument("--mariadb-port", type=int, default=None,
                    help="TCP port (only meaningful with --mariadb-host).")
    mg.add_argument("--mariadb-user", default=os.environ.get("USER"),
                    help="MariaDB user.  Password via $MYSQL_PWD or $MARIADB_PWD.")
    mg.add_argument("--mariadb-db", default="test",
                    help="Default database; queries run inside this database.")
    mg.add_argument("--mariadb-client", default=None,
                    help="Path to the `mariadb` (or `mysql`) client binary.")

    # PostgreSQL connection
    pg = ap.add_argument_group("PostgreSQL connection")
    pg.add_argument("--pg-host", default=None,
                    help="Hostname, or a /path-style UNIX socket directory.")
    pg.add_argument("--pg-port", type=int, default=None)
    pg.add_argument("--pg-user", default=os.environ.get("USER"),
                    help="PostgreSQL user.  Password via $PGPASSWORD.")
    pg.add_argument("--pg-db", default="postgres",
                    help="Database queries connect to.")
    pg.add_argument("--pg-bin", default=None,
                    help="Path to the `psql` binary.")

    # Output
    out = ap.add_argument_group("output")
    out.add_argument("--report", default=None,
                     help="Report file path (default: ./<test-basename>.diff.md).")
    out.add_argument("--report-title", default=None,
                     help="H1 line for the report (default: derived from test basename).")
    out.add_argument("--dump-scripts", default=None, metavar="DIR",
                     help="Also write the generated MariaDB/PG scripts under DIR.")

    # Run control
    rc = ap.add_argument_group("run control")
    rc.add_argument("--sections", nargs="*", type=int, default=None,
                    help="Filter to these section numbers (default: all).")
    rc.add_argument("--reset", action="store_true",
                    help="Drop and recreate the MariaDB DB and PG public schema "
                         "before running.")
    rc.add_argument("--fresh", action="store_true",
                    help="Truncate the report before writing (default: append).")

    args = ap.parse_args()
    cfg = _build_config(args)

    if cfg.reset:
        print("Resetting MariaDB and PostgreSQL...", file=sys.stderr)
        reset_mariadb(cfg)
        reset_postgres(cfg)

    blocks = parse_test_file(cfg.test_file, sections=cfg.sections)
    sec_label = (f"sections {sorted(cfg.sections)}" if cfg.sections
                 else "all sections")
    print(f"Parsed {len(blocks)} blocks from {sec_label}", file=sys.stderr)

    if cfg.dump_scripts_dir:
        stem = cfg.test_file.stem
        (cfg.dump_scripts_dir / f"{stem}.mariadb.sql").write_text(
            "\n".join(b.sql + ";" for b in blocks) + "\n")
        (cfg.dump_scripts_dir / f"{stem}.postgres.sql").write_text(
            "\n".join(translate_for_pg(b.sql).sql + ";" for b in blocks) + "\n")

    print("Running blocks (MariaDB + PostgreSQL each)...", file=sys.stderr)
    results, total = compare(cfg, blocks)

    write_report(results, total, cfg.report, cfg.report_title,
                 sorted(cfg.sections) if cfg.sections else None,
                 append=not cfg.fresh)
    print(f"Report: {cfg.report}", file=sys.stderr)
    n_match = sum(1 for r in results if r.classification == "matches")
    n_diff = len(results) - n_match
    print(f"Results: {n_match} matches, {n_diff} differences "
          f"/ {total} comparable SELECTs", file=sys.stderr)

    # Non-zero exit when there's anything unexpected (bug/semantic/translator).
    bad = sum(1 for r in results
              if r.classification.startswith(("bug", "translator"))
              or r.classification == "semantic")
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
