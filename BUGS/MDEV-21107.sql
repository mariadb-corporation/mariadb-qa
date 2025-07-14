# Ref /data/KEEP/MDEV-21107

CREATE TABLE t2(c1 char(3)) DEFAULT CHARSET = sjis ENGINE = RocksDB;
CREATE TABLE t1(f1 DECIMAL(44,24)) ENGINE=ROCKSDB;
XA START 'a';
INSERT INTO t1 VALUES (0), (0), (1), (2);
insert into t2 values (11437+0.75);
XA END 'a';
XA PREPARE 'a';
XA ROLLBACK 'a';
INSERT INTO t1 SELECT * FROM t2;
DROP TABLE t1;
SELECT SLEEP(2);

# mysqld options required for replay: --log-bin --sql_mode= --innodb_flush_method=O_DIRECT
SET autocommit=0;
SET SESSION enforce_storage_engine=Aria;
CREATE TABLE t(c CHAR(1)CHARACTER SET 'utf8' COLLATE 'utf8_bin',c2 CHAR(1) BINARY CHARACTER SET 'latin1' COLLATE 'latin1_bin',c3 CHAR (1) BINARY CHARACTER SET 'BINARY' COLLATE 'BINARY',c4 VARCHAR(1) CHARACTER SET 'BINARY' COLLATE 'BINARY') ROW_FORMAT=COMPRESSED;
CREATE TABLE t2(a DATE)PARTITION BY KEY(a);
INSERT INTO t2 VALUES(),();
UPDATE t2 SET a=2;
CREATE TABLE t2(c INT KEY,c2 CHAR(1)) ENCRYPTION=''ENGINE=Spider;
INSERT INTO t SELECT 1 exist;
INSERT INTO t2 VALUES();
CREATE TABLE t4(a INT UNSIGNED,b INT,c BINARY (1),d CHAR(1),e BINARY (1),f CHAR(1),g BLOB,h BLOB,id INT,KEY(b));

# mysqld options required for replay:  --max_allowed_packet=33554432 --maximum-bulk_insert_buffer_size=1M --maximum-myisam_mmap_size=1M --maximum-optimizer_trace_max_mem_size=1M --maximum-preload_buffer_size=1M --maximum-query_prealloc_size=1M --maximum-range_alloc_block_size=1M --maximum-read_buffer_size=1M --maximum-read_rnd_buffer_size=1M --sql_mode= --innodb_file_per_table=1 --innodb_flush_method=O_DIRECT --innodb_stats_persistent=off --loose-idle_write_transaction_timeout=0 --connect_timeout=60 --interactive_timeout=28800 --wait_timeout=28800 --lock-wait-timeout=86400 --log_output=FILE --log_bin_trust_function_creators=1 --loose-debug_assert_on_not_freed_memory=0 --innodb-buffer-pool-size=300M
CREATE TABLE t (a DATE);
EXECUTE s;
DROP DATABASE mysql;
INSERT t VALUES ();
INSERT INTO t VALUES ();
SET mode=1;
CREATE TABLE tp (id INT) PARTITION BY RANGE (id) (PARTITION p0 VALUES LESS THAN (0),PARTITION p VALUES LESS THAN (1),PARTITION p2 VALUES LESS THAN (200),PARTITION p3 VALUES LESS THAN (300),PARTITION p4 VALUES LESS THAN (400),PARTITION p5 VALUES LESS THAN (500),PARTITION p6 VALUES LESS THAN (600),PARTITION p7 VALUES LESS THAN (700),PARTITION p8 VALUES LESS THAN (800));

# mysqld options required for replay: --log-bin --net_read_timeout=30 --net_write_timeout=60
CREATE TABLE t (a INT);
DROP DATABASE mysql;
INSERT INTO t VALUES (1);
INSERT INTO t VALUES (1);
SELECT*(@JSON;
CREATE TABLE t2 (Ｃ１ CHAR(1),INDEX (Ｃ１)) DEFAULT CHARSET=utf8;

SET autocommit=0,sql_mode='';
SET SESSION enforce_storage_engine=Aria;
CREATE TABLE t(c CHAR(1)CHARACTER SET 'utf8' COLLATE 'utf8_bin',c2 CHAR(1) BINARY CHARACTER SET 'latin1' COLLATE 'latin1_bin',c3 CHAR (1) BINARY CHARACTER SET 'BINARY' COLLATE 'BINARY',c4 VARCHAR(1) CHARACTER SET 'BINARY' COLLATE 'BINARY') ROW_FORMAT=COMPRESSED;
CREATE TABLE t2(a DATE)PARTITION BY KEY(a);
INSERT INTO t2 VALUES(),();
UPDATE t2 SET a=2;
CREATE TABLE t2(c INT KEY,c2 CHAR(1)) ENCRYPTION=''ENGINE=Spider;
INSERT INTO t SELECT 1 exist;
INSERT INTO t2 VALUES();
CREATE TABLE t4(a INT UNSIGNED,b INT,c BINARY (1),d CHAR(1),e BINARY (1),f CHAR(1),g BLOB,h BLOB,id INT,KEY(b));
