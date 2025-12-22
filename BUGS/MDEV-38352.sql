CREATE TABLE t2 (c INT);
SET debug_dbug='+d,page_intermittent_checksum_mismatch,ib_rename_indexes_too_many__trxs,log_write_fail';
DROP TABLE t2;
SET GLOBAL innodb_lru_scan_depth=86400;
CREATE TABLE t2 (b INT);
INSERT INTO t2 VALUES (1);
