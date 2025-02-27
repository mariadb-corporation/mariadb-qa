USE test;
SET @@SESSION.optimizer_trace=1;
SET in_predicate_conversion_threshold=2;
CREATE TABLE t1(c1 YEAR);
SELECT * FROM t1 WHERE c1 IN(NOW(),NOW());

SET in_predicate_conversion_threshold=2;
CREATE TABLE t1(c1 YEAR);
SELECT * FROM t1 WHERE c1 IN(NOW(),NOW());
drop table t1;

USE test;
SET IN_PREDICATE_CONVERSION_THRESHOLD=2;
CREATE TABLE t(c BIGINT NOT NULL);
SELECT * FROM t WHERE c IN (CURDATE(),ADDDATE(CURDATE(),'a')) ORDER BY c;

SET @@in_predicate_conversion_threshold=2;
CREATE TABLE t (a INT KEY) ENGINE=InnoDB;
SELECT 1 FROM t WHERE ROW(a, (a,a)) IN ((1, (1,1)),(2, (2,2)));

SET @@in_predicate_conversion_threshold=2;
SELECT 1 FROM (SELECT 1 AS c) AS t WHERE ROW(c,(c,c)) IN ((1,(1,1)),(2,(2,1)));

SET SESSION in_predicate_conversion_threshold=1;
CREATE TABLE t1 (a SERIAL KEY,b INT) ENGINE=InnoDB;
SELECT 1 FROM t1 WHERE ROW(a,(a,a)) IN ((1,(1,1)),(2,(2,1)));
