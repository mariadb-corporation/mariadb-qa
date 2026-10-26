# Requires MTR: kill -9 the server while the CREATE OR REPLACE runs, then restart it; ref bug report for MTR testcase
CREATE TABLE t0 (a INT) ENGINE=InnoDB;
INSERT INTO t0 SELECT seq FROM seq_1_to_3000000;
CREATE TABLE t1 (b INT) ENGINE=InnoDB PARTITION BY HASH (b) PARTITIONS 2;
INSERT INTO t1 VALUES (10),(20);
CREATE OR REPLACE TABLE t1 (a INT) ENGINE=InnoDB PARTITION BY HASH (a) PARTITIONS 2 SELECT a FROM t0;
SELECT COUNT(*) FROM t1;
#CLI: returns 0; expected 2
#ERR: [ERROR] DDL_LOG: Got error 1050 when trying to execute action for entry 1 of type 'rename table'
