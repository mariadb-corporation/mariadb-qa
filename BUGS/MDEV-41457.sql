CREATE TABLE t1 (a INT);
INSERT INTO t1 VALUES (NULL), (1);
CREATE TABLE t2 (b INT, KEY (b));
INSERT INTO t2 VALUES (NULL), (NULL), (1);
SELECT COUNT(*) FROM t1 JOIN t2 ON t2.b = t1.a WHERE t1.a <=> t2.b;
#CLI: 3; expected 1, as with IGNORE INDEX (b)
#ERR: - (no error)
