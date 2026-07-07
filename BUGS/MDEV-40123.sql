CREATE TABLE t1 (pk INT AUTO_INCREMENT PRIMARY KEY, col_int INT, col_int_key INT NOT NULL, col_bigint BIGINT, KEY col_int_key (col_int_key)) ENGINE=InnoDB;
INSERT INTO t1 (col_int,col_int_key,col_bigint) VALUES (9,9,9),(9,9,109),(9,19,19),(9,29,29),(9,39,39);
SELECT col_bigint FROM t1 WHERE pk=1 FOR UPDATE;
SET DEBUG_SYNC='lock_trx_handle_wait_enter WAIT_FOR go';
SELECT col_bigint FROM t1 WHERE col_int=9 ORDER BY col_int_key LIMIT 4 FOR UPDATE SKIP LOCKED;
SELECT COUNT(*) FROM information_schema.INNODB_TRX WHERE trx_state='LOCK WAIT';
SET DEBUG_SYNC='now SIGNAL go';
