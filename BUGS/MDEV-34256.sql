CREATE TEMPORARY TABLE t1(c1 MEDIUMTEXT) ENGINE=InnoDB;
SET GLOBAL innodb_immediate_scrub_data_uncompressed=1;
INSERT INTO t1 VALUES (repeat(1,16777215));
DROP TEMPORARY TABLE t1;
SET GLOBAL innodb_truncate_temporary_tablespace_now=1;
SET @@GLOBAL.innodb_buffer_pool_size=10485760;
