# Repeat till server crashes (may take 20+ minutes)
DROP DATABASE test;
CREATE DATABASE test;
USE test;
SET GLOBAL innodb_limit_optimistic_insert_debug=7;
CREATE TABLE t1 (c1 INT) PARTITION BY HASH (c1) PARTITIONS 15;
SET GLOBAL innodb_change_buffering_debug=1;
DROP TABLE t1;
SELECT SUBSTRING ('00', 1, 1);
