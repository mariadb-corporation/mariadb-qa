CREATE TABLE t1 (f1 VARCHAR(10)) ENGINE=InnoDB;
SET SESSION wsrep_trx_fragment_unit='statements';
SET SESSION wsrep_trx_fragment_size=1;
SET SESSION wsrep_on=OFF;
XA START 't';
SET GLOBAL wsrep_on=ON;
INSERT INTO t1 VALUES ('a');
SELECT * FROM t1 WHERE f1='a' ORDER BY c1;
