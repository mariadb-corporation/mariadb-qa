# compare.py — MariaDB vs PostgreSQL row-set comparator

For every comparable `SELECT` in a MariaDB MTR `.test` file, the tool
runs the query on both MariaDB and PostgreSQL (translating MariaDB
dialect to PostgreSQL where they diverge) and writes a Markdown
report listing every match and every difference.

## Prerequisites

- **Python 3.8+**
- **MariaDB client binary** (`mariadb` or `mysql`) on `PATH`, or pass
  `--mariadb-client PATH`.
- **PostgreSQL client binary** (`psql`) on `PATH`, or pass
  `--pg-bin PATH`.
- A running MariaDB server you can reach over a UNIX socket or TCP.
- A running PostgreSQL server you can reach the same way.
- If your test file uses MariaDB's vector type or functions, install
  the `pgvector` extension on your PG server.  The translator emits
  `CREATE EXTENSION IF NOT EXISTS vector;` automatically when needed.

Passwords are read from environment variables (`MYSQL_PWD` or
`MARIADB_PWD` for MariaDB, `PGPASSWORD` for PostgreSQL) so they stay
out of shell history.

## Quick start

```sh
# Local socket, default everything
python3 compare.py \
  --test ~/mariadb-src/mysql-test/main/full_join.test \
  --mariadb-socket /tmp/mysql.sock \
  --reset --fresh

# Over TCP, custom databases
python3 compare.py \
  --test path/to/some.test \
  --mariadb-host 127.0.0.1 --mariadb-port 3306 --mariadb-db mtr_test \
  --pg-host /var/run/postgresql --pg-db dev \
  --reset --fresh
```

Example invocation for a fresh report using UNIX sockets for MariaDB:
```
python3 compare.py \
    --test /path/to/some.test \
    --mariadb-client ~/path/to/client/mariadb \
    --mariadb-socket ~/path/to/unix_socket \
    --mariadb-db test \
    --pg-bin ~/postgres-bin/bin/psql \
    --pg-db postgres \
    --pg-user "$USER" \
    --report ~/fj-pg-check/some.pg_diff.md \
    --report-title "some.test — MariaDB vs PostgreSQL" \
    --reset \
    --fresh
```

The report defaults to `./<test-basename>.diff.md` in the current
directory.

## All options

```
--test PATH                      (required)  test file to run

MariaDB connection:
  --mariadb-socket PATH          UNIX socket; mutually exclusive with --mariadb-host
  --mariadb-host HOST            TCP host;    mutually exclusive with --mariadb-socket
  --mariadb-port N
  --mariadb-user USER            default: $USER
  --mariadb-db NAME              default: test
  --mariadb-client PATH          default: `mariadb` on $PATH

PostgreSQL connection:
  --pg-host HOST                 hostname, or /path-style socket directory
  --pg-port N
  --pg-user USER                 default: $USER
  --pg-db NAME                   default: postgres
  --pg-bin PATH                  default: `psql` on $PATH

Output:
  --report PATH                  default: ./<test-basename>.diff.md
  --report-title TEXT            default: derived from test basename
  --dump-scripts DIR             also write the generated MariaDB/PG scripts

Run control:
  --sections N [N ...]           filter to these sections (default: all)
  --reset                        drop+create the MariaDB DB and PG public schema first
  --fresh                        truncate report before writing (default: append)
```

## Sections

If the test file uses `--echo # Section N:` headers, pass
`--sections 1 2 5` to run just those.  If the file has no section
headers, the tool treats it as a single implicit section and runs
everything.

## Reset behaviour

With `--reset`:

- MariaDB: `DROP DATABASE IF EXISTS <db>; CREATE DATABASE <db>;`
- PostgreSQL: `DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public;`

Both are scoped to the database you pass with `--mariadb-db` /
`--pg-db`.  Other databases on the server are untouched, but
**everything in the target MariaDB database and the PG `public`
schema is destroyed**.  Don't aim this at a database you care about.

Without `--reset`, the run uses whatever state the databases are in.

## Exit code

- `0` — every row set either matched or fell into an `expected:`
  classification.
- `1` — at least one `bug:`, `semantic`, or `translator:` entry in
  the report.

## Reading the report

Each entry has this shape:


### [classification] Section <N> — line <L>
_Context:_ <preceding --echo comment from the test file>

**Setup (MariaDB and PostgreSQL):**
```sql
<DDL/DML accumulated since the last DROP TABLE>
```
**Query (MariaDB):**
```sql
<original SQL verbatim>
```
**Query (PostgreSQL):**
```sql
<translated SQL>
```
**Translator notes:**
- <each rewrite rule that fired>

**Errors:**                                (only if either engine errored)
- MariaDB: ...
- PostgreSQL: ...

**MariaDB rows (N):** ...
**PostgreSQL rows (M):** ...


### Classifications

| Tag | Meaning |
|---|---|
| `[matches]` | Both engines accepted the query and returned the same row set. |
| `[expected: ...]` | A known dialect divergence — see the suffix.  Not a bug. |
| `[translator: ...]` | The translated SQL produced a syntax error on PG.  The translator needs a new rewrite or an existing rewrite is producing invalid PG. |
| `[semantic]` | Both engines ran but returned different row sets, not matching any known expected category.  Worth investigating. |

Entries are emitted in the order semantic → translator → expected →
matches, so the most interesting differences are at the top.

Known `[expected: ...]` categories:

- **PG enforces strict GROUP BY** — `select *, agg(...) ... group by col`
  is allowed in MariaDB but not in PG.
- **PG only supports equi-condition FULL JOIN** — PG rejects FULL JOIN
  whose ON clause is not merge- or hash-joinable (`is null`, `<=>`,
  etc.).
- **PG strict typing (no implicit int<->varchar)** — implicit numeric
  to text comparison errors on PG.
- **collation (MariaDB default is case-insensitive)** — string equality
  matches `'world' = 'WORLD'` in MariaDB, not in PG.
- **decimal precision formatting** — same number, different trailing
  zeros (e.g. `15.0000` vs `15.0000000000000000`).

### Author-annotated expected hints

When the row-level heuristics can't detect a dialect difference on
their own (e.g. when collation differences produce *structurally*
different row sets rather than case-different rows), the test author
can mark a query as a known expected diff by including a recognised
phrase in the preceding `--echo` comment.  Current vocabulary:

| Phrase (case-insensitive substring) | Classification |
|---|---|
| `case-sensitive match depends on collation` | `expected: collation (MariaDB default is case-insensitive)` |

Example:

```
--echo # FULL JOIN on varchar column (case-sensitive match depends on collation).
--sorted_result
select t1.id, t2.id from t1 full join t2 on t1.str_val = t2.str_val;
```

To register a new hint, edit `Result.classify()` and add the
substring/classification pair next to the existing one.

## Extending the translator

The translator lives in `translate_for_pg(sql)` near the top of
`compare.py`.  Each rule is a regex substitution that appends a note
to the `Translation.notes` list when it fires.  If your test file
hits a MariaDB construct PG rejects, add a rule there and re-run.
Keep rules narrow — broad regex rewrites tend to misfire on unrelated
SQL.

## Layout

```
compare.py        the tool (Python 3, stdlib only)
README.md         this file
```

## Limitations

- Each block runs in a fresh client invocation.  Server-side session
  state (`SET @var = ...`) does not persist across blocks.
- `PREPARE` / `EXECUTE` / `DEALLOCATE` and `CREATE PROCEDURE` /
  `CALL` are run on MariaDB only; the verification SELECTs that
  follow them are compared.
- The translator is regex-based, not a parser.  Some constructs need
  new rules added by hand as they come up.
