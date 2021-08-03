# mysqld options required for replay: --log_bin=binlog --gtid_strict_mode=1
CREATE TABLE t1(id int) ENGINE=InnoDB;
XA START 'test';
INSERT INTO t1  VALUES(0);
SET SESSION wsrep_trx_fragment_size = 2;
SET GLOBAL wsrep_provider_options='repl.max_ws_size=4096';
SET SESSION wsrep_trx_fragment_unit = 'statements';
SET GLOBAL wsrep_on=OFF;
SET SESSION wsrep_trx_fragment_size = DEFAULT;
