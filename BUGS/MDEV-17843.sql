# Repeat unlimited. Single thread repeats will eventually show the issue. Sometimes within 10 minutes.
# mysqld options used for replay:  --log-bin --sql_mode=ONLY_FULL_GROUP_BY --maximum-query_alloc_block_size=1M --maximum-query_prealloc_size=1M --maximum-range_alloc_block_size=1M --maximum-read_buffer_size=1M --maximum-read_rnd_buffer_size=1M --maximum-sort_buffer_size=1M --maximum-tmp_table_size=1M --maximum-transaction_alloc_block_size=1M --maximum-transaction_prealloc_size=1M --log-output=none --innodb_file_per_table=1 --innodb_flush_method=O_DIRECT --innodb_stats_persistent=off --loose-idle_write_transaction_timeout=0 --loose-idle_transaction_timeout=0 --loose-idle_readonly_transaction_timeout=0 --connect_timeout=60 --interactive_timeout=28800 --slave_net_timeout=60 --net_read_timeout=30 --net_write_timeout=60 --wait_timeout=28800 --lock-wait-timeout=86400 --innodb-lock-wait-timeout=50 --log_output=FILE --log_bin_trust_function_creators=1 --loose-max-statement-time=30 --loose-debug_assert_on_not_freed_memory=0 --innodb-buffer-pool-size=300M --max_allowed_packet=33554432 --maximum-bulk_insert_buffer_size=1M --maximum-join_buffer_size=1M --maximum-max_heap_table_size=1M --maximum-max_join_size=1M --maximum-myisam_max_sort_file_size=1M --maximum-myisam_mmap_size=1M --maximum-myisam_sort_buffer_size=1M --maximum-optimizer_trace_max_mem_size=1M
DROP DATABASE test;
CREATE DATABASE test;
USE test;
SET @@GLOBAL.rpl_semi_sync_master_enabled=1;
SET @@GLOBAL.innodb_status_output=1;
CREATE TABLE t3 (c1 VARCHAR(2049) BINARY CHARACTER SET 'latin1' COLLATE 'latin1_bin',c2 YEAR,c3 DATETIME(5)) ENGINE=RocksDB PARTITION BY LINEAR HASH((c2)) PARTITIONS 523;
TRUNCATE t3;
TRUNCATE t3;
SELECT 1;
