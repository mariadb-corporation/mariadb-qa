CREATE TABLE t1 (a INT);
INSERT INTO t1 VALUES (1),(2),(3);
DELETE FROM t1 WHERE a IN (SELECT a FROM t1) ORDER BY b;
SELECT COUNT(*) FROM t1;
#CLI: no error, and 0 rows left; expected ERROR 1054 (42S22): Unknown column 'b' in 'ORDER BY', and 3 rows left
#ERR: - (no error)

CREATE TABLE t1 (a INT);
INSERT INTO t1 VALUES (1),(2),(3);
DELETE FROM t1 WHERE a IN (SELECT a FROM t1) ORDER BY nosuchfunc(a);
SELECT COUNT(*) FROM t1;
#CLI: no error, and 0 rows left; expected ERROR 1305 (42000): FUNCTION test.nosuchfunc does not exist, and 3 rows left
#ERR: - (no error)

CREATE TABLE t1 (a INT);
INSERT INTO t1 VALUES (1),(2),(3);
DELETE FROM t1 WHERE a IN (SELECT a FROM t1) ORDER BY nosuchtable.a;
SELECT COUNT(*) FROM t1;
#CLI: no error, and 0 rows left; expected ERROR 1054 (42S22): Unknown column 'nosuchtable.a' in 'ORDER BY', and 3 rows left
#ERR: - (no error)
