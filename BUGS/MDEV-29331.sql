# mysqld options required for replay:  --innodb_change_buffering=inserts
SET @@GLOBAL.innodb_limit_optimistic_insert_debug=2;
SET @@global.innodb_flush_neighbors=2;
SET @@GLOBAL.innodb_buffer_pool_size=16777216;
CREATE TABLE t1 (c1 BIGINT NULL, c2 CHAR(5)) PARTITION BY KEY(c1) PARTITIONS 99;
DROP TABLE t1;
