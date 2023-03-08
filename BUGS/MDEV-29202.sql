# mysqld options required for replay: --log-bin
SET autocommit=OFF;
SET GLOBAL wsrep_gtid_mode=ON;
SET SESSION binlog_format=statement;
ALTER TABLE t0 MODIFY a TIMESTAMP;
CREATE TEMPORARY TABLE t0 (c0 INT);
