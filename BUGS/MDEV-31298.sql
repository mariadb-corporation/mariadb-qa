SET foreign_key_checks=0,unique_checks=0;
CREATE TABLE t1 (c1 CHAR,INDEX (c1)) ENGINE=INNODB;
XA START 'a';
INSERT INTO t1 VALUES();
SET foreign_key_checks=1;
CREATE TEMPORARY SEQUENCE f;
