# Repeat till it crashes
DROP DATABASE test;
CREATE DATABASE test;
USE test;
CREATE TABLE t1 (a INT,b INT,c INT,d INT,PRIMARY KEY(a),KEY(b),KEY(c),KEY(d)) ENGINE=InnoDB;
SET unique_checks=0,foreign_key_checks=0,autocommit=0;
INSERT INTO t1 VALUES (0,0,0,0);
SET @@unique_checks=1;
CREATE TEMPORARY SEQUENCE s1;
