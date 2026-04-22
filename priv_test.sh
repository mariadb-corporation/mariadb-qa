#!/bin/bash
# MariaDB GRANT privilege enforcement test harness.
#
# Creates a disposable user for each privilege listed in SHOW PRIVILEGES,
# grants exactly the privilege(s) under test, and checks that:
#   (a) the gated action succeeds when the privilege is held, and
#   (b) the same action (or a scope/column variant) fails when it is not.
#
# Any FAIL line is either a script bug or a real enforcement gap — both
# worth investigating for the hardening pass.
#
# Usage: cd into a MariaDB test-build dir that has the standard `anc`/`start`
#   helper layout and run `./priv_test.sh`. The script runs `./anc` itself to
#   get a clean server, then runs all tests against `./socket.sock`.
#
# Note on FLUSH PRIVILEGES: every account/grant change below goes through
# SQL DDL (CREATE USER / ALTER USER / GRANT / REVOKE / SET PASSWORD /
# RENAME USER / DROP USER / SET ROLE / CREATE ROLE / DROP ROLE). These
# update the in-memory grant tables as part of the statement, so FLUSH
# PRIVILEGES is NOT required and is deliberately omitted — the determinism
# of this test run is evidence that privilege changes take effect
# immediately. FLUSH PRIVILEGES is only needed when the mysql.* tables are
# modified directly via INSERT/UPDATE/DELETE; the "FLUSH PRIVILEGES
# semantics" section at the end demonstrates that distinction.

set -u
# Note: we don't use `set -e`; tests individually assert success/failure.

# Run against the current working dir. The expectation is that CWD is a
# MariaDB test-build directory that has `anc`, `start`, `socket.sock`, and
# `bin/mariadb[d]` in the standard layout used by mariadb-qa tooling.
BASEDIR="${PWD}"
SOCK="${BASEDIR}/socket.sock"
CLI="${BASEDIR}/bin/mariadb"
ADMIN="${BASEDIR}/bin/mariadb-admin"
SCHEMA="privtest"

if [ ! -x "${BASEDIR}/anc" ] || [ ! -x "${CLI}" ]; then
    echo "ERROR: run this script from inside a MariaDB test-build dir" >&2
    echo "  (missing ./anc or ./bin/mariadb under ${BASEDIR})" >&2
    exit 2
fi

PASS=0
FAIL=0
SKIP=0
FAIL_LIST=()
SKIP_LIST=()
CURRENT_SECTION=""

C_RED=$'\033[0;31m'
C_GRN=$'\033[0;32m'
C_YEL=$'\033[0;33m'
C_BLU=$'\033[0;34m'
C_BLD=$'\033[1m'
C_END=$'\033[0m'

section() {
    CURRENT_SECTION="$1"
    echo
    echo "${C_BLU}${C_BLD}=== ${CURRENT_SECTION} ===${C_END}"
}

log_pass() { PASS=$((PASS + 1)); echo "  ${C_GRN}PASS${C_END}: $1"; }
log_fail() {
    FAIL=$((FAIL + 1))
    FAIL_LIST+=("[${CURRENT_SECTION}] $1")
    echo "  ${C_RED}FAIL${C_END}: $1"
    [ -n "${2:-}" ] && echo "        ${2}" | head -c 400 | sed 's/$/.../' | sed 's/^/        /'
}
log_skip() {
    SKIP=$((SKIP + 1))
    SKIP_LIST+=("[${CURRENT_SECTION}] $1")
    echo "  ${C_YEL}SKIP${C_END}: $1 (${2:-})"
}

# ---------- SQL execution helpers ----------

# root_sql <sql> — run SQL as root; abort harness on error.
root_sql() {
    local out
    out=$(printf '%s\n' "$1" | "${CLI}" -A -uroot -S"${SOCK}" --binary-mode 2>&1)
    local rc=$?
    if [ $rc -ne 0 ] || echo "${out}" | grep -qE '^ERROR'; then
        echo "${C_RED}FATAL${C_END}: root SQL failed:"
        printf '  %s\n' "$1"
        printf '  %s\n' "${out}"
        exit 1
    fi
    # Only emit output when there is any — otherwise an uncaptured call like
    # `root_sql "GRANT ..."` would print a stray blank line between tests.
    [ -n "${out}" ] && echo "${out}"
}

# root_sql_allow_fail <sql> — root SQL, errors are tolerated (returns 1 on error).
root_sql_allow_fail() {
    local out
    out=$(printf '%s\n' "$1" | "${CLI}" -A -uroot -S"${SOCK}" --binary-mode 2>&1)
    local rc=$?
    printf '%s' "${out}"
    [ $rc -eq 0 ] && ! echo "${out}" | grep -qE '^ERROR' && return 0
    return 1
}

# user_run <user> <pass> <db> <sql>
# Pass "" for db to connect without selecting a default schema — required for
# users who hold only global privileges (they can't `USE privtest`).
user_run() {
    local u="$1" p="$2" db="$3" sql="$4"
    local pflag=() dbarg=()
    [ -n "${p}" ] && pflag=(-p"${p}")
    [ -n "${db}" ] && dbarg=("${db}")
    printf '%s\n' "${sql}" | "${CLI}" -A -u"${u}" "${pflag[@]}" -S"${SOCK}" --binary-mode "${dbarg[@]}" 2>&1
}

# assert_ok <user> <pass> <db> <sql> <desc>
assert_ok() {
    local u="$1" p="$2" db="$3" sql="$4" desc="$5"
    local out rc
    out=$(user_run "${u}" "${p}" "${db}" "${sql}")
    rc=$?
    if [ $rc -eq 0 ] && ! echo "${out}" | grep -qE '^ERROR'; then
        log_pass "${desc}"
    else
        log_fail "${desc}" "${out}"
    fi
}

# Error patterns that indicate the server rejected the action on privilege
# grounds (vs. some other SQL error).
DENY_RE='Access denied|command denied|you need (at least one of )?the|privileges? \(at least one of|SUPER|not allowed|anonymous user|grant for|GRANT OPTION|No such grant|has no such grant|is not allowed|not owner of thread|Illegal GRANT|DB GRANT and GLOBAL|running with the --read-only|read-only=ON|read_only'

# assert_denied <user> <pass> <db> <sql> <desc>
assert_denied() {
    local u="$1" p="$2" db="$3" sql="$4" desc="$5"
    local out
    out=$(user_run "${u}" "${p}" "${db}" "${sql}")
    if echo "${out}" | grep -qE "^ERROR.*(${DENY_RE})"; then
        log_pass "${desc}"
    else
        log_fail "${desc}" "${out}"
    fi
}

# assert_error <user> <pass> <db> <sql> <pattern> <desc>
# Passes iff the output contains an ERROR line matching the given regex.
# Used when the expected error is something other than a permission denial
# (e.g. "secure-file-priv" after FILE privilege check succeeds).
assert_error() {
    local u="$1" p="$2" db="$3" sql="$4" pat="$5" desc="$6"
    local out
    out=$(user_run "${u}" "${p}" "${db}" "${sql}")
    if echo "${out}" | grep -qE "^ERROR" && echo "${out}" | grep -qE "${pat}"; then
        log_pass "${desc}"
    else
        log_fail "${desc}" "${out}"
    fi
}

# assert_denied_or_hidden <user> <pass> <db> <sql> <desc>
# MariaDB's SHOW CREATE PROCEDURE/FUNCTION deliberately hides the routine
# (returns "does not exist") when the caller lacks the necessary privilege,
# to avoid leaking routine existence. Treat that as a valid denial.
assert_denied_or_hidden() {
    local u="$1" p="$2" db="$3" sql="$4" desc="$5"
    local out
    out=$(user_run "${u}" "${p}" "${db}" "${sql}")
    if echo "${out}" | grep -qE "^ERROR.*(${DENY_RE}|does not exist)"; then
        log_pass "${desc}"
    else
        log_fail "${desc}" "${out}"
    fi
}

# assert_not_denied <user> <pass> <db> <sql> <desc>
# The action may or may not succeed overall, but it must NOT be refused on
# permission grounds — i.e. the privilege check let us through.
assert_not_denied() {
    local u="$1" p="$2" db="$3" sql="$4" desc="$5"
    local out
    out=$(user_run "${u}" "${p}" "${db}" "${sql}")
    if echo "${out}" | grep -qE "^ERROR.*(${DENY_RE})"; then
        log_fail "${desc}" "${out}"
    else
        log_pass "${desc}"
    fi
}

drop_user() {
    root_sql_allow_fail "DROP USER IF EXISTS ${1};" > /dev/null
}

fresh_user() {
    # fresh_user <name> — creates ${name}@localhost with empty password, returns
    # it fully quoted for re-use.
    drop_user "\`${1}\`@localhost"
    root_sql "CREATE USER \`${1}\`@localhost;"
}

# ---------- Bring up a clean server ----------

echo "${C_BLD}Starting fresh MariaDB server via anc...${C_END}"
cd "${BASEDIR}" || { echo "cannot cd ${BASEDIR}"; exit 1; }
./anc > /dev/null 2>&1
for _ in $(seq 1 120); do
    "${ADMIN}" ping -uroot -S"${SOCK}" >/dev/null 2>&1 && break
    sleep 0.25
done
if ! "${ADMIN}" ping -uroot -S"${SOCK}" >/dev/null 2>&1; then
    echo "${C_RED}FATAL${C_END}: server did not come up."
    exit 1
fi
echo "Server up on ${SOCK}."

echo "Server version: $(root_sql 'SELECT VERSION() AS v' | tail -1)"
echo "secure_file_priv: $(root_sql 'SELECT @@secure_file_priv AS v' | tail -1)"
SECURE_FILE_PRIV=$(root_sql 'SELECT COALESCE(@@secure_file_priv, "__NULL__") AS v' | tail -1)

# ---------- Schema setup ----------

root_sql "
DROP DATABASE IF EXISTS ${SCHEMA};
DROP DATABASE IF EXISTS ${SCHEMA}_alt;
CREATE DATABASE ${SCHEMA};
CREATE DATABASE ${SCHEMA}_alt;
CREATE TABLE ${SCHEMA}.t1 (a INT PRIMARY KEY, b INT, c VARCHAR(32));
INSERT INTO ${SCHEMA}.t1 VALUES (1,10,'x'), (2,20,'y'), (3,30,'z');
CREATE TABLE ${SCHEMA}.t2 (id INT PRIMARY KEY, note VARCHAR(32));
INSERT INTO ${SCHEMA}.t2 VALUES (1,'one'), (2,'two');
CREATE TABLE ${SCHEMA}_alt.other (x INT);
INSERT INTO ${SCHEMA}_alt.other VALUES (1);
CREATE TABLE ${SCHEMA}.vt (a INT PRIMARY KEY, v INT) WITH SYSTEM VERSIONING;
INSERT INTO ${SCHEMA}.vt VALUES (1,1);
UPDATE ${SCHEMA}.vt SET v=2 WHERE a=1;
UPDATE ${SCHEMA}.vt SET v=3 WHERE a=1;
CREATE VIEW ${SCHEMA}.v1 AS SELECT a, b FROM ${SCHEMA}.t1;
DELIMITER //
CREATE PROCEDURE ${SCHEMA}.p1() BEGIN SELECT 1; END //
CREATE FUNCTION ${SCHEMA}.f1() RETURNS INT DETERMINISTIC BEGIN RETURN 42; END //
DELIMITER ;
"

# ============================================================================
# Section: table-level DML privileges — SELECT / INSERT / UPDATE / DELETE
# ============================================================================

section "DML: SELECT / INSERT / UPDATE / DELETE (table scope)"

for priv in SELECT INSERT UPDATE DELETE; do
    uname="u_${priv,,}_tbl"
    fresh_user "${uname}"
    root_sql "GRANT ${priv} ON ${SCHEMA}.t1 TO \`${uname}\`@localhost;"

    # WHERE and computed-from-current-value expressions require SELECT on the
    # referenced columns. We deliberately use literal assignments and
    # constant predicates so the UPDATE/DELETE tests exercise only the
    # privilege under test.
    case "${priv}" in
        SELECT) sql_ok="SELECT * FROM ${SCHEMA}.t1 LIMIT 1"; sql_bad="INSERT INTO ${SCHEMA}.t1 VALUES (99,99,'n')";;
        INSERT) sql_ok="INSERT INTO ${SCHEMA}.t1 VALUES (100+CONNECTION_ID()%1000,1,'ok')"; sql_bad="SELECT * FROM ${SCHEMA}.t1 LIMIT 1";;
        UPDATE) sql_ok="UPDATE ${SCHEMA}.t1 SET b=99 LIMIT 1"; sql_bad="SELECT * FROM ${SCHEMA}.t1 LIMIT 1";;
        DELETE) sql_ok="DELETE FROM ${SCHEMA}.t1 WHERE 1=0"; sql_bad="SELECT * FROM ${SCHEMA}.t1 LIMIT 1";;
    esac

    assert_ok     "${uname}" "" "${SCHEMA}" "${sql_ok}" "${priv}: granted user can perform ${priv}"
    assert_denied "${uname}" "" "${SCHEMA}" "${sql_bad}" "${priv}: granted user CANNOT perform unrelated DML"

    # Scope enforcement: same priv on a different table must not leak.
    assert_denied "${uname}" "" "${SCHEMA}" "SELECT 1 FROM ${SCHEMA}.t2 LIMIT 1" \
        "${priv}: priv on t1 does not leak to t2 (read)"
    assert_denied "${uname}" "" "${SCHEMA}_alt" "SELECT 1 FROM ${SCHEMA}_alt.other LIMIT 1" \
        "${priv}: priv in ${SCHEMA} does not leak to ${SCHEMA}_alt"

    drop_user "\`${uname}\`@localhost"
done

# ============================================================================
# Section: column-level privileges
# ============================================================================

section "Column-level: SELECT(col) / INSERT(col) / UPDATE(col)"

fresh_user "u_col_sel"
root_sql "GRANT SELECT (a,b) ON ${SCHEMA}.t1 TO \`u_col_sel\`@localhost;"
assert_ok     "u_col_sel" "" "${SCHEMA}" "SELECT a,b FROM ${SCHEMA}.t1 LIMIT 1" "SELECT(a,b): granted cols readable"
assert_denied "u_col_sel" "" "${SCHEMA}" "SELECT c FROM ${SCHEMA}.t1 LIMIT 1"    "SELECT(a,b): unlisted col denied"
assert_denied "u_col_sel" "" "${SCHEMA}" "SELECT * FROM ${SCHEMA}.t1 LIMIT 1"     "SELECT(a,b): SELECT * denied (covers c)"
drop_user "\`u_col_sel\`@localhost"

fresh_user "u_col_ins"
root_sql "GRANT INSERT (a) ON ${SCHEMA}.t1 TO \`u_col_ins\`@localhost;"
assert_ok     "u_col_ins" "" "${SCHEMA}" "INSERT INTO ${SCHEMA}.t1 (a) VALUES (201)" "INSERT(a): insert into listed col ok"
assert_denied "u_col_ins" "" "${SCHEMA}" "INSERT INTO ${SCHEMA}.t1 (a,b) VALUES (202,1)" "INSERT(a): insert into unlisted col denied"
drop_user "\`u_col_ins\`@localhost"

fresh_user "u_col_upd"
root_sql "GRANT UPDATE (b) ON ${SCHEMA}.t1 TO \`u_col_upd\`@localhost;
         GRANT SELECT (a) ON ${SCHEMA}.t1 TO \`u_col_upd\`@localhost;"
# `SET b=99` doesn't read b; WHERE references col `a` which we granted SELECT on.
assert_ok     "u_col_upd" "" "${SCHEMA}" "UPDATE ${SCHEMA}.t1 SET b=99 WHERE a=1" "UPDATE(b): update listed col ok"
assert_denied "u_col_upd" "" "${SCHEMA}" "UPDATE ${SCHEMA}.t1 SET c='n' WHERE a=1" "UPDATE(b): update unlisted col denied"
drop_user "\`u_col_upd\`@localhost"

# ============================================================================
# Section: scope — db-scope vs. table-scope
# ============================================================================

section "Scope: db-level grants cover all tables in db, not other dbs"

fresh_user "u_db_sel"
root_sql "GRANT SELECT ON ${SCHEMA}.* TO \`u_db_sel\`@localhost;"
assert_ok     "u_db_sel" "" "${SCHEMA}" "SELECT 1 FROM ${SCHEMA}.t1 LIMIT 1" "SELECT on db.* covers t1"
assert_ok     "u_db_sel" "" "${SCHEMA}" "SELECT 1 FROM ${SCHEMA}.t2 LIMIT 1" "SELECT on db.* covers t2"
assert_denied "u_db_sel" "" "${SCHEMA}_alt" "SELECT 1 FROM ${SCHEMA}_alt.other LIMIT 1" "SELECT on db.* does NOT cover other db"
drop_user "\`u_db_sel\`@localhost"

# ============================================================================
# Section: DDL privileges
# ============================================================================

section "DDL: CREATE / DROP / ALTER / INDEX"

# CREATE (table)
fresh_user "u_create"
root_sql "GRANT CREATE ON ${SCHEMA}.* TO \`u_create\`@localhost;"
assert_ok     "u_create" "" "${SCHEMA}" "CREATE TABLE ${SCHEMA}.nt1 (id INT)" "CREATE: user can create a table"
assert_denied "u_create" "" "${SCHEMA}" "DROP TABLE ${SCHEMA}.nt1" "CREATE: does NOT include DROP"
root_sql "DROP TABLE IF EXISTS ${SCHEMA}.nt1;"
drop_user "\`u_create\`@localhost"

# CREATE at global scope creates new databases
fresh_user "u_create_g"
root_sql "GRANT CREATE ON *.* TO \`u_create_g\`@localhost;"
assert_ok     "u_create_g" "" "${SCHEMA}" "CREATE DATABASE ${SCHEMA}_new" "CREATE global: can create database"
root_sql_allow_fail "DROP DATABASE IF EXISTS ${SCHEMA}_new;" >/dev/null
drop_user "\`u_create_g\`@localhost"

# DROP
fresh_user "u_drop"
root_sql "CREATE TABLE ${SCHEMA}.scrap1 (x INT);
         GRANT DROP ON ${SCHEMA}.scrap1 TO \`u_drop\`@localhost;"
assert_ok     "u_drop" "" "${SCHEMA}" "DROP TABLE ${SCHEMA}.scrap1" "DROP: user can drop table"
assert_denied "u_drop" "" "${SCHEMA}" "DROP TABLE ${SCHEMA}.t2" "DROP: does not extend to table without DROP"
drop_user "\`u_drop\`@localhost"

# ALTER
fresh_user "u_alter"
root_sql "CREATE TABLE ${SCHEMA}.scrap2 (x INT);
         GRANT ALTER ON ${SCHEMA}.scrap2 TO \`u_alter\`@localhost;"
assert_ok     "u_alter" "" "${SCHEMA}" "ALTER TABLE ${SCHEMA}.scrap2 ADD COLUMN y INT" "ALTER: user can alter table"
assert_denied "u_alter" "" "${SCHEMA}" "INSERT INTO ${SCHEMA}.scrap2 VALUES (1,1)" "ALTER: does not include INSERT"
root_sql "DROP TABLE ${SCHEMA}.scrap2;"
drop_user "\`u_alter\`@localhost"

# INDEX
fresh_user "u_index"
root_sql "CREATE TABLE ${SCHEMA}.scrap3 (x INT);
         GRANT INDEX ON ${SCHEMA}.scrap3 TO \`u_index\`@localhost;"
assert_ok     "u_index" "" "${SCHEMA}" "CREATE INDEX idx_x ON ${SCHEMA}.scrap3 (x)" "INDEX: user can create index"
assert_ok     "u_index" "" "${SCHEMA}" "DROP INDEX idx_x ON ${SCHEMA}.scrap3" "INDEX: user can drop index"
assert_denied "u_index" "" "${SCHEMA}" "ALTER TABLE ${SCHEMA}.scrap3 ADD COLUMN y INT" "INDEX: does NOT include full ALTER"
root_sql "DROP TABLE ${SCHEMA}.scrap3;"
drop_user "\`u_index\`@localhost"

# ============================================================================
# Section: view & trigger
# ============================================================================

section "Views & triggers: CREATE VIEW / SHOW VIEW / TRIGGER"

# CREATE VIEW
fresh_user "u_cview"
root_sql "GRANT CREATE VIEW, SELECT ON ${SCHEMA}.* TO \`u_cview\`@localhost;"
assert_ok     "u_cview" "" "${SCHEMA}" "CREATE VIEW ${SCHEMA}.vv AS SELECT a FROM ${SCHEMA}.t1" "CREATE VIEW: granted user ok"
assert_denied "u_cview" "" "${SCHEMA}" "SHOW CREATE VIEW ${SCHEMA}.vv" "CREATE VIEW does not imply SHOW VIEW"
root_sql "DROP VIEW IF EXISTS ${SCHEMA}.vv;"
drop_user "\`u_cview\`@localhost"

# SHOW VIEW
fresh_user "u_sview"
root_sql "GRANT SHOW VIEW, SELECT ON ${SCHEMA}.* TO \`u_sview\`@localhost;"
assert_ok     "u_sview" "" "${SCHEMA}" "SHOW CREATE VIEW ${SCHEMA}.v1" "SHOW VIEW: granted user ok"
drop_user "\`u_sview\`@localhost"

fresh_user "u_sview_no"
root_sql "GRANT SELECT ON ${SCHEMA}.* TO \`u_sview_no\`@localhost;"
assert_denied "u_sview_no" "" "${SCHEMA}" "SHOW CREATE VIEW ${SCHEMA}.v1" "SHOW VIEW: without priv denied"
drop_user "\`u_sview_no\`@localhost"

# TRIGGER
fresh_user "u_trig"
root_sql "GRANT TRIGGER, SELECT, INSERT, UPDATE ON ${SCHEMA}.* TO \`u_trig\`@localhost;"
assert_ok "u_trig" "" "${SCHEMA}" \
    "CREATE TRIGGER ${SCHEMA}.trg_t1 BEFORE INSERT ON ${SCHEMA}.t1 FOR EACH ROW SET NEW.b = COALESCE(NEW.b,0)+1" \
    "TRIGGER: granted user can create trigger"
assert_ok "u_trig" "" "${SCHEMA}" "DROP TRIGGER ${SCHEMA}.trg_t1" "TRIGGER: granted user can drop trigger"
drop_user "\`u_trig\`@localhost"

fresh_user "u_trig_no"
root_sql "GRANT SELECT, INSERT ON ${SCHEMA}.* TO \`u_trig_no\`@localhost;"
assert_denied "u_trig_no" "" "${SCHEMA}" \
    "CREATE TRIGGER ${SCHEMA}.trg_t1 BEFORE INSERT ON ${SCHEMA}.t1 FOR EACH ROW SET NEW.b = NEW.b" \
    "TRIGGER: without priv denied"
drop_user "\`u_trig_no\`@localhost"

# ============================================================================
# Section: routines
# ============================================================================

section "Routines: CREATE ROUTINE / ALTER ROUTINE / EXECUTE / SHOW CREATE ROUTINE"

# CREATE ROUTINE
fresh_user "u_croutine"
root_sql "GRANT CREATE ROUTINE ON ${SCHEMA}.* TO \`u_croutine\`@localhost;"
assert_ok "u_croutine" "" "${SCHEMA}" \
    "CREATE PROCEDURE ${SCHEMA}.p_new() SELECT 1" "CREATE ROUTINE: create procedure ok"
assert_ok "u_croutine" "" "${SCHEMA}" \
    "CREATE FUNCTION ${SCHEMA}.f_new() RETURNS INT DETERMINISTIC RETURN 1" "CREATE ROUTINE: create function ok"
# Creator auto-gets ALTER ROUTINE + EXECUTE on their routine.
assert_ok "u_croutine" "" "${SCHEMA}" "CALL ${SCHEMA}.p_new()" "CREATE ROUTINE: creator can EXECUTE own proc"
assert_ok "u_croutine" "" "${SCHEMA}" "DROP PROCEDURE ${SCHEMA}.p_new" "CREATE ROUTINE: creator can DROP own proc"
root_sql "DROP FUNCTION IF EXISTS ${SCHEMA}.f_new;"
drop_user "\`u_croutine\`@localhost"

# EXECUTE
fresh_user "u_exec"
root_sql "GRANT EXECUTE ON PROCEDURE ${SCHEMA}.p1 TO \`u_exec\`@localhost;
         GRANT EXECUTE ON FUNCTION ${SCHEMA}.f1 TO \`u_exec\`@localhost;"
assert_ok     "u_exec" "" "${SCHEMA}" "CALL ${SCHEMA}.p1()" "EXECUTE: user can CALL proc"
assert_ok     "u_exec" "" "${SCHEMA}" "SELECT ${SCHEMA}.f1()" "EXECUTE: user can invoke function"
assert_denied "u_exec" "" "${SCHEMA}" "DROP PROCEDURE ${SCHEMA}.p1" "EXECUTE: does not grant DROP"
drop_user "\`u_exec\`@localhost"

# ALTER ROUTINE
fresh_user "u_aroutine"
root_sql "GRANT ALTER ROUTINE ON PROCEDURE ${SCHEMA}.p1 TO \`u_aroutine\`@localhost;"
assert_ok     "u_aroutine" "" "${SCHEMA}" "ALTER PROCEDURE ${SCHEMA}.p1 COMMENT 'altered'" "ALTER ROUTINE: granted user ok"
assert_denied "u_aroutine" "" "${SCHEMA}" "CALL ${SCHEMA}.p1()" "ALTER ROUTINE: does not grant EXECUTE"
drop_user "\`u_aroutine\`@localhost"

# SHOW CREATE ROUTINE (MariaDB 11.3+ privilege)
fresh_user "u_scr"
root_sql "GRANT SHOW CREATE ROUTINE ON ${SCHEMA}.* TO \`u_scr\`@localhost;"
assert_ok     "u_scr" "" "${SCHEMA}" "SHOW CREATE PROCEDURE ${SCHEMA}.p1" "SHOW CREATE ROUTINE: can show proc DDL"
assert_ok     "u_scr" "" "${SCHEMA}" "SHOW CREATE FUNCTION ${SCHEMA}.f1"  "SHOW CREATE ROUTINE: can show function DDL"
assert_denied "u_scr" "" "${SCHEMA}" "CALL ${SCHEMA}.p1()"                "SHOW CREATE ROUTINE: does not grant EXECUTE"
drop_user "\`u_scr\`@localhost"

fresh_user "u_scr_no"
root_sql "GRANT SELECT ON ${SCHEMA}.* TO \`u_scr_no\`@localhost;"
# MariaDB hides the routine (returns "does not exist") rather than revealing
# that it exists — accept that as a valid denial.
assert_denied_or_hidden "u_scr_no" "" "${SCHEMA}" "SHOW CREATE PROCEDURE ${SCHEMA}.p1" "SHOW CREATE ROUTINE: without priv denied/hidden"
drop_user "\`u_scr_no\`@localhost"

# ============================================================================
# Section: CREATE TEMPORARY TABLES
# ============================================================================

section "CREATE TEMPORARY TABLES"

fresh_user "u_tmp"
root_sql "GRANT CREATE TEMPORARY TABLES ON ${SCHEMA}.* TO \`u_tmp\`@localhost;"
assert_ok     "u_tmp" "" "${SCHEMA}" "CREATE TEMPORARY TABLE tt (x INT); INSERT INTO tt VALUES (1); SELECT * FROM tt; DROP TEMPORARY TABLE tt" \
    "CREATE TEMPORARY TABLES: full temp-table lifecycle ok"
# Without INSERT on base tables, user still can't write to permanent tables.
assert_denied "u_tmp" "" "${SCHEMA}" "INSERT INTO ${SCHEMA}.t1 VALUES (300,1,'n')" \
    "CREATE TEMPORARY TABLES: does NOT grant INSERT on permanent tables"
drop_user "\`u_tmp\`@localhost"

# ============================================================================
# Section: EVENT
# ============================================================================

section "EVENT"

fresh_user "u_event"
root_sql "GRANT EVENT ON ${SCHEMA}.* TO \`u_event\`@localhost;"
assert_ok "u_event" "" "${SCHEMA}" \
    "CREATE EVENT ${SCHEMA}.ev1 ON SCHEDULE EVERY 1 HOUR DISABLE DO SELECT 1" "EVENT: user can CREATE EVENT"
assert_ok "u_event" "" "${SCHEMA}" "ALTER EVENT ${SCHEMA}.ev1 DISABLE" "EVENT: user can ALTER EVENT"
assert_ok "u_event" "" "${SCHEMA}" "DROP EVENT ${SCHEMA}.ev1" "EVENT: user can DROP EVENT"
drop_user "\`u_event\`@localhost"

fresh_user "u_event_no"
root_sql "GRANT SELECT ON ${SCHEMA}.* TO \`u_event_no\`@localhost;"
assert_denied "u_event_no" "" "${SCHEMA}" \
    "CREATE EVENT ${SCHEMA}.ev2 ON SCHEDULE EVERY 1 HOUR DISABLE DO SELECT 1" "EVENT: without priv denied"
drop_user "\`u_event_no\`@localhost"

# ============================================================================
# Section: LOCK TABLES
# ============================================================================

section "LOCK TABLES"

fresh_user "u_lock"
root_sql "GRANT LOCK TABLES, SELECT ON ${SCHEMA}.* TO \`u_lock\`@localhost;"
assert_ok "u_lock" "" "${SCHEMA}" "LOCK TABLES ${SCHEMA}.t1 READ; UNLOCK TABLES" "LOCK TABLES: granted user ok"
drop_user "\`u_lock\`@localhost"

fresh_user "u_lock_no"
root_sql "GRANT SELECT ON ${SCHEMA}.* TO \`u_lock_no\`@localhost;"
assert_denied "u_lock_no" "" "${SCHEMA}" "LOCK TABLES ${SCHEMA}.t1 READ" "LOCK TABLES: without priv denied"
drop_user "\`u_lock_no\`@localhost"

# ============================================================================
# Section: DELETE HISTORY (system-versioned tables)
# ============================================================================

section "DELETE HISTORY (system versioning)"

fresh_user "u_dh"
root_sql "GRANT DELETE HISTORY ON ${SCHEMA}.vt TO \`u_dh\`@localhost;"
assert_ok     "u_dh" "" "${SCHEMA}" "DELETE HISTORY FROM ${SCHEMA}.vt BEFORE SYSTEM_TIME NOW()" \
    "DELETE HISTORY: granted user can purge history"
assert_denied "u_dh" "" "${SCHEMA}" "DELETE FROM ${SCHEMA}.vt WHERE a=1" \
    "DELETE HISTORY: does NOT grant plain DELETE"
drop_user "\`u_dh\`@localhost"

fresh_user "u_dh_no"
root_sql "GRANT SELECT ON ${SCHEMA}.vt TO \`u_dh_no\`@localhost;"
assert_denied "u_dh_no" "" "${SCHEMA}" "DELETE HISTORY FROM ${SCHEMA}.vt BEFORE SYSTEM_TIME NOW()" \
    "DELETE HISTORY: without priv denied"
drop_user "\`u_dh_no\`@localhost"

# ============================================================================
# Section: FILE (global-only)
# ============================================================================

section "FILE (global)"

fresh_user "u_file"
root_sql "GRANT FILE ON *.* TO \`u_file\`@localhost;"
# Use a unique path per run so a leftover doesn't mask a real enforcement
# change on the next invocation. Clean up both before and after.
OUTF="${BASEDIR}/tmp/privtest_outf_$$"
find "${BASEDIR}/tmp" -maxdepth 1 -name "privtest_outf_*" -delete 2>/dev/null
# With FILE held, the privilege check must pass. What happens next depends
# on @@secure_file_priv:
#   - NULL/empty & writable path → file gets written.
#   - non-empty dir → must be under it, else "secure-file-priv" error.
# In none of those outcomes should we see an Access-denied.
assert_not_denied "u_file" "" "" \
    "SELECT 1 INTO OUTFILE '${OUTF}'" \
    "FILE: priv check passes (not refused on privilege grounds)"
find "${BASEDIR}/tmp" -maxdepth 1 -name "privtest_outf_*" -delete 2>/dev/null
drop_user "\`u_file\`@localhost"

fresh_user "u_file_no"
root_sql "GRANT SELECT ON ${SCHEMA}.* TO \`u_file_no\`@localhost;"
assert_denied "u_file_no" "" "${SCHEMA}" \
    "SELECT 1 INTO OUTFILE '${BASEDIR}/tmp/privtest_outf_nopriv'" \
    "FILE: without priv denied"
drop_user "\`u_file_no\`@localhost"

# FILE cannot be granted at db-scope — expect a "not a database-level
# privilege" error. The target user must exist already, otherwise we hit
# "no matching row in user table" which is a different error.
fresh_user "u_file_dbscope"
assert_error "root" "" "" \
    "GRANT FILE ON ${SCHEMA}.* TO \`u_file_dbscope\`@localhost" \
    "Illegal GRANT|GLOBAL PRIVILEGES|not a database|wrong usage|DB GRANT" \
    "FILE: cannot be granted at db scope"
drop_user "\`u_file_dbscope\`@localhost"

# ============================================================================
# Section: PROCESS
# ============================================================================

section "PROCESS"

fresh_user "u_proc"
root_sql "GRANT PROCESS ON *.* TO \`u_proc\`@localhost;"
assert_ok "u_proc" "" "" "SHOW ENGINE INNODB STATUS" "PROCESS: SHOW ENGINE INNODB STATUS ok"
# With PROCESS we see other threads in INFORMATION_SCHEMA.PROCESSLIST.
assert_ok "u_proc" "" "" \
    "SELECT IF(COUNT(DISTINCT USER) >= 1, 'ok', 'missing') AS r FROM INFORMATION_SCHEMA.PROCESSLIST" \
    "PROCESS: can query PROCESSLIST"
drop_user "\`u_proc\`@localhost"

fresh_user "u_proc_no"
assert_denied "u_proc_no" "" "" "SHOW ENGINE INNODB STATUS" "PROCESS: without priv SHOW ENGINE INNODB STATUS denied"
drop_user "\`u_proc_no\`@localhost"

# ============================================================================
# Section: RELOAD
# ============================================================================

section "RELOAD"

fresh_user "u_reload"
root_sql "GRANT RELOAD ON *.* TO \`u_reload\`@localhost;"
assert_ok     "u_reload" "" "" "FLUSH TABLES"       "RELOAD: FLUSH TABLES ok"
assert_ok     "u_reload" "" "" "FLUSH LOGS"         "RELOAD: FLUSH LOGS ok"
assert_ok     "u_reload" "" "" "FLUSH STATUS"       "RELOAD: FLUSH STATUS ok"
assert_ok     "u_reload" "" "" "FLUSH PRIVILEGES"   "RELOAD: FLUSH PRIVILEGES ok"
drop_user "\`u_reload\`@localhost"

fresh_user "u_reload_no"
assert_denied "u_reload_no" "" "" "FLUSH TABLES"     "RELOAD: without priv FLUSH TABLES denied"
assert_denied "u_reload_no" "" "" "FLUSH PRIVILEGES" "RELOAD: without priv FLUSH PRIVILEGES denied"
drop_user "\`u_reload_no\`@localhost"

# ============================================================================
# Section: SHOW DATABASES
# ============================================================================

section "SHOW DATABASES"

# With the privilege — should see all dbs.
fresh_user "u_shdb"
root_sql "GRANT SHOW DATABASES ON *.* TO \`u_shdb\`@localhost;"
out=$(user_run "u_shdb" "" "" "SHOW DATABASES")
if echo "${out}" | grep -q "${SCHEMA}_alt" && echo "${out}" | grep -q "mysql"; then
    log_pass "SHOW DATABASES: sees ${SCHEMA}_alt AND mysql"
else
    log_fail "SHOW DATABASES: did not see all dbs" "${out}"
fi
drop_user "\`u_shdb\`@localhost"

# Without — user only sees dbs they have privs on.
fresh_user "u_shdb_no"
root_sql "GRANT SELECT ON ${SCHEMA}.* TO \`u_shdb_no\`@localhost;"
out=$(user_run "u_shdb_no" "" "" "SHOW DATABASES")
if echo "${out}" | grep -q "${SCHEMA}" && ! echo "${out}" | grep -q "${SCHEMA}_alt"; then
    log_pass "SHOW DATABASES: without priv, only permitted dbs listed"
else
    log_fail "SHOW DATABASES: filter misbehaved" "${out}"
fi
drop_user "\`u_shdb_no\`@localhost"

# ============================================================================
# Section: CREATE USER (and roles — roles require CREATE USER or INSERT mysql.*)
# ============================================================================

section "CREATE USER / roles"

fresh_user "u_cu"
root_sql "GRANT CREATE USER ON *.* TO \`u_cu\`@localhost;"
assert_ok     "u_cu" "" "" "CREATE USER temp_x@localhost" "CREATE USER: can create user"
assert_ok     "u_cu" "" "" "RENAME USER temp_x@localhost TO temp_y@localhost" "CREATE USER: can rename user"
assert_ok     "u_cu" "" "" "DROP USER temp_y@localhost" "CREATE USER: can drop user"
# Roles also require CREATE USER.
assert_ok     "u_cu" "" "" "CREATE ROLE r_cu"   "CREATE USER: can CREATE ROLE"
assert_ok     "u_cu" "" "" "DROP ROLE r_cu"     "CREATE USER: can DROP ROLE"
drop_user "\`u_cu\`@localhost"

fresh_user "u_cu_no"
assert_denied "u_cu_no" "" "" "CREATE USER temp_z@localhost" "CREATE USER: without priv denied"
assert_denied "u_cu_no" "" "" "CREATE ROLE r_no" "CREATE ROLE: without CREATE USER denied"
drop_user "\`u_cu_no\`@localhost"

# ============================================================================
# Section: SUPER and its descendants
# ============================================================================

section "SUPER and split children"

# SUPER residual — KILL system / connection of another user, SET GLOBAL of
# non-split variables, etc.  Also needed for changing DEFINER in some paths.
# Here we test a legacy SUPER-gated action: set a session sql_mode variable
# that requires SUPER — actually SET GLOBAL of things that did NOT split out.
# `general_log` and `slow_query_log` still need SUPER (or RELOAD? actually
# require SUPER+FILE historically) — simplest: SET GLOBAL event_scheduler.
fresh_user "u_super"
root_sql "GRANT SUPER ON *.* TO \`u_super\`@localhost;"
assert_ok "u_super" "" "" "SET GLOBAL event_scheduler=OFF" "SUPER: SET GLOBAL event_scheduler ok"
drop_user "\`u_super\`@localhost"

fresh_user "u_super_no"
assert_denied "u_super_no" "" "" "SET GLOBAL event_scheduler=ON" "SUPER: without priv SET GLOBAL denied"
drop_user "\`u_super_no\`@localhost"

# BINLOG MONITOR (formerly REPLICATION CLIENT) — SHOW BINARY LOGS / BINLOG STATUS.
fresh_user "u_blmon"
root_sql "GRANT BINLOG MONITOR ON *.* TO \`u_blmon\`@localhost;"
assert_not_denied "u_blmon" "" "" "SHOW BINARY LOGS" "BINLOG MONITOR: SHOW BINARY LOGS not refused on priv"
assert_not_denied "u_blmon" "" "" "SHOW BINLOG STATUS" "BINLOG MONITOR: SHOW BINLOG STATUS not refused on priv"
drop_user "\`u_blmon\`@localhost"

# REPLICATION CLIENT is an alias for BINLOG MONITOR — SHOW GRANTS should
# display the canonical form.
fresh_user "u_rc"
root_sql "GRANT REPLICATION CLIENT ON *.* TO \`u_rc\`@localhost;"
out=$(root_sql "SHOW GRANTS FOR \`u_rc\`@localhost")
if echo "${out}" | grep -q "BINLOG MONITOR"; then
    log_pass "REPLICATION CLIENT: alias for BINLOG MONITOR (SHOW GRANTS)"
else
    log_fail "REPLICATION CLIENT: alias did not normalize to BINLOG MONITOR" "${out}"
fi
drop_user "\`u_rc\`@localhost"

fresh_user "u_blmon_no"
assert_denied "u_blmon_no" "" "" "SHOW BINARY LOGS" "BINLOG MONITOR: without priv SHOW BINARY LOGS denied"
drop_user "\`u_blmon_no\`@localhost"

# BINLOG ADMIN — PURGE BINARY LOGS (server has no binlog here → expect either
# success or a non-privilege error; not denial).
fresh_user "u_bladmin"
root_sql "GRANT BINLOG ADMIN ON *.* TO \`u_bladmin\`@localhost;"
assert_not_denied "u_bladmin" "" "" "PURGE BINARY LOGS BEFORE NOW()" "BINLOG ADMIN: PURGE not refused on priv"
drop_user "\`u_bladmin\`@localhost"

fresh_user "u_bladmin_no"
assert_denied "u_bladmin_no" "" "" "PURGE BINARY LOGS BEFORE NOW()" "BINLOG ADMIN: without priv PURGE denied"
drop_user "\`u_bladmin_no\`@localhost"

# BINLOG REPLAY — session gtid_seq_no is gated on this.
fresh_user "u_blreplay"
root_sql "GRANT BINLOG REPLAY ON *.* TO \`u_blreplay\`@localhost;"
assert_not_denied "u_blreplay" "" "" "SET SESSION gtid_seq_no = 1000" "BINLOG REPLAY: set gtid_seq_no ok"
drop_user "\`u_blreplay\`@localhost"

fresh_user "u_blreplay_no"
assert_denied "u_blreplay_no" "" "" "SET SESSION gtid_seq_no = 1000" "BINLOG REPLAY: without priv denied"
drop_user "\`u_blreplay_no\`@localhost"

# REPLICATION MASTER ADMIN — SHOW REPLICA HOSTS / SHOW SLAVE HOSTS.
fresh_user "u_rmadmin"
root_sql "GRANT REPLICATION MASTER ADMIN ON *.* TO \`u_rmadmin\`@localhost;"
assert_not_denied "u_rmadmin" "" "" "SHOW SLAVE HOSTS" "REPLICATION MASTER ADMIN: SHOW SLAVE HOSTS ok"
drop_user "\`u_rmadmin\`@localhost"

fresh_user "u_rmadmin_no"
assert_denied "u_rmadmin_no" "" "" "SHOW SLAVE HOSTS" "REPLICATION MASTER ADMIN: without priv denied"
drop_user "\`u_rmadmin_no\`@localhost"

# REPLICATION SLAVE ADMIN — START/STOP REPLICA, CHANGE MASTER.
fresh_user "u_rsadmin"
root_sql "GRANT REPLICATION SLAVE ADMIN ON *.* TO \`u_rsadmin\`@localhost;"
# Not configured, so expect server-side "not configured" error, not a denial.
assert_not_denied "u_rsadmin" "" "" "STOP SLAVE" "REPLICATION SLAVE ADMIN: STOP SLAVE not refused on priv"
drop_user "\`u_rsadmin\`@localhost"

fresh_user "u_rsadmin_no"
assert_denied "u_rsadmin_no" "" "" "STOP SLAVE" "REPLICATION SLAVE ADMIN: without priv STOP SLAVE denied"
assert_denied "u_rsadmin_no" "" "" "CHANGE MASTER TO MASTER_HOST='x'" "REPLICATION SLAVE ADMIN: without priv CHANGE MASTER denied"
drop_user "\`u_rsadmin_no\`@localhost"

# SLAVE MONITOR / REPLICA MONITOR — SHOW SLAVE STATUS, SHOW RELAYLOG EVENTS.
fresh_user "u_slmon"
root_sql "GRANT SLAVE MONITOR ON *.* TO \`u_slmon\`@localhost;"
assert_not_denied "u_slmon" "" "" "SHOW SLAVE STATUS" "SLAVE MONITOR: SHOW SLAVE STATUS ok"
drop_user "\`u_slmon\`@localhost"

fresh_user "u_slmon_no"
assert_denied "u_slmon_no" "" "" "SHOW SLAVE STATUS" "SLAVE MONITOR: without priv denied"
drop_user "\`u_slmon_no\`@localhost"

# REPLICATION SLAVE — tested via grant/show grants since exercising COM_BINLOG_DUMP
# is out of scope for a SQL-level harness.
fresh_user "u_rslv"
root_sql "GRANT REPLICATION SLAVE ON *.* TO \`u_rslv\`@localhost;"
out=$(root_sql "SHOW GRANTS FOR \`u_rslv\`@localhost")
if echo "${out}" | grep -q "REPLICATION SLAVE"; then
    log_pass "REPLICATION SLAVE: grant recorded"
else
    log_fail "REPLICATION SLAVE: grant not visible" "${out}"
fi
drop_user "\`u_rslv\`@localhost"

# CONNECTION ADMIN — kill another user's connection.
# Open a long-running connection as a victim user, grab its CONNECTION_ID,
# then attempt KILL as a user WITH and WITHOUT CONNECTION ADMIN.
fresh_user "u_victim"
fresh_user "u_killer_ok"
fresh_user "u_killer_no"
root_sql "GRANT SELECT ON ${SCHEMA}.* TO \`u_victim\`@localhost;
         GRANT CONNECTION ADMIN ON *.* TO \`u_killer_ok\`@localhost;
         GRANT SELECT ON ${SCHEMA}.* TO \`u_killer_no\`@localhost;"

spawn_victim() {
    "${CLI}" -A -uu_victim -S"${SOCK}" "${SCHEMA}" -e "SELECT SLEEP(30)" >/dev/null 2>&1 &
    sleep 0.4
    root_sql "SELECT ID FROM INFORMATION_SCHEMA.PROCESSLIST WHERE USER='u_victim' ORDER BY TIME DESC LIMIT 1" \
        | tail -1
}

vid=$(spawn_victim)
if [[ -n "${vid}" && "${vid}" =~ ^[0-9]+$ ]]; then
    assert_denied "u_killer_no" "" "${SCHEMA}" "KILL ${vid}" "CONNECTION ADMIN: without priv KILL of other user denied"
else
    log_skip "CONNECTION ADMIN negative: could not spawn victim" "vid=${vid}"
fi
vid=$(spawn_victim)
if [[ -n "${vid}" && "${vid}" =~ ^[0-9]+$ ]]; then
    # u_killer_ok has only CONNECTION ADMIN (global) — no default db.
    assert_ok "u_killer_ok" "" "" "KILL ${vid}" "CONNECTION ADMIN: with priv KILL of other user ok"
else
    log_skip "CONNECTION ADMIN positive: could not spawn victim" "vid=${vid}"
fi
wait 2>/dev/null
drop_user "\`u_victim\`@localhost"
drop_user "\`u_killer_ok\`@localhost"
drop_user "\`u_killer_no\`@localhost"

# FEDERATED ADMIN — CREATE/ALTER/DROP SERVER.
fresh_user "u_fedadmin"
root_sql "GRANT FEDERATED ADMIN ON *.* TO \`u_fedadmin\`@localhost;"
assert_ok "u_fedadmin" "" "" \
    "CREATE SERVER fs1 FOREIGN DATA WRAPPER mysql OPTIONS (HOST '127.0.0.1', DATABASE '${SCHEMA}', USER 'root', PORT 3306)" \
    "FEDERATED ADMIN: CREATE SERVER ok"
assert_ok "u_fedadmin" "" "" "DROP SERVER fs1" "FEDERATED ADMIN: DROP SERVER ok"
drop_user "\`u_fedadmin\`@localhost"

fresh_user "u_fedadmin_no"
assert_denied "u_fedadmin_no" "" "" \
    "CREATE SERVER fs2 FOREIGN DATA WRAPPER mysql OPTIONS (HOST '127.0.0.1', DATABASE '${SCHEMA}', USER 'root', PORT 3306)" \
    "FEDERATED ADMIN: without priv denied"
drop_user "\`u_fedadmin_no\`@localhost"

# SET USER — create routine/view/trigger with non-self DEFINER.
# SET USER is global-only; CREATE/ALTER ROUTINE stays db-scoped.
fresh_user "u_setuser"
root_sql "GRANT SET USER ON *.* TO \`u_setuser\`@localhost;
         GRANT CREATE ROUTINE, ALTER ROUTINE ON ${SCHEMA}.* TO \`u_setuser\`@localhost;"
assert_ok "u_setuser" "" "${SCHEMA}" \
    "CREATE DEFINER='root'@'localhost' PROCEDURE ${SCHEMA}.p_su() SELECT 1" \
    "SET USER: create proc with DEFINER=root ok"
root_sql_allow_fail "DROP PROCEDURE IF EXISTS ${SCHEMA}.p_su;" >/dev/null
drop_user "\`u_setuser\`@localhost"

fresh_user "u_setuser_no"
root_sql "GRANT CREATE ROUTINE ON ${SCHEMA}.* TO \`u_setuser_no\`@localhost;"
# Without SET USER, MariaDB either rejects the non-self DEFINER outright
# or silently rewrites to the creator and warns. Either is acceptable —
# what's NOT acceptable is allowing the non-self DEFINER to persist.
SU_OUT="${BASEDIR}/tmp/privtest_su.out"
user_run "u_setuser_no" "" "${SCHEMA}" \
    "CREATE DEFINER='root'@'localhost' PROCEDURE ${SCHEMA}.p_su_no() SELECT 1" > "${SU_OUT}" 2>&1
out=$(root_sql_allow_fail "SELECT DEFINER FROM mysql.proc WHERE db='${SCHEMA}' AND name='p_su_no'")
if grep -qiE "access denied|specified as a definer|SET USER" "${SU_OUT}" 2>/dev/null; then
    log_pass "SET USER: without priv DEFINER override refused"
elif echo "${out}" | grep -q "u_setuser_no"; then
    log_pass "SET USER: without priv DEFINER override rewritten to creator"
else
    log_fail "SET USER: without priv DEFINER override not properly handled" \
        "proc-definer='${out}' / client='$(cat "${SU_OUT}" 2>/dev/null)'"
fi
rm -f "${SU_OUT}"
root_sql_allow_fail "DROP PROCEDURE IF EXISTS ${SCHEMA}.p_su_no;" >/dev/null
drop_user "\`u_setuser_no\`@localhost"

# READ_ONLY ADMIN — SET GLOBAL read_only and write-during-read_only.
fresh_user "u_roadmin"
root_sql "GRANT READ_ONLY ADMIN, INSERT, SELECT ON *.* TO \`u_roadmin\`@localhost;"
# Turn read_only on as root, test that the RO-ADMIN user can still write,
# then reset.
root_sql "SET GLOBAL read_only = ON;"
assert_ok "u_roadmin" "" "${SCHEMA}" "INSERT INTO ${SCHEMA}.t2 VALUES (777,'ro')" "READ_ONLY ADMIN: bypasses read_only"
root_sql "SET GLOBAL read_only = OFF; DELETE FROM ${SCHEMA}.t2 WHERE id=777;"
assert_ok "u_roadmin" "" "" "SET GLOBAL read_only = OFF" "READ_ONLY ADMIN: can change read_only"
drop_user "\`u_roadmin\`@localhost"

fresh_user "u_roadmin_no"
root_sql "GRANT INSERT, SELECT ON *.* TO \`u_roadmin_no\`@localhost;
         SET GLOBAL read_only = ON;"
assert_denied "u_roadmin_no" "" "${SCHEMA}" "INSERT INTO ${SCHEMA}.t2 VALUES (778,'ro')" \
    "READ_ONLY ADMIN: without priv INSERT blocked under read_only"
root_sql "SET GLOBAL read_only = OFF;"
drop_user "\`u_roadmin_no\`@localhost"

# SHUTDOWN — negative only (we don't want to shut the server down).
fresh_user "u_shut_no"
assert_denied "u_shut_no" "" "" "SHUTDOWN" "SHUTDOWN: without priv denied"
drop_user "\`u_shut_no\`@localhost"
log_skip "SHUTDOWN positive" "would terminate the running server"

# CREATE TABLESPACE — parser still accepts it; run grant path only.
fresh_user "u_cts"
root_sql "GRANT CREATE TABLESPACE ON *.* TO \`u_cts\`@localhost;"
out=$(root_sql "SHOW GRANTS FOR \`u_cts\`@localhost")
if echo "${out}" | grep -q "CREATE TABLESPACE"; then
    log_pass "CREATE TABLESPACE: grant recorded"
else
    log_fail "CREATE TABLESPACE: grant missing" "${out}"
fi
drop_user "\`u_cts\`@localhost"

# ============================================================================
# Section: PROXY
# ============================================================================

section "PROXY"

# Create target and proxy users; granter must have PROXY ... WITH GRANT OPTION.
fresh_user "u_target"
fresh_user "u_proxy"
# root has PROXY ''@'%' WITH GRANT OPTION by default.
assert_ok "root" "" "" \
    "GRANT PROXY ON \`u_target\`@localhost TO \`u_proxy\`@localhost" \
    "PROXY: root can GRANT PROXY"

# A user without PROXY WITH GRANT OPTION on the target cannot re-grant.
fresh_user "u_proxy2"
assert_denied "u_proxy" "" "" \
    "GRANT PROXY ON \`u_target\`@localhost TO \`u_proxy2\`@localhost" \
    "PROXY: proxy without GRANT OPTION cannot re-grant"

root_sql_allow_fail "REVOKE PROXY ON \`u_target\`@localhost FROM \`u_proxy\`@localhost" >/dev/null
drop_user "\`u_target\`@localhost"
drop_user "\`u_proxy\`@localhost"
drop_user "\`u_proxy2\`@localhost"

# ============================================================================
# Section: GRANT OPTION
# ============================================================================

section "GRANT OPTION"

fresh_user "u_granter"
fresh_user "u_recipient"
root_sql "GRANT SELECT ON ${SCHEMA}.* TO \`u_granter\`@localhost WITH GRANT OPTION;"
assert_ok "u_granter" "" "${SCHEMA}" \
    "GRANT SELECT ON ${SCHEMA}.t1 TO \`u_recipient\`@localhost" \
    "GRANT OPTION: holder can re-grant subset of own privs"
# Cannot escalate to a privilege the granter does not hold.
assert_denied "u_granter" "" "${SCHEMA}" \
    "GRANT INSERT ON ${SCHEMA}.t1 TO \`u_recipient\`@localhost" \
    "GRANT OPTION: cannot grant a priv the holder lacks"
drop_user "\`u_granter\`@localhost"
drop_user "\`u_recipient\`@localhost"

# Without GRANT OPTION, even a priv-holder cannot re-grant.
fresh_user "u_nogopt"
fresh_user "u_recipient2"
root_sql "GRANT SELECT ON ${SCHEMA}.* TO \`u_nogopt\`@localhost;"
assert_denied "u_nogopt" "" "${SCHEMA}" \
    "GRANT SELECT ON ${SCHEMA}.t1 TO \`u_recipient2\`@localhost" \
    "GRANT OPTION: without it, re-grant denied"
drop_user "\`u_nogopt\`@localhost"
drop_user "\`u_recipient2\`@localhost"

# ============================================================================
# Section: ALL PRIVILEGES
# ============================================================================

section "ALL PRIVILEGES"

fresh_user "u_all_db"
root_sql "GRANT ALL PRIVILEGES ON ${SCHEMA}.* TO \`u_all_db\`@localhost;"
for act in \
    "SELECT * FROM ${SCHEMA}.t1 LIMIT 1|SELECT" \
    "INSERT INTO ${SCHEMA}.t2 VALUES (900,'all')|INSERT" \
    "UPDATE ${SCHEMA}.t2 SET note='up' WHERE id=900|UPDATE" \
    "DELETE FROM ${SCHEMA}.t2 WHERE id=900|DELETE" \
    "CREATE TABLE ${SCHEMA}.alltbl (x INT)|CREATE" \
    "ALTER TABLE ${SCHEMA}.alltbl ADD COLUMN y INT|ALTER" \
    "DROP TABLE ${SCHEMA}.alltbl|DROP" \
; do
    sql="${act%|*}"; desc="${act##*|}"
    assert_ok "u_all_db" "" "${SCHEMA}" "${sql}" "ALL PRIVILEGES on db: includes ${desc}"
done
# ALL does NOT include GRANT OPTION.
fresh_user "u_all_recip"
assert_denied "u_all_db" "" "${SCHEMA}" \
    "GRANT SELECT ON ${SCHEMA}.t1 TO \`u_all_recip\`@localhost" \
    "ALL PRIVILEGES: does NOT include GRANT OPTION"
drop_user "\`u_all_recip\`@localhost"
drop_user "\`u_all_db\`@localhost"

# Scope: ALL on db does NOT reach other db.
fresh_user "u_all_scope"
root_sql "GRANT ALL PRIVILEGES ON ${SCHEMA}.* TO \`u_all_scope\`@localhost;"
assert_denied "u_all_scope" "" "${SCHEMA}_alt" "SELECT 1 FROM ${SCHEMA}_alt.other LIMIT 1" \
    "ALL PRIVILEGES on db.* does NOT extend to other db"
drop_user "\`u_all_scope\`@localhost"

# ============================================================================
# Section: USAGE & resource options
# ============================================================================

section "USAGE"

fresh_user "u_usage"
# USAGE = no privs, just a placeholder.
root_sql "GRANT USAGE ON *.* TO \`u_usage\`@localhost WITH MAX_QUERIES_PER_HOUR 5 MAX_USER_CONNECTIONS 2;"
out=$(root_sql "SHOW GRANTS FOR \`u_usage\`@localhost")
if echo "${out}" | grep -q "USAGE" && echo "${out}" | grep -q "MAX_QUERIES_PER_HOUR 5"; then
    log_pass "USAGE: placeholder row with resource options stored"
else
    log_fail "USAGE: row/options not recorded" "${out}"
fi
assert_denied "u_usage" "" "" "SELECT 1 FROM ${SCHEMA}.t1 LIMIT 1" "USAGE: grants no privileges"
drop_user "\`u_usage\`@localhost"

# ============================================================================
# Section: Roles
# ============================================================================

section "Roles"

root_sql_allow_fail "DROP ROLE IF EXISTS r_role1;" >/dev/null
root_sql "CREATE ROLE r_role1; GRANT SELECT ON ${SCHEMA}.t1 TO r_role1;"

fresh_user "u_role"
root_sql "GRANT r_role1 TO \`u_role\`@localhost;"

# Before SET ROLE — the role's privileges are NOT active. Use no default db,
# since the user hasn't got SELECT on ${SCHEMA} until SET ROLE.
assert_denied "u_role" "" "" "SELECT 1 FROM ${SCHEMA}.t1 LIMIT 1" "Role: privs not active before SET ROLE"

# After SET ROLE r_role1 (within single connection) — should succeed.
assert_ok "u_role" "" "" \
    "SET ROLE r_role1; SELECT 1 FROM ${SCHEMA}.t1 LIMIT 1" \
    "Role: privs active after SET ROLE"

# Default role: make it the default, then a fresh connection picks it up.
root_sql "SET DEFAULT ROLE r_role1 FOR \`u_role\`@localhost;"
assert_ok "u_role" "" "${SCHEMA}" \
    "SELECT 1 FROM ${SCHEMA}.t1 LIMIT 1" \
    "Role: default role auto-activates on login"

# Revoke default and role; check access gone.
root_sql "SET DEFAULT ROLE NONE FOR \`u_role\`@localhost; REVOKE r_role1 FROM \`u_role\`@localhost;"
assert_denied "u_role" "" "" \
    "SELECT 1 FROM ${SCHEMA}.t1 LIMIT 1" \
    "Role: revoking role removes access"

# Role granting requires ADMIN OPTION (or being the role creator).
fresh_user "u_roleadmin"
root_sql "GRANT r_role1 TO \`u_roleadmin\`@localhost;"
fresh_user "u_roleuser"
assert_denied "u_roleadmin" "" "" \
    "GRANT r_role1 TO \`u_roleuser\`@localhost" \
    "Role: without ADMIN OPTION cannot re-grant role"
root_sql "GRANT r_role1 TO \`u_roleadmin\`@localhost WITH ADMIN OPTION;"
assert_ok "u_roleadmin" "" "" \
    "GRANT r_role1 TO \`u_roleuser\`@localhost" \
    "Role: WITH ADMIN OPTION allows re-grant"

drop_user "\`u_roleadmin\`@localhost"
drop_user "\`u_roleuser\`@localhost"
drop_user "\`u_role\`@localhost"
root_sql "DROP ROLE r_role1;"

# ============================================================================
# Section: REFERENCES (accepted but currently unenforced)
# ============================================================================

section "REFERENCES (syntactic)"

fresh_user "u_ref"
root_sql "GRANT REFERENCES ON ${SCHEMA}.t1 TO \`u_ref\`@localhost;"
out=$(root_sql "SHOW GRANTS FOR \`u_ref\`@localhost")
if echo "${out}" | grep -q "REFERENCES"; then
    log_pass "REFERENCES: grant recorded (semantic: historically unenforced in MariaDB)"
else
    log_fail "REFERENCES: grant missing" "${out}"
fi
drop_user "\`u_ref\`@localhost"

# ============================================================================
# Section: cross-checks — SUPER does NOT imply the split children (10.5+)
# ============================================================================

section "SUPER split: SUPER alone does NOT imply split children"

fresh_user "u_super_only"
root_sql "GRANT SUPER ON *.* TO \`u_super_only\`@localhost;"

# Each of these privileges was split out of SUPER and must be held separately.
# Confirm SUPER alone is insufficient.
assert_denied "u_super_only" "" "" "STOP SLAVE"                  "SUPER alone does NOT grant REPLICATION SLAVE ADMIN"
assert_denied "u_super_only" "" "" "SHOW SLAVE STATUS"           "SUPER alone does NOT grant SLAVE MONITOR"
assert_denied "u_super_only" "" "" "SHOW BINARY LOGS"            "SUPER alone does NOT grant BINLOG MONITOR"
assert_denied "u_super_only" "" "" "PURGE BINARY LOGS BEFORE NOW()" "SUPER alone does NOT grant BINLOG ADMIN"
assert_denied "u_super_only" "" "" "SET SESSION gtid_seq_no = 123"  "SUPER alone does NOT grant BINLOG REPLAY"
assert_denied "u_super_only" "" "" \
    "CREATE SERVER fs_super FOREIGN DATA WRAPPER mysql OPTIONS (HOST '127.0.0.1')" \
    "SUPER alone does NOT grant FEDERATED ADMIN"
# READ_ONLY ADMIN was removed from SUPER in 10.11/11.0+; with read_only=ON a
# SUPER-only user should NOT be able to write.
root_sql "GRANT SELECT, INSERT ON ${SCHEMA}.* TO \`u_super_only\`@localhost;
         SET GLOBAL read_only = ON;"
assert_denied "u_super_only" "" "${SCHEMA}" \
    "INSERT INTO ${SCHEMA}.t2 VALUES (655, 'su')" \
    "SUPER alone does NOT grant READ_ONLY ADMIN (13.0)"
root_sql "SET GLOBAL read_only = OFF;"

drop_user "\`u_super_only\`@localhost"

# ============================================================================
# Section: sanity — unauthenticated/empty-grant user cannot do anything
# ============================================================================

section "USAGE-only sanity: minimal user is locked out of data"

fresh_user "u_empty"
assert_denied "u_empty" "" "${SCHEMA}" "SELECT 1 FROM ${SCHEMA}.t1 LIMIT 1" "Empty grants: SELECT denied"
assert_denied "u_empty" "" "${SCHEMA}" "SHOW CREATE TABLE ${SCHEMA}.t1"     "Empty grants: SHOW CREATE TABLE denied"
assert_denied "u_empty" "" "${SCHEMA}" "INSERT INTO ${SCHEMA}.t1 VALUES (5,5,'n')" "Empty grants: INSERT denied"
drop_user "\`u_empty\`@localhost"

# ============================================================================
# Section: REVOKE — removing privileges
# ============================================================================

section "REVOKE: specific priv / ALL / GRANT OPTION / IF EXISTS / roles"

# REVOKE specific priv: after revocation the action must fail.
fresh_user "u_rv"
root_sql "GRANT SELECT, INSERT, UPDATE ON ${SCHEMA}.t1 TO \`u_rv\`@localhost;"
assert_ok     "u_rv" "" "${SCHEMA}" "SELECT 1 FROM ${SCHEMA}.t1 LIMIT 1" "REVOKE pre-check: SELECT works before revoke"
root_sql "REVOKE SELECT ON ${SCHEMA}.t1 FROM \`u_rv\`@localhost;"
assert_denied "u_rv" "" "${SCHEMA}" "SELECT 1 FROM ${SCHEMA}.t1 LIMIT 1" "REVOKE SELECT: subsequent SELECT denied"
# Untouched privs should remain.
assert_ok     "u_rv" "" "${SCHEMA}" "INSERT INTO ${SCHEMA}.t1 VALUES (401,1,'r')" "REVOKE SELECT: INSERT still works"
drop_user "\`u_rv\`@localhost"

# REVOKE ALL PRIVILEGES strips every non-GRANT-OPTION priv but keeps the user.
fresh_user "u_rvall"
root_sql "GRANT SELECT, INSERT, UPDATE, DELETE ON ${SCHEMA}.t1 TO \`u_rvall\`@localhost;"
root_sql "REVOKE ALL PRIVILEGES ON ${SCHEMA}.t1 FROM \`u_rvall\`@localhost;"
assert_denied "u_rvall" "" "${SCHEMA}" "SELECT 1 FROM ${SCHEMA}.t1 LIMIT 1" "REVOKE ALL: SELECT denied after"
assert_denied "u_rvall" "" "${SCHEMA}" "INSERT INTO ${SCHEMA}.t1 VALUES (410,1,'r')" "REVOKE ALL: INSERT denied after"
# User row still present — USAGE-only.
out=$(root_sql "SHOW GRANTS FOR \`u_rvall\`@localhost")
if echo "${out}" | grep -q "USAGE"; then
    log_pass "REVOKE ALL: user remains with USAGE-only grant"
else
    log_fail "REVOKE ALL: unexpected post-revoke grants" "${out}"
fi
drop_user "\`u_rvall\`@localhost"

# REVOKE GRANT OPTION only — priv stays, but holder can no longer re-grant.
fresh_user "u_rvgo"
fresh_user "u_rvgo_recv"
root_sql "GRANT SELECT ON ${SCHEMA}.* TO \`u_rvgo\`@localhost WITH GRANT OPTION;"
assert_ok "u_rvgo" "" "${SCHEMA}" \
    "GRANT SELECT ON ${SCHEMA}.t1 TO \`u_rvgo_recv\`@localhost" \
    "REVOKE GRANT OPTION pre-check: re-grant works"
root_sql "REVOKE GRANT OPTION ON ${SCHEMA}.* FROM \`u_rvgo\`@localhost;"
assert_denied "u_rvgo" "" "${SCHEMA}" \
    "GRANT SELECT ON ${SCHEMA}.t2 TO \`u_rvgo_recv\`@localhost" \
    "REVOKE GRANT OPTION: re-grant now denied"
# But the underlying SELECT is preserved.
assert_ok "u_rvgo" "" "${SCHEMA}" "SELECT 1 FROM ${SCHEMA}.t1 LIMIT 1" \
    "REVOKE GRANT OPTION: SELECT itself survives"
drop_user "\`u_rvgo\`@localhost"
drop_user "\`u_rvgo_recv\`@localhost"

# REVOKE ALL PRIVILEGES, GRANT OPTION FROM user — blanket wipe form.
fresh_user "u_rvblank"
root_sql "GRANT SELECT, INSERT ON ${SCHEMA}.* TO \`u_rvblank\`@localhost WITH GRANT OPTION;
         GRANT PROCESS ON *.* TO \`u_rvblank\`@localhost;"
root_sql "REVOKE ALL PRIVILEGES, GRANT OPTION FROM \`u_rvblank\`@localhost;"
out=$(root_sql "SHOW GRANTS FOR \`u_rvblank\`@localhost")
# After the blanket form only the USAGE row should remain.
non_usage=$(echo "${out}" | grep -cvE 'USAGE|Grants for|--------------|^$|^ *$')
if [ "${non_usage}" -eq 0 ]; then
    log_pass "REVOKE ALL PRIVILEGES, GRANT OPTION: blanket wipe leaves only USAGE"
else
    log_fail "REVOKE ALL PRIVILEGES, GRANT OPTION: residual grants" "${out}"
fi
drop_user "\`u_rvblank\`@localhost"

# REVOKE on a never-granted priv errors at the table/column level (1147
# "no such grant") but is silently tolerated at the global level when
# nothing matches. MariaDB does NOT implement `REVOKE IF EXISTS` — only
# CREATE/DROP USER and CREATE/DROP ROLE support IF [NOT] EXISTS.
fresh_user "u_rvie"
if root_sql_allow_fail "REVOKE SELECT ON ${SCHEMA}.t1 FROM \`u_rvie\`@localhost" > /dev/null; then
    log_fail "REVOKE never-granted table priv: expected 1147 error, got success" ""
else
    log_pass "REVOKE never-granted table priv: errors (1147 'no such grant')"
fi
# Confirm the `IF EXISTS` clause is NOT accepted by the parser — this is
# the gap MDEV-28471 (et al) tracks. A syntax error here is the
# expected behavior on current MariaDB.
out=$(root_sql_allow_fail "REVOKE IF EXISTS SELECT ON ${SCHEMA}.t1 FROM \`u_rvie\`@localhost")
if echo "${out}" | grep -qE 'syntax'; then
    log_pass "REVOKE IF EXISTS: parser rejects (feature not in MariaDB 13.0)"
else
    log_fail "REVOKE IF EXISTS: expected parser rejection" "${out}"
fi
drop_user "\`u_rvie\`@localhost"

# Unauthorized REVOKE: a user with no CREATE USER / no GRANT OPTION on the
# target privilege cannot revoke it from someone else.
fresh_user "u_rv_victim"
fresh_user "u_rv_attacker"
root_sql "GRANT SELECT ON ${SCHEMA}.t1 TO \`u_rv_victim\`@localhost;
         GRANT SELECT ON ${SCHEMA}.t1 TO \`u_rv_attacker\`@localhost;"
assert_denied "u_rv_attacker" "" "${SCHEMA}" \
    "REVOKE SELECT ON ${SCHEMA}.t1 FROM \`u_rv_victim\`@localhost" \
    "REVOKE: attacker without GRANT OPTION cannot revoke victim's priv"
drop_user "\`u_rv_victim\`@localhost"
drop_user "\`u_rv_attacker\`@localhost"

# Holder with GRANT OPTION can revoke the priv from recipients they granted to.
fresh_user "u_rvgo2"
fresh_user "u_rvgo2_recv"
root_sql "GRANT SELECT ON ${SCHEMA}.t1 TO \`u_rvgo2\`@localhost WITH GRANT OPTION;"
assert_ok "u_rvgo2" "" "${SCHEMA}" \
    "GRANT SELECT ON ${SCHEMA}.t1 TO \`u_rvgo2_recv\`@localhost" \
    "REVOKE via GRANT OPTION: pre-grant step"
assert_ok "u_rvgo2" "" "${SCHEMA}" \
    "REVOKE SELECT ON ${SCHEMA}.t1 FROM \`u_rvgo2_recv\`@localhost" \
    "REVOKE via GRANT OPTION: holder can revoke what they granted"
drop_user "\`u_rvgo2\`@localhost"
drop_user "\`u_rvgo2_recv\`@localhost"

# REVOKE role — dropping a role from a user removes the role's privileges
# (already exercised in the Roles section but test the standalone REVOKE
# grammar here for completeness).
root_sql_allow_fail "DROP ROLE IF EXISTS r_rv;" >/dev/null
root_sql "CREATE ROLE r_rv; GRANT SELECT ON ${SCHEMA}.t1 TO r_rv;"
fresh_user "u_rvrole"
root_sql "GRANT r_rv TO \`u_rvrole\`@localhost; SET DEFAULT ROLE r_rv FOR \`u_rvrole\`@localhost;"
assert_ok "u_rvrole" "" "${SCHEMA}" "SELECT 1 FROM ${SCHEMA}.t1 LIMIT 1" "REVOKE role pre-check: access via role"
root_sql "REVOKE r_rv FROM \`u_rvrole\`@localhost;"
assert_denied "u_rvrole" "" "" "SELECT 1 FROM ${SCHEMA}.t1 LIMIT 1" "REVOKE role: access removed"
drop_user "\`u_rvrole\`@localhost"
root_sql "DROP ROLE r_rv;"

# REVOKE PROXY — unwinds a PROXY grant.
fresh_user "u_rvpx_tgt"
fresh_user "u_rvpx_pxy"
root_sql "GRANT PROXY ON \`u_rvpx_tgt\`@localhost TO \`u_rvpx_pxy\`@localhost;"
out=$(root_sql "SHOW GRANTS FOR \`u_rvpx_pxy\`@localhost" | grep -c "PROXY")
if [ "${out}" -ge 1 ]; then
    log_pass "REVOKE PROXY pre-check: proxy grant visible"
fi
root_sql "REVOKE PROXY ON \`u_rvpx_tgt\`@localhost FROM \`u_rvpx_pxy\`@localhost;"
out=$(root_sql "SHOW GRANTS FOR \`u_rvpx_pxy\`@localhost" | grep -c "PROXY")
if [ "${out}" -eq 0 ]; then
    log_pass "REVOKE PROXY: proxy grant removed"
else
    log_fail "REVOKE PROXY: proxy still listed" "grep count=${out}"
fi
drop_user "\`u_rvpx_tgt\`@localhost"
drop_user "\`u_rvpx_pxy\`@localhost"

# ============================================================================
# Section: Password and account management
# ============================================================================

section "Passwords: CREATE/ALTER/SET PASSWORD"

# CREATE USER ... IDENTIFIED BY — correct password works, wrong one denied.
drop_user "\`u_pw\`@localhost"
root_sql "CREATE USER \`u_pw\`@localhost IDENTIFIED BY 'Corr3ct-Pwd!';"
assert_ok     "u_pw" "Corr3ct-Pwd!" "" "SELECT 1" "CREATE USER IDENTIFIED BY: correct password auths"
assert_denied "u_pw" "wrong"        "" "SELECT 1" "CREATE USER IDENTIFIED BY: wrong password denied"
assert_denied "u_pw" ""             "" "SELECT 1" "CREATE USER IDENTIFIED BY: empty password denied"

# ALTER USER ... IDENTIFIED BY — rotates the password. Old one stops working.
root_sql "ALTER USER \`u_pw\`@localhost IDENTIFIED BY 'Rotated-Pwd#2';"
assert_denied "u_pw" "Corr3ct-Pwd!"  "" "SELECT 1" "ALTER USER IDENTIFIED BY: old password denied after rotate"
assert_ok     "u_pw" "Rotated-Pwd#2" "" "SELECT 1" "ALTER USER IDENTIFIED BY: new password works"

# SET PASSWORD FOR <user> = 'plain' — administrator form.
root_sql "SET PASSWORD FOR \`u_pw\`@localhost = PASSWORD('Third-Pwd\$3');"
assert_ok "u_pw" "Third-Pwd\$3" "" "SELECT 1" "SET PASSWORD FOR <user>: new password works"

# Self-change: current user sets their own password (no CREATE USER needed).
root_sql "ALTER USER \`u_pw\`@localhost IDENTIFIED BY 'Pre-Self1';"
out=$(user_run "u_pw" "Pre-Self1" "" "SET PASSWORD = PASSWORD('Self-Changed2')")
if echo "${out}" | grep -qE '^ERROR'; then
    log_fail "SET PASSWORD (self): user cannot change own password" "${out}"
else
    log_pass "SET PASSWORD (self): user changed own password"
fi
assert_ok     "u_pw" "Self-Changed2" "" "SELECT 1" "Self-changed password authenticates"
assert_denied "u_pw" "Pre-Self1"     "" "SELECT 1" "Self-changed password: old denied"

drop_user "\`u_pw\`@localhost"

# Cross-user password change: a user without CREATE USER cannot change
# another user's password.
root_sql "CREATE USER \`u_pw_tgt\`@localhost IDENTIFIED BY 'Target-Pw1';"
fresh_user "u_pw_attacker"
assert_denied "u_pw_attacker" "" "" \
    "SET PASSWORD FOR \`u_pw_tgt\`@localhost = PASSWORD('Hijacked')" \
    "SET PASSWORD: non-CREATE-USER cannot change another's password"
assert_denied "u_pw_attacker" "" "" \
    "ALTER USER \`u_pw_tgt\`@localhost IDENTIFIED BY 'Hijacked2'" \
    "ALTER USER: non-CREATE-USER cannot rotate another's password"
# Target's original password should still work.
assert_ok "u_pw_tgt" "Target-Pw1" "" "SELECT 1" "Cross-user password change: target's original password intact"
drop_user "\`u_pw_tgt\`@localhost"
drop_user "\`u_pw_attacker\`@localhost"

section "Passwords: expiry / lock / TLS / resource limits / IF NOT EXISTS"

# PASSWORD EXPIRE — user with an expired password can connect but gets
# "must SET PASSWORD" on any other statement.
drop_user "\`u_pwx\`@localhost"
root_sql "CREATE USER \`u_pwx\`@localhost IDENTIFIED BY 'Expire-Pw1' PASSWORD EXPIRE;"
out=$(user_run "u_pwx" "Expire-Pw1" "" "SELECT 1")
if echo "${out}" | grep -qE 'must SET PASSWORD|password.*expired|password has expired'; then
    log_pass "PASSWORD EXPIRE: expired user blocked from SELECT until reset"
else
    log_fail "PASSWORD EXPIRE: expected 'must SET PASSWORD' error" "${out}"
fi
# Self-reset of the expired password should be allowed.
out=$(user_run "u_pwx" "Expire-Pw1" "" "SET PASSWORD = PASSWORD('Reset-Pw1')")
if echo "${out}" | grep -qE '^ERROR'; then
    log_fail "PASSWORD EXPIRE: self SET PASSWORD rejected" "${out}"
else
    log_pass "PASSWORD EXPIRE: self SET PASSWORD accepted"
fi
assert_ok "u_pwx" "Reset-Pw1" "" "SELECT 1" "PASSWORD EXPIRE: after self-reset, normal queries work"

# PASSWORD EXPIRE NEVER
root_sql "ALTER USER \`u_pwx\`@localhost PASSWORD EXPIRE NEVER;"
out=$(root_sql "SHOW CREATE USER \`u_pwx\`@localhost")
if echo "${out}" | grep -qE 'PASSWORD EXPIRE NEVER'; then
    log_pass "PASSWORD EXPIRE NEVER: recorded in user definition"
else
    log_fail "PASSWORD EXPIRE NEVER: not reflected in SHOW CREATE USER" "${out}"
fi

# PASSWORD EXPIRE INTERVAL N DAY
root_sql "ALTER USER \`u_pwx\`@localhost PASSWORD EXPIRE INTERVAL 90 DAY;"
out=$(root_sql "SHOW CREATE USER \`u_pwx\`@localhost")
if echo "${out}" | grep -qE 'PASSWORD EXPIRE INTERVAL 90 DAY'; then
    log_pass "PASSWORD EXPIRE INTERVAL N DAY: recorded"
else
    log_fail "PASSWORD EXPIRE INTERVAL N DAY: not reflected in SHOW CREATE USER" "${out}"
fi

drop_user "\`u_pwx\`@localhost"

# ACCOUNT LOCK / UNLOCK
root_sql "CREATE USER \`u_lock\`@localhost IDENTIFIED BY 'Locked-Pw1' ACCOUNT LOCK;"
out=$(user_run "u_lock" "Locked-Pw1" "" "SELECT 1")
if echo "${out}" | grep -qE 'account is locked|ACCOUNT.*LOCK|locked'; then
    log_pass "ACCOUNT LOCK: locked account cannot authenticate"
else
    log_fail "ACCOUNT LOCK: expected 'account is locked' error" "${out}"
fi
root_sql "ALTER USER \`u_lock\`@localhost ACCOUNT UNLOCK;"
assert_ok "u_lock" "Locked-Pw1" "" "SELECT 1" "ACCOUNT UNLOCK: account works after unlock"
root_sql "ALTER USER \`u_lock\`@localhost ACCOUNT LOCK;"
out=$(user_run "u_lock" "Locked-Pw1" "" "SELECT 1")
if echo "${out}" | grep -qE 'account is locked|ACCOUNT.*LOCK|locked'; then
    log_pass "ALTER USER ACCOUNT LOCK: re-lock effective"
else
    log_fail "ALTER USER ACCOUNT LOCK: re-lock not effective" "${out}"
fi
drop_user "\`u_lock\`@localhost"

# REQUIRE SSL / NONE / X509 — grammar and persistence. Enforcement needs
# TLS wiring which this harness doesn't set up, so we check that the
# requirement is recorded.
fresh_user "u_ssl"
root_sql "ALTER USER \`u_ssl\`@localhost REQUIRE SSL;"
out=$(root_sql "SHOW CREATE USER \`u_ssl\`@localhost")
if echo "${out}" | grep -q "REQUIRE SSL"; then
    log_pass "REQUIRE SSL: recorded on account"
else
    log_fail "REQUIRE SSL: not recorded" "${out}"
fi
root_sql "ALTER USER \`u_ssl\`@localhost REQUIRE NONE;"
out=$(root_sql "SHOW CREATE USER \`u_ssl\`@localhost")
if ! echo "${out}" | grep -q "REQUIRE SSL"; then
    log_pass "REQUIRE NONE: previous SSL requirement cleared"
else
    log_fail "REQUIRE NONE: SSL requirement still present" "${out}"
fi
drop_user "\`u_ssl\`@localhost"

# Resource limits via CREATE/ALTER USER
fresh_user "u_rl"
root_sql "ALTER USER \`u_rl\`@localhost WITH MAX_QUERIES_PER_HOUR 100 MAX_UPDATES_PER_HOUR 50 MAX_CONNECTIONS_PER_HOUR 10 MAX_USER_CONNECTIONS 3 MAX_STATEMENT_TIME 5;"
out=$(root_sql "SHOW CREATE USER \`u_rl\`@localhost")
for lim in \
    "MAX_QUERIES_PER_HOUR 100" \
    "MAX_UPDATES_PER_HOUR 50" \
    "MAX_CONNECTIONS_PER_HOUR 10" \
    "MAX_USER_CONNECTIONS 3" \
    "MAX_STATEMENT_TIME 5" \
; do
    if echo "${out}" | grep -q "${lim}"; then
        log_pass "Resource limit: ${lim} recorded"
    else
        log_fail "Resource limit: ${lim} missing" "${out}"
    fi
done
drop_user "\`u_rl\`@localhost"

# CREATE USER IF NOT EXISTS / DROP USER IF EXISTS — idempotence.
drop_user "\`u_ine\`@localhost"
root_sql "CREATE USER IF NOT EXISTS \`u_ine\`@localhost IDENTIFIED BY 'Pw1';"
# Second CREATE IF NOT EXISTS on the same name should be a no-op (warning only).
if root_sql_allow_fail "CREATE USER IF NOT EXISTS \`u_ine\`@localhost IDENTIFIED BY 'Pw2'" > /dev/null; then
    log_pass "CREATE USER IF NOT EXISTS: idempotent (no error on repeat)"
else
    log_fail "CREATE USER IF NOT EXISTS: repeat errored" ""
fi
# Confirm password was NOT changed by the second IF NOT EXISTS.
assert_ok     "u_ine" "Pw1" "" "SELECT 1" "CREATE USER IF NOT EXISTS: password NOT overwritten on repeat"
assert_denied "u_ine" "Pw2" "" "SELECT 1" "CREATE USER IF NOT EXISTS: 2nd-call password has no effect"
# DROP USER IF EXISTS — once real, once no-op.
if root_sql_allow_fail "DROP USER IF EXISTS \`u_ine\`@localhost" > /dev/null; then
    log_pass "DROP USER IF EXISTS: removes existing user"
fi
if root_sql_allow_fail "DROP USER IF EXISTS \`u_ine\`@localhost" > /dev/null; then
    log_pass "DROP USER IF EXISTS: no-op on missing user"
else
    log_fail "DROP USER IF EXISTS: errored on missing user" ""
fi

# RENAME USER — preserves privileges.
root_sql "CREATE USER \`u_rn\`@localhost IDENTIFIED BY 'Rn-Pw1';
         GRANT SELECT ON ${SCHEMA}.t1 TO \`u_rn\`@localhost;"
assert_ok "u_rn" "Rn-Pw1" "" "SELECT 1 FROM ${SCHEMA}.t1 LIMIT 1" "RENAME USER pre-check: old name works"
root_sql "RENAME USER \`u_rn\`@localhost TO \`u_rn2\`@localhost;"
assert_ok     "u_rn2" "Rn-Pw1" "" "SELECT 1 FROM ${SCHEMA}.t1 LIMIT 1" "RENAME USER: new name + preserved privs"
assert_denied "u_rn"  "Rn-Pw1" "" "SELECT 1 FROM ${SCHEMA}.t1 LIMIT 1" "RENAME USER: old name no longer authenticates"
drop_user "\`u_rn2\`@localhost"

# ============================================================================
# Section: FLUSH PRIVILEGES semantics
# ============================================================================

section "FLUSH PRIVILEGES: only needed for direct mysql.* table edits"

# Positive side: GRANT + REVOKE take effect immediately WITHOUT a FLUSH
# PRIVILEGES. (The rest of this script relies on this and passes
# deterministically — this section makes the guarantee explicit.)
fresh_user "u_fp_noflush"
root_sql "GRANT SELECT ON ${SCHEMA}.t1 TO \`u_fp_noflush\`@localhost;"
assert_ok "u_fp_noflush" "" "${SCHEMA}" "SELECT 1 FROM ${SCHEMA}.t1 LIMIT 1" \
    "FLUSH PRIVILEGES: GRANT via DDL takes effect without FLUSH"
root_sql "REVOKE SELECT ON ${SCHEMA}.t1 FROM \`u_fp_noflush\`@localhost;"
assert_denied "u_fp_noflush" "" "${SCHEMA}" "SELECT 1 FROM ${SCHEMA}.t1 LIMIT 1" \
    "FLUSH PRIVILEGES: REVOKE via DDL takes effect without FLUSH"
drop_user "\`u_fp_noflush\`@localhost"

# Negative side: direct manipulation of mysql.* does NOT take effect until
# FLUSH PRIVILEGES. Create a user via DDL, then poke mysql.global_priv
# directly to add a global priv, observe it does not apply, then FLUSH and
# observe it now applies.
#
# MariaDB's legacy GRANT tables were merged into the `global_priv` JSON
# document in 10.4. Adding Select_priv at the JSON level is awkward; the
# classic demonstration uses mysql.tables_priv which still exists.
fresh_user "u_fp_direct"
# Baseline: no access to ${SCHEMA}.t1.
assert_denied "u_fp_direct" "" "${SCHEMA}" "SELECT 1 FROM ${SCHEMA}.t1 LIMIT 1" \
    "FLUSH PRIVILEGES: baseline — direct user has no access"

# Insert a table-level Select_priv row directly (bypassing GRANT DDL).
root_sql "INSERT INTO mysql.tables_priv (Host, Db, User, Table_name, Grantor, Timestamp, Table_priv, Column_priv)
          VALUES ('localhost','${SCHEMA}','u_fp_direct','t1','root@localhost', NOW(), 'Select', '');"
# Without FLUSH PRIVILEGES the in-memory ACL cache is unchanged.
assert_denied "u_fp_direct" "" "${SCHEMA}" "SELECT 1 FROM ${SCHEMA}.t1 LIMIT 1" \
    "FLUSH PRIVILEGES: direct mysql.tables_priv insert does NOT apply pre-FLUSH"
root_sql "FLUSH PRIVILEGES;"
assert_ok "u_fp_direct" "" "${SCHEMA}" "SELECT 1 FROM ${SCHEMA}.t1 LIMIT 1" \
    "FLUSH PRIVILEGES: after FLUSH, direct-insert priv is live"
# Clean up: delete the row and re-flush.
root_sql "DELETE FROM mysql.tables_priv WHERE User='u_fp_direct'; FLUSH PRIVILEGES;"
drop_user "\`u_fp_direct\`@localhost"

# ============================================================================
# Final summary
# ============================================================================

echo
echo "${C_BLD}=======================  Summary  =======================${C_END}"
echo "  ${C_GRN}PASS${C_END}: ${PASS}"
echo "  ${C_RED}FAIL${C_END}: ${FAIL}"
echo "  ${C_YEL}SKIP${C_END}: ${SKIP}"

if [ ${FAIL} -gt 0 ]; then
    echo
    echo "${C_BLD}Failures:${C_END}"
    for f in "${FAIL_LIST[@]}"; do
        echo "  - ${f}"
    done
fi

if [ ${SKIP} -gt 0 ]; then
    echo
    echo "${C_BLD}Skipped:${C_END}"
    for s in "${SKIP_LIST[@]}"; do
        echo "  - ${s}"
    done
fi

echo
[ ${FAIL} -eq 0 ] && echo "${C_GRN}All enforced privileges behaved as expected.${C_END}" \
                 || echo "${C_RED}${FAIL} failures need investigation.${C_END}"

# Shut down (ignoring errors — the user's normal workflow is to re-run ./anc).
"${BASEDIR}/stop" >/dev/null 2>&1 || true

exit ${FAIL}
