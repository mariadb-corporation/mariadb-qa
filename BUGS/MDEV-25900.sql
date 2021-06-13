# mysqld options required for replay:  --log-bin
CREATE DATABASE db CHARACTER SET filename;
USE db;
CREATE TABLE t1 (a CHAR(209)) ENGINE=InnoDB;
CREATE TABLE t2 (c INT) ENGINE=InnoDB;
CREATE TEMPORARY TABLE t3 (c INT) ENGINE=InnoDB;
SELECT * FROM t2 GROUP BY abc LIMIT 1;  # ERROR 1054 (42S22): Unknown column 'abc' in 'group statement'
INSERT INTO t1 VALUES (0);
