CREATE TABLE t (c INT,c2 CHAR(5)) ENGINE=InnoDB PARTITION BY LINEAR KEY(c) PARTITIONS 99;
SET GLOBAL innodb_lru_scan_depth=10000;
SELECT SLEEP (1);
SELECT * FROM t;
SET GLOBAL innodb_checksum_algorithm=strict_innodb;
SELECT * FROM mysql.innodb_index_stats;

CREATE TABLE tbl1 (a INT,b INT,KEY(b));
CREATE TABLE tbl2 (f INT KEY);
SELECT SLEEP (1);
SET GLOBAL innodb_checksum_algorithm=strict_innodb;
CREATE TEMPORARY TABLE t (f INT);
INSERT INTO tbl2 SELECT SEQ FROM seq_1_to_3000;
INSERT INTO tbl1 VALUES (+1,0);
INSERT INTO tbl1 VALUES (+1,0);
SET GLOBAL innodb_lru_scan_depth=10000;
INSERT INTO t SELECT 1 FROM tbl2 AS t,tbl2 AS t2;
