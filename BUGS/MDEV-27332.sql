# mysqld options required for replay:  --innodb-force-recovery=5
XA START 'a';
SELECT * FROM mysql.innodb_index_stats;
SELECT trx_state,trx_isolation_level,trx_LAST_FOREIGN_KEY_ERROR FROM information_schema.innodb_trx;
