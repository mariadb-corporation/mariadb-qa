CREATE TABLE t1 (c CHAR(4), KEY (c));
INSERT INTO t1 VALUES ('abc'), ('x'), ('y');
SELECT COUNT(*) FROM t1 WHERE SUBSTR(c, 1, 1) = 'a ';
#CLI: 0; expected 1 (as with IGNORE INDEX (c))
#ERR: - (no error)
