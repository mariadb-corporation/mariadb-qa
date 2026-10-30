CREATE TABLE t1 (c SET('x','b','a')) PARTITION BY KEY (c) PARTITIONS 7;
INSERT INTO t1 VALUES (''),('x'),('x,b'),('a,b');
SELECT COUNT(*) FROM t1 WHERE c > 'b' AND c < 'x';
CREATE TABLE t2 (e ENUM('x','b','a'));
INSERT INTO t2 VALUES ('x'),('b'),('a'),('b');
ANALYZE TABLE t2 PERSISTENT FOR ALL;
SELECT COUNT(*) FROM t2 WHERE e > 'a' AND e < 'x';
#CLI: 0; expected 1
#CLI: 0; expected 2
#ERR: - (no error)
