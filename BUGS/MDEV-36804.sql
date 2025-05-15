# mysqld options required for replay:  --log_bin=binlog --binlog_format=ROW
CREATE TABLE t (c INT);
XA START 'a';
SAVEPOINT s;
INSERT INTO t VALUES (1);
CREATE TEMPORARY TABLE t (c INT);
SELECT * FROM mysql.proc;
ROLLBACK WORK TO s;
