CREATE TABLE t1 ( c1 int, c2 int, c3 int, c4 int, c5 int, key (c1), key (c5)) ENGINE=InnoDB;
INSERT INTO t1 VALUES (NULL, 15, NULL, 2012, NULL) , (NULL, 12, 2008, 2004, 2021) , (2003, 11, 2031, NULL, NULL);
CREATE TABLE t2 SELECT c2 AS f FROM t1;
UPDATE t2 SET f = 0 WHERE f NOT IN ( SELECT c2 AS c1 FROM t1 WHERE c5 IS NULL AND c1 IS NULL );

# Keep repeating the following testcase in quick succession till mysqld crashes. Sporadic.
DROP DATABASE test;
CREATE DATABASE test;
USE test;
CREATE TABLE t (column_name_1 INT, column_name_2 VARCHAR(52)) ENGINE=InnoDB;
XA START 'a';
SET MAX_STATEMENT_TIME = 0.001;
INSERT INTO t VALUES (101,NULL),(102,NULL),(103,NULL),(104,NULL),(105,NULL),(106,NULL),(107,NULL),(108,NULL),(109,NULL),(1010,NULL);
CHECKSUM TABLE t, INFORMATION_SCHEMA.tables;
SELECT SLEEP(3);

# Keep repeating the following testcase in quick succession till mysqld crashes. Sporadic (~1/10)
CREATE TABLE t(c INT) ENGINE=InnoDB;
SELECT REVERSE(t) FROM t;
SET max_statement_time=0.000001;
EXPLAIN SELECT * FROM t;
PREPARE p FROM 'CHECKSUM TABLE t';
EXECUTE p;

# Keep pasting into client in quick succession till mariadbd crashes. Sporadic (~1/10)
SET sql_mode='', @@max_statement_time=0.0001;
CREATE TEMPORARY TABLE t3 (c VARCHAR PRIMARY KEY,c2 INT,c3 TIME) ENGINE=Aria;
CREATE TABLE t1(a int) ENGINE=FEDERATED COMMENT='';
SET @@GLOBAL.OPTIMIZER_SWITCH="join_cache_bka=ON";
RENAME TABLE InnoDB.procs_priv TO procs_priv_backup;
INSERT INTO t1 VALUES;
CHECKSUM TABLE t1,t2,t3;
