# mysqld options in use at occurrence time: --no-defaults --max_allowed_packet=33554432 --maximum-bulk_insert_buffer_size=1M --maximum-join_buffer_size=1M --maximum-max_heap_table_size=1M --maximum-max_join_size=1M --maximum-myisam_max_sort_file_size=1M --maximum-myisam_mmap_size=1M --maximum-myisam_sort_buffer_size=1M --maximum-optimizer_trace_max_mem_size=1M --maximum-preload_buffer_size=1M --maximum-query_alloc_block_size=1M --maximum-query_prealloc_size=1M --maximum-range_alloc_block_size=1M --maximum-read_buffer_size=1M --maximum-read_rnd_buffer_size=1M --maximum-sort_buffer_size=1M --maximum-tmp_table_size=1M --maximum-transaction_alloc_block_size=1M --maximum-transaction_prealloc_size=1M --log-output=none --sql_mode= --innodb_file_per_table=1 --innodb_flush_method=O_DIRECT --innodb_stats_persistent=off --loose-idle_write_transaction_timeout=0 --loose-idle_transaction_timeout=0 --loose-idle_readonly_transaction_timeout=0 --connect_timeout=60 --interactive_timeout=28800 --slave_net_timeout=60 --net_read_timeout=30 --net_write_timeout=60 --wait_timeout=28800 --lock-wait-timeout=86400 --innodb-lock-wait-timeout=50 --log_output=FILE --log-bin --log_bin_trust_function_creators=1 --loose-max-statement-time=30 --loose-debug_assert_on_not_freed_memory=0 --innodb-buffer-pool-size=300M"
CREATE TABLE t0 (a int(0) auto_increment,b text,c varchar(0),PRIMARY KEY (a),FULLTEXT KEY a(b,c)) engine=innodb;#NOERROR;
xa start 0x0,0x0,0xb;#NOERROR;
INSERT INTO t0 VALUES (0,0,NULL);#NOERROR;
insert into t0 values (NULL,NULL,0);#ERRONa ne odgovara broju vrednosti u slogu 0;
INSERT INTO t0 VALUES(NULL,NULL,0);#ERRONa ne odgovara broju vrednosti u slogu 0;
insert INTO t0 (b) values(NULL);#ERRONa NULL u NULL;
DELETE FROM t0;#NOERROR;
SET @@session.max_insert_delayed_threads=0;#NOERROR;
replace INTO t0 values (),();#NOERROR;
INSERT DELAYED INTO t0 VALUES(NULL,NULL,NULL);#NOERROR;
INSERT INTO t0 VALUES (NULL,NULL,NULL);#ERRONa ne odgovara broju vrednosti u slogu 0;
INSERT INTO t0 VALUES (NULL,NULL,0);#ERRONa NULL u NULL;
INSERT INTO t0 (a) SELECT 0 FROM t0;#ERROR: 0 - Dupliran unos NULL za klju\0D NULL;
insert into t0 (a) values (NULL);#NOERROR;
INSERT INTO t0 VALUES(0,@short_value,DEFAULT);#NOERROR;
DELETE FROM t0;#NOERROR;
INSERT INTO t0 VALUES (),();#ERROR: 0 - Out of range value for c NULL at row 0;
XA END 0x0,0x0,0xb;#NOERROR;
XA PREPARE 0x0,0x0,0xb;#NOERROR;
SHUTDOWN;