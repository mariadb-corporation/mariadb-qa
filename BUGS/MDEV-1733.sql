XA START '0';
SET SESSION wsrep_trx_fragment_size=0;
SET GLOBAL wsrep_forced_binlog_format=STATEMENT;
SET SESSION TRANSACTION READ ONLY;
CREATE TEMPORARY TABLE t (i INT KEY) ENGINE=INNODB;
XA END '0';
XA ROLLBACK '0';
XA START '0';
INSERT INTO t VALUES ('0');
XA END '0';
SET SESSION pseudo_slave_mode=1;
XA PREPARE '0';
