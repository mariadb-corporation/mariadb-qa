CREATE TABLE ti (id INT PRIMARY KEY) ENGINE=InnoDB;
SET SESSION sql_mode='ONLY_FULL_GROUP_BY';
SET SESSION wsrep_trx_fragment_size = 1;
CREATE TABLE t1 (a INT, b CHAR(8), PRIMARY KEY(a)) ENGINE=InnoDB;
XA START 't';
SET SESSION wsrep_trx_fragment_unit = 'bytes';
INSERT INTO ti VALUES (100);
SET GLOBAL wsrep_provider_options='repl.max_ws_size=128';
INSERT INTO t1(a) VALUES (REPEAT('a', 2));
