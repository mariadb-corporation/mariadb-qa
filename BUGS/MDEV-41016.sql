SET GLOBAL innodb_adaptive_hash_index=ON;
CREATE TABLE t (a INT PRIMARY KEY) ENGINE=InnoDB;
BEGIN;
INSERT INTO t SELECT seq FROM seq_1_to_200;
SELECT COUNT(*) FROM t AS t1 JOIN t AS t2 ON t1.a=t2.a;
SET GLOBAL innodb_adaptive_hash_index=IF_SPECIFIED;
ROLLBACK;
