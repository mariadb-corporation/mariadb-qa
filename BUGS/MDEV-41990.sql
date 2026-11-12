CREATE TABLE t1 (a INT PRIMARY KEY, b INT) ENGINE=InnoDB PARTITION BY HASH (a) PARTITIONS 4;
INSERT INTO t1 SELECT seq, seq FROM seq_1_to_1000;
SET SESSION innodb_table_lock_on_full_scan= ON;
BEGIN;
DELETE FROM t1;
SELECT trx_rows_locked FROM information_schema.INNODB_TRX WHERE trx_mysql_thread_id = CONNECTION_ID();
ROLLBACK;
#CLI: 1004; expected 0
#ERR: - (no error)
