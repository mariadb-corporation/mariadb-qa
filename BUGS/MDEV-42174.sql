SET GLOBAL innodb_adaptive_hash_index=ON;
CREATE TABLE t1 (a INT PRIMARY KEY, b VARCHAR(1)) ENGINE=InnoDB;
INSERT INTO t1 SELECT seq,'' FROM seq_1_to_200;
SELECT SUM((SELECT a FROM t1 WHERE a=seq)) FROM seq_1_to_200;
SET GLOBAL innodb_adaptive_hash_index=IF_SPECIFIED;
UPDATE t1 SET b='x';
CHECK TABLE t1;
