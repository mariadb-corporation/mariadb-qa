CREATE TABLE t2 (c INT);
XA START 'a';
INSERT INTO t2 VALUES(1);
SET SESSION pseudo_slave_mode=1;
XA END 'a';
XA PREPARE 'a';
