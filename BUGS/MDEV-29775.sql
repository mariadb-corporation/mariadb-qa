SET GLOBAL wsrep_mode=replicate_myisam;
SET GLOBAL wsrep_forced_binlog_format=STATEMENT;
CREATE TABLE t (f0 CHAR(0)) ENGINE=MyISAM;
INSERT INTO t VALUES();
