USE test;
SET collation_connection='utf16_general_ci';
SET sql_buffer_result=1;
CREATE TABLE t(c INT);
INSERT INTO t VALUES(NULL);
SELECT PASSWORD(c) FROM t;

SET collation_connection='utf16_general_ci';
CREATE OR REPLACE TABLE t1(c INT);
INSERT INTO t1 VALUES(NULL);
CREATE OR REPLACE TABLE t2 AS SELECT PASSWORD(c) FROM t1;

SET collation_connection='utf16_general_ci';
CREATE OR REPLACE TABLE t1 AS SELECT PASSWORD(CAST(NULL AS SIGNED));

SET @@sql_buffer_result=ON;
SET collation_connection='utf16_bin';
CREATE TABLE t (c CHAR(1));
INSERT INTO t VALUES (1),(1),(1),(NULL);
INSERT INTO t SELECT * FROM t;
SELECT PASSWORD(c) FROM t;

SET sql_mode='';
SET SESSION sql_buffer_result=1;
CREATE TABLE t1 (c1 INT) ENGINE=InnoDB;
INSERT INTO t1 VALUES ();
INSERT IGNORE INTO t1 VALUES (@a);
SET collation_connection='ucs2_bin';
SELECT PASSWORD(c1) FROM t1;
