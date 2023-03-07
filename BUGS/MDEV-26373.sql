# mysqld options required for replay: --enforce-storage-engine=InnoDB 
SET sql_mode='';
ALTER TABLE mysql.slow_log ENGINE=MyISAM;
SET tx_read_only=1;
SET SESSION long_query_time=0;
SET SESSION slow_query_log=1;
SET GLOBAL slow_query_log=1;
SET GLOBAL log_output='TABLE,FILE';
ALTER TABLE mysql.slow_log ENGINE=MyISAM;

# mysqld options required for replay: --log_bin --sql_mode=ONLY_FULL_GROUP_BY --max_allowed_packet=33554432 --maximum-bulk_insert_buffer_size=1M --maximum-join_buffer_size=1M --maximum-max_heap_table_size=1M --maximum-max_join_size=1M --maximum-myisam_max_sort_file_size=1M --maximum-myisam_mmap_size=1M --maximum-myisam_sort_buffer_size=1M --maximum-optimizer_trace_max_mem_size=1M --maximum-preload_buffer_size=1M --maximum-query_alloc_block_size=1M --maximum-query_prealloc_size=1M --maximum-range_alloc_block_size=1M --maximum-read_buffer_size=1M --maximum-read_rnd_buffer_size=1M --maximum-sort_buffer_size=1M --maximum-tmp_table_size=1M --maximum-transaction_alloc_block_size=1M --maximum-transaction_prealloc_size=1M --log-output=none --innodb_file_per_table=1 --innodb_flush_method=O_DIRECT --log-slow-rate-limit=2047 --tmp-memory-table-size=24
CREATE OR REPLACE TABLE mysql.general_log (a INT) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS t1 (a INT) SELECT 3 AS a;
SET GLOBAL general_log=ON;
SET GLOBAL log_output='TABLE,TABLE';
SET SESSION tx_read_only=1;
SET SESSION AUTOCOMMIT=0;
SELECT 't1 ROWs AFTER SMALL DELETE', COUNT(*) FROM t1;
SET SESSION tx_read_only=0;
INSERT INTO t1 VALUES (1);
SELECT SLEEP (3);
SET SESSION tx_read_only=1;  # added for looping

SET sql_mode=ORACLE;
SET @@session.enforce_storage_engine=innodb;
ALTER TABLE mysql.general_log engine = CSV;
SET GLOBAL tx_read_only=1;
SET GLOBAL general_log=ON;
SET GLOBAL log_output='TABLE,FILE';
SELECT 1;

SET sql_mode='';
SET SESSION enforce_storage_engine=InnoDB;
CREATE TABLE t (ind SET('') DEFAULT'',string1 CHAR,KEY(ind)) ENGINE=Spider DEFAULT CHARSET=utf8;
ALTER TABLE mysql.general_log ENGINE=MyISAM;
SET SESSION tx_read_only=ON;
XA START 'a';
SET GLOBAL log_output='TABLE';
SELECT * FROM t;
SET GLOBAL general_log=ON;

SET sql_mode='',enforce_storage_engine=InnoDB;
ALTER TABLE mysql.general_log ENGINE=MyISAM;
SET unique_checks=0,tx_read_only=ON,foreign_key_checks=0;
SET GLOBAL general_log=ON;
SET GLOBAL log_output='TABLE,FILE';
SELECT 1;
