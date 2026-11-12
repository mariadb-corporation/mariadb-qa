CREATE TABLE t1 (a INT, t TEXT, FULLTEXT (t)) ENGINE=MyISAM PARTITION BY HASH (a) PARTITIONS 2;
INSERT INTO t1 VALUES (1, 'apple banana'), (2, 'cherry grape'), (3, 'melon lemon'), (4, 'peach plum');
SELECT COUNT(*) FROM t1 WHERE MATCH (t) AGAINST ('apple');
CREATE TABLE t2 (a INT, t TEXT, FULLTEXT (t)) ENGINE=Aria PARTITION BY HASH (a) PARTITIONS 2;
INSERT INTO t2 SELECT * FROM t1;
SELECT COUNT(*) FROM t2 WHERE MATCH (t) AGAINST ('apple');
#CLI: 0; expected 1
#CLI: 0; expected 1
#ERR: - (no error)
