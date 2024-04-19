CREATE TABLE t (a INT,c INT,filler CHAR,KEY(a,c));
XA START '1';
SET SESSION foreign_key_checks=OFF;
SET SESSION unique_checks=OFF;
INSERT INTO t VALUES();
SET foreign_key_checks=1;
SELECT * FROM t;
