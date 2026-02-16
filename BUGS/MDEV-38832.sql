CREATE TABLE t (c2 ENUM ('') CHARACTER SET 'BINARY' COLLATE 'BINARY')Engine=InnoDB;
SET GLOBAL innodb_flush_log_at_trx_commit=0;
SET GLOBAL innodb_stats_persistent=OFF;
DROP SCHEMA test;

SET max_session_mem_used=8192;
CREATE TABLE t (a INT,b VECTOR (5) NOT NULL,VECTOR INDEX (b) ) ENGINE=INNODB;
SET GLOBAL innodb_flush_log_at_trx_commit=0;
DROP DATABASE test;
