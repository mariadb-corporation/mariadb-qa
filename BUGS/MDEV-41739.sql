CREATE TABLE t1 (a INT PRIMARY KEY, b VARCHAR(10), FULLTEXT(b)) ENGINE=InnoDB;
INSERT INTO t1 VALUES (1,'x'),(2,'x'),(3,'x');
SET DEBUG_SYNC='innodb_inplace_alter_table_enter SIGNAL ddl WAIT_FOR dml';
SET DEBUG_SYNC='lock_wait_start SIGNAL ddl_wait';
ALTER TABLE t1 ADD UNIQUE(b);
SET DEBUG_SYNC='now WAIT_FOR ddl';
SET DEBUG_SYNC='fts_instrument_sync_request SIGNAL dml WAIT_FOR go';
UPDATE t1 SET b='y' WHERE a=1;
SET DEBUG_SYNC='now WAIT_FOR ddl_wait';
SET DEBUG_SYNC='lock_wait_start SIGNAL go';
DELETE FROM t1 WHERE a=2;

