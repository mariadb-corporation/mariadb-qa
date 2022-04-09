SET unique_checks=0,foreign_key_checks=0,autocommit=0;
CREATE TABLE t (c CHAR(1));
INSERT INTO t VALUES();
SET SESSION foreign_key_checks=TRUE;
CREATE TEMPORARY SEQUENCE s1;
