CREATE TABLE t (c INT) ENGINE=INNODB;
SET SESSION wsrep_trx_fragment_size=1;
XA START 'a';
SELECT count(1) FROM mysql.user;
SET GLOBAL wsrep_trx_fragment_size=DEFAULT;
INSERT INTO t (c) VALUES (1);
SAVEPOINT cc;
XA END 'a';
XA PREPARE 'a';
