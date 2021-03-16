XA START 'b';
SET SESSION wsrep_trx_fragment_unit='statements';
DELETE FROM mysql.innodb_table_stats;
SET SESSION wsrep_trx_fragment_size=1;
CREATE TEMPORARY SEQUENCE s1;