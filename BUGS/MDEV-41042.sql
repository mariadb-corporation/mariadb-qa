# mysqld options required for replay:  --innodb-rollback-on-timeout=1
CREATE DATABASE db1;
BEGIN;
SELECT COUNT(*) INTO @c FROM mysql.innodb_table_stats FOR UPDATE;
SET innodb_lock_wait_timeout=1;
DROP DATABASE db1;
