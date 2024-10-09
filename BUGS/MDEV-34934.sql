CREATE TABLE t (c INT) ENGINE=InnoDB;
BEGIN;
SET sql_mode='',foreign_key_checks=0,unique_checks=0;
INSERT INTO t VALUES (1);
SET unique_checks=1;
CREATE TEMPORARY SEQUENCE f;

CREATE TABLE t (c INT) ENGINE=InnoDB;
BEGIN;
SET sql_mode='',foreign_key_checks=0,unique_checks=0;
INSERT INTO t VALUES (1);
SET foreign_key_checks=1;
CREATE TEMPORARY SEQUENCE f;
