CREATE TABLE t (a CHAR(8), i INT);
INSERT INTO t VALUES ('foo',1),('bar',2);
CREATE VIEW v AS SELECT a, SUM(i) FROM t GROUP BY a;
SELECT * FROM v WHERE a !=SFORMAT ('{}', 'qux');