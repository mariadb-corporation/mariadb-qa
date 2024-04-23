# Requires MBR or RBR m/s setup
SET binlog_row_image='NOBLOB';
CREATE TABLE t (c INT PRIMARY KEY, d INT, i BLOB GENERATED ALWAYS AS (c), KEY k(i)) ENGINE=InnoDB;
CREATE TEMPORARY TABLE t2 (c INT) ENGINE=InnoDB;
INSERT INTO t (c) VALUES (1);
SELECT * FROM performance_schema.global_status;
UPDATE t SET d=0;
