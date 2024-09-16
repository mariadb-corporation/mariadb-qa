# mysqld options required for replay:  --log-bin
CREATE DATABASE db CHARACTER SET filename;
USE db;
CREATE TABLE t1 (a CHAR(209)) ENGINE=InnoDB;
CREATE TABLE t2 (c INT) ENGINE=InnoDB;
CREATE TEMPORARY TABLE t3 (c INT) ENGINE=InnoDB;
SELECT * FROM t2 GROUP BY abc LIMIT 1;  # ERROR 1054 (42S22): Unknown column 'abc' in 'group statement'
INSERT INTO t1 VALUES (0);

# mysqld options required for replay: --log_bin 
CREATE TABLE t (a INT,b INT,KEY(a));
SELECT * FROM t INTO OUTFILE 'a';
USE performance_schema;
SET SESSION collation_server=filename;
DROP DATABASE test;  # ERROR 1010 (HY000): Error dropping database (can't rmdir './test', errno: 39 "Directory not empty")
USE test;
CREATE TEMPORARY TABLE tmp (a INT);
LOAD DATA INFILE 'a' INTO TABLE t;
CREATE TABLE t (a CHAR(255),KEY(a));
INSERT INTO t VALUES();

SET SESSION collation_server=filename;
DROP DATABASE test;
CREATE DATABASE test;
USE test;
CREATE TABLE t (a INT UNSIGNED,b INT,c BINARY (8),d BINARY (8),e CHAR(46),f BINARY (13),g BLOB,h BLOB,id INT,KEY(b)) ENGINE=InnoDB;
INSERT INTO t VALUES (+1,+1,0,0,0,0,0,0,0);
ALTER TABLE t CHANGE COLUMN a a CHAR(232);
ALTER TABLE t ENGINE=Aria;
