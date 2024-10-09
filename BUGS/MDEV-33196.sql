INSTALL PLUGIN spider SONAME 'ha_spider.so';
SET spider_internal_sql_log_off=1;
DROP TABLE mysql.spider_link_mon_servers;
CREATE TABLE t1(c DATE) ENGINE=MyISAM;
CREATE TABLE t(c DATE,PRIMARY KEY(c)) ENGINE=Spider COMMENT='socket "../socket.sock",table "t1 t2"' CONNECTION='mkd "1"';
SELECT * FROM t WHERE c=0;

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE TABLE t (c INT KEY,c1 BLOB,c2 TEXT) ENGINE=Spider;
DROP DATABASE mysql;
RENAME TABLE t TO c,v2 TO t;

DROP DATABASE test;
CREATE DATABASE test;
USE test;
INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE TABLE t (a INT) ENGINE=Spider;
SET @@max_statement_time=0.0001;
RENAME TABLE t TO t2,t3 TO t3,t2 TO t;

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE TABLE t (a INT) ENGINE=Spider;
SET @@max_statement_time=0.0001;
RENAME TABLE t TO t2,t3 TO t3,t2 TO t;

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE TABLE t (c INT);
CREATE OR REPLACE TABLE t (a INT);
CREATE TABLE t2 (t2_i INT KEY,t2_j BLOB) ENGINE=Spider;
DROP TABLE Ｔ１;
DROP TABLE t;
SET max_statement_time=0.000001;
RENAME TABLE t2 TO t,t2 TO t3,t TO t3;

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE SERVER srv FOREIGN DATA WRAPPER mysql OPTIONS (SOCKET '../socket.sock', DATABASE 'test', USER 'Spider', PASSWORD'');
CREATE TABLE t (c INT PRIMARY KEY,c1 BLOB, c2 TEXT) ENGINE=Spider COMMENT='WRAPPER "mysql", SRV "srv", TABLE "t"';
CREATE TABLE t2 (c INT KEY,c1 BLOB, c2 TEXT) ENGINE=Spider COMMENT='WRAPPER "mysql", SRV "srv", TABLE "tm"';
SET @@max_statement_time=0.0001;
CREATE OR REPLACE TABLE t (a VARCHAR(10));
CREATE OR REPLACE TABLE t (x INT, y INT) WITH SYSTEM VERSIONING;
DROP TABLE t;
DROP TABLE t4,t3,t,t2;
CREATE TABLE nnodb_monitor (a INT) ENGINE=Spider;
CREATE TABLE t (a tinyINT,b FLOAT,c INT, d INT, e INT, f INT, KEY(b), KEY(c), KEY(d), KEY(e), KEY(f)) ENGINE=Spider;
RENAME TABLE t TO t3,t2 TO t3,t TO t;

# mysqld options required for replay:  --max_allowed_packet=33554432 --maximum-bulk_insert_buffer_size=1M --maximum-join_buffer_size=1M --maximum-max_heap_table_size=1M --maximum-max_join_size=1M --maximum-myisam_max_sort_file_size=1M --maximum-myisam_mmap_size=1M --maximum-myisam_sort_buffer_size=1M --maximum-optimizer_trace_max_mem_size=1M --maximum-preload_buffer_size=1M --maximum-query_alloc_block_size=1M --maximum-query_prealloc_size=1M --maximum-range_alloc_block_size=1M --maximum-read_buffer_size=1M --maximum-read_rnd_buffer_size=1M --maximum-sort_buffer_size=1M --maximum-tmp_table_size=1M --maximum-transaction_alloc_block_size=1M --maximum-transaction_prealloc_size=1M --log-output=none --sql_mode=
INSTALL PLUGIN spider SONAME 'ha_spider.so';
FLUSH PRIVILEGES;
CREATE TABLE t936 (c1 INTEGER);
SET @@max_statement_time=0.0001;
INSERT INTO t1 VALUES(8482);
create TABLE t1 (a int,b int) engine=Spider;
CREATE TABLE t2 (a INT) ENGINE = Spider SELECT 1;
CREATE TABLE t1(a int NOT NULL,b blob NOT NULL,c text,PRIMARY KEY (b(10),a),INDEX (c(767)),INDEX(b(767))) ENGINE=Spider ROW_FORMAT=DYNAMIC;
RENAME TABLE t1 to t2;
