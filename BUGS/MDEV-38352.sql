CREATE TABLE t2 (c INT);
SET debug_dbug='+d,page_intermittent_checksum_mismatch,ib_rename_indexes_too_many__trxs,log_write_fail';
DROP TABLE t2;
SET GLOBAL innodb_lru_scan_depth=86400;
CREATE TABLE t2 (b INT);
INSERT INTO t2 VALUES (1);

CREATE TABLE t1 (c INT);
SET debug_dbug='+d,page_intermittent_checksum_mismatch';
SET GLOBAL innodb_lru_scan_depth=86400;
CREATE TABLE t2 (b INT);
INSERT INTO t2 VALUES (1);

CREATE TABLE t1 (c INT);
SET debug_dbug='+d,page_intermittent_checksum_mismatch';
SET GLOBAL innodb_lru_scan_depth=86400;
CREATE TABLE t2 (b INT);
CREATE TABLE t3 (b INT);
CREATE TABLE t4 (b INT);
CREATE TABLE t5 (b INT);
CREATE TABLE t6 (b INT);

CREATE TABLE t1 (c INT);
SET debug_dbug='+d,page_intermittent_checksum_mismatch';
SET GLOBAL innodb_lru_scan_depth=86400;
CREATE TABLE t2 (b INT);
INSERT INTO t2 SELECT seq FROM seq_1_to_2000;

CREATE TABLE t1 (c INT);
SET debug_dbug='+d,page_intermittent_checksum_mismatch';
SET GLOBAL innodb_lru_scan_depth=86400;
CREATE TABLE t2 (b INT) PARTITION BY HASH(b) PARTITIONS 4;
INSERT INTO t2 VALUES (1);

SET debug_dbug='+d,page_intermittent_checksum_mismatch';
SET GLOBAL innodb_lru_scan_depth=86400;
CREATE TABLE t1 (b INT);
CREATE TABLE t2 (b INT);
CREATE TABLE t3 (b INT);
CREATE TABLE t4 (b INT);
CREATE TABLE t5 (b INT);
CREATE TABLE t6 (b INT);
CREATE TABLE t7 (b INT);
CREATE TABLE t8 (b INT);
CREATE TABLE t9 (b INT);
CREATE TABLE t10 (b INT);
