CREATE TABLE t (c2 ENUM ('') CHARACTER SET 'BINARY' COLLATE 'BINARY')Engine=InnoDB;
SET GLOBAL innodb_flush_log_at_trx_commit=0;
SET GLOBAL innodb_stats_persistent=OFF;
DROP SCHEMA test;
