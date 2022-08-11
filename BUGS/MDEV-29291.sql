# mysqld options required for replay: --innodb-buffer-pool-size=300M
# Repeat testcase a number of times, then shutdown
DROP DATABASE test;
CREATE DATABASE test;
USE test;
SET sql_mode='';
ALTER TABLE t1 RENAME TO t2;
CREATE TABLE t1 (a INT) ENGINE=InnoDB PARTITION BY HASH (a) PARTITIONS 1024;
INSERT INTO t1 VALUES (1),(3),(5),(7);
CREATE TABLE q (b TEXT CHARSET latin1, FULLTEXT (b)) ENGINE=InnoDB;
