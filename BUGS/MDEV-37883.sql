# mysqld options required for replay: --innodb-undo-tablespaces=0 --innodb-data-file-path=ibdata1:12M
SET GLOBAL innodb_file_per_table=0;
CREATE TABLE t (a LONGTEXT, FULLTEXT(a)) STATS_PERSISTENT=0;
INSERT INTO t VALUES (REPEAT('a',1048576)),(REPEAT('a',1048576));
DROP TABLE t;

# mysqld options required for replay: --log_bin --maximum-myisam_mmap_size=1M --maximum-myisam_sort_buffer_size=1M --maximum-optimizer_trace_max_mem_size=1M --maximum-preload_buffer_size=1M --maximum-query_alloc_block_size=1M --maximum-query_prealloc_size=1M --maximum-range_alloc_block_size=1M --max_allowed_packet=33554432 --maximum-bulk_insert_buffer_size=1M --maximum-join_buffer_size=1M --maximum-max_heap_table_size=1M --maximum-max_join_size=1M
SET DEBUG_DBUG='+d,page_intermittent_checksum_mismatch,ib_rename_indexes_too_many_concurrent_trxs,log_write_fail';
INSERT INTO sbtest1 VALUES;
CREATE TABLE t1 (pk INT PRIMARY KEY,c TEXT) ENGINE=INNODB;
CREATE TABLE t1 (c1 BIGINT,c2 VARBINARY,c3 INTEGER,c4 VARBINARY PRIMARY KEY,c5 BIGINT UNIQUE KEY,c6 NUMERIC(10,8) DEFAULT 3.141592);
insert into t1 VALUES (2,12);
SET DEBUG_DBUG='+d,ib_build_indexes_too_many_concurrent_trxs,ib_rename_indexes_too_many_concurrent_trxs';
SELECT * t1;
SET @@global.INNODB_lru_scan_depth = 86400;
SELECT SLEEP;
ALTER TABLE t1 ADD FULLTEXT KEY ft_colte (c);
ALTER TABLE t1 ADD FULLTEXT KEY ft_colte (c);
