CREATE TABLE t1 (pk INT PRIMARY KEY, c1 VARCHAR(10), c2 INT, KEY i2 (c1, c2)) ENGINE=MyISAM;
INSERT INTO t1 VALUES (1, 'b ', NULL), (6, 'b', 7);
SELECT COUNT(pk) FROM t1 FORCE INDEX (i2) WHERE c1 = 'b ' AND c2 + 0 = 7;
#CLI: 0; expected 1 (as with IGNORE INDEX (i2))
#ERR: - (no error)
