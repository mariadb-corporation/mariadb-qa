CREATE TABLE t1 (a int) engine=innodb;
XA START 'a';
INSERT INTO t1 SELECT seq FROM seq_1_to_10000;
SELECT count(*) a from mysql.db;
SAVEPOINT s1;
INSERT INTO t1 SELECT * FROM t1;
XA END 'a';
XA PREPARE 'a';
XA COMMIT 'a';
