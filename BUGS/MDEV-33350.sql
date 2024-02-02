# Requires standard m/s setup
SET sql_mode='',unique_checks=0,foreign_key_checks=0,autocommit=0;
CREATE TABLE t1 (c1 INT UNIQUE KEY) ENGINE=InnoDB;
CREATE TABLE t2 (c1 BINARY (0),c2 INT UNIQUE KEY) ENGINE=InnoDB;
INSERT INTO t2 VALUES (0,0);
INSERT INTO t1 VALUES (0,0);
CREATE TEMPORARY TABLE t1 (c INT);
INSERT INTO t2 VALUES (0,0);
