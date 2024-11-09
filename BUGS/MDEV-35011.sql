# Sporadic, loop till crash (~500)
DROP DATABASE test;
CREATE DATABASE test;
USE test;
INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE SERVER srv FOREIGN DATA WRAPPER mysql OPTIONS (SOCKET '../socket.sock', DATABASE 'test', USER 'Spider', PASSWORD '');
CREATE TABLE t1 (c INT PRIMARY KEY,c1 BLOB, c2 TEXT) ENGINE=Spider COMMENT='WRAPPER "mysql", SRV "srv", TABLE "t"';
CREATE TABLE t2 (c INT KEY,c1 BLOB, c2 TEXT) ENGINE=Spider COMMENT='WRAPPER "mysql", SRV "srv", TABLE "tm"';
CREATE TABLE t3 (e INT, f BLOB) ENGINE=Spider;
SET GLOBAL default_storage_engine=Spider;
CREATE TABLE t5 (c1 TINYINT NOT NULL);
XA START 'xa1';
SHOW CREATE TABLE t1;
SET spider_semi_table_lock=1;
SELECT AVG(c1) AS VALUE FROM t1;
SET GLOBAL table_open_cache=10;
EXPLAIN EXTENDED SELECT * FROM t3 WHERE a >=any (SELECT b FROM t2);
INSERT INTO t2 VALUES (0,0,0,'a','b','c','d');
UPDATE IGNORE t5 SET c1=NULL WHERE c1>1;
SELECT * FROM t1 WHERE c2 IS NOT NULL ORDER BY c1,c2 LIMIT 2;
INSERT INTO t1 SELECT A.a+10* B.a+100* C.a, A.a+10* B.a+100* C.a, 'filler' FROM t1 A, t1 B, t1 C;
INSERT INTO t3 VALUES (1,0);
SELECT HEX(c1),HEX (c2) FROM t5;
SELECT * FROM t2 WHERE c1 <=-255 ORDER BY c1,c6 DESC LIMIT 2;

# Sporadic, loop till crash (~500)
# Options in use: --max_allowed_packet=33554432 --maximum-bulk_insert_buffer_size=1M --maximum-join_buffer_size=1M --maximum-max_heap_table_size=1M --maximum-max_join_size=1M --maximum-myisam_max_sort_file_size=1M --maximum-myisam_mmap_size=1M --maximum-myisam_sort_buffer_size=1M --maximum-optimizer_trace_max_mem_size=1M --maximum-preload_buffer_size=1M --maximum-query_alloc_block_size=1M --maximum-query_prealloc_size=1M --maximum-range_alloc_block_size=1M --maximum-read_buffer_size=1M --maximum-read_rnd_buffer_size=1M --maximum-sort_buffer_size=1M --maximum-tmp_table_size=1M --maximum-transaction_alloc_block_size=1M --maximum-transaction_prealloc_size=1M --log-output=none --sql_mode= --core-file
INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE SERVER srv FOREIGN DATA WRAPPER mysql OPTIONS (SOCKET '../socket.sock', DATABASE 'test', USER 'Spider', PASSWORD '');
CREATE TABLE t1 (c INT PRIMARY KEY,c1 BLOB, c2 TEXT) ENGINE=Spider COMMENT='WRAPPER "mysql", SRV "srv", TABLE "t"';
CREATE TABLE t2 (c INT KEY,c1 BLOB, c2 TEXT) ENGINE=Spider COMMENT='WRAPPER "mysql", SRV "srv", TABLE "tm"';
CREATE TABLE t3 (e INT, f BLOB) ENGINE=Spider;
SET GLOBAL default_storage_engine=Spider;
SET default_storage_engine=DEFAULT;
CREATE TABLE t5 (c1 TINYINT NOT NULL);
XA START 'xa1';
SHOW CREATE TABLE t1;
SET spider_semi_table_lock=1;
SELECT AVG(c1) AS VALUE FROM t1;
SET GLOBAL table_open_cache=FALSE;
EXPLAIN EXTENDED SELECT * FROM t3 WHERE a >=any (SELECT b FROM t2);
INSERT INTO t2 VALUES (888,228312,37,'graDUALLy','mineral','creak','FAS');
UPDATE IGNORE t5 SET c1=NULL WHERE c1>100;
SELECT * FROM t1 WHERE c2 IS NOT NULL ORDER BY c1,c2 LIMIT 2;
SELECT * FROM t2 WHERE i > 10 AND i <=18 ORDER BY i;
INSERT INTO t1 SELECT A.a+10* B.a+100* C.a, A.a+10* B.a+100* C.a, 'filler' FROM t1 A, t1 B, t1 C;
CALL sp71_nu (1.00e+40);
INSERT INTO t3 VALUES (1,0);
SELECT HEX(c1),HEX (c2) FROM t5;
SELECT * FROM t2 WHERE c1 <=-255 ORDER BY c1,c6 DESC LIMIT 2;

# Deterministic
INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE SERVER srv FOREIGN DATA WRAPPER mysql OPTIONS (SOCKET '../socket.sock', DATABASE 'test', USER 'Spider', PASSWORD '');
CREATE TABLE t2 (c INT KEY,c1 BLOB, c2 TEXT) ENGINE=Spider COMMENT='WRAPPER "mysql", SRV "srv", TABLE "tm"';
CREATE TABLE t1 (c1 INT, c2 GEOMETRY NOT NULL, SPATIAL INDEX (c2)) ENGINE=Spider;
XA START '1';
SET spider_semi_table_lock=1;
SELECT * FROM t1 LIMIT 1;
SELECT a FROM t1 WHERE a > ALL (SELECT * FROM t2);
INSERT INTO t2 SELECT * FROM t2;
HANDLER t2 OPEN;
SELECT f1, f2 FROM t2 FOR UPDATE;
SET GLOBAL table_open_cache=256;
SELECT HEX(ind),HEX (string1) FROM t2 ORDER BY string1;
