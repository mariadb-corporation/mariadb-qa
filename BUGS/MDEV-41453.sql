CREATE TABLE t1 (a ENUM('a','b','c'));
INSERT INTO t1 VALUES ('a');
CREATE TABLE t2 (i INT);
INSERT INTO t2 VALUES (1);
SELECT a = 1, a IN (SELECT i FROM t2) FROM t1;
#CLI: 1 and 0; expected 1 and 1
#ERR: - (no error)
