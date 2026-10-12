CREATE TABLE t1 (a INT, KEY (a));
INSERT INTO t1 VALUES (2), (20);
SELECT a FROM t1 WHERE a = '2.0.0';
#CLI: 20; expected 2, as with IGNORE INDEX (a)
#ERR: - (no error)
