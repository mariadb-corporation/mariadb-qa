SET sql_mode='';
INSTALL SONAME 'ha_rocksdb';
SET rocksdb_max_row_locks=1;
CREATE TABLE t (a INT UNSIGNED,b INT,c CHAR,d BINARY,e BINARY,f CHAR,g BLOB,h BLOB,id INT,KEY(b)) ENGINE=RocksDB;
CREATE TABLE t2 (a INT,b CHAR,PRIMARY KEY(a)) ENGINE=RocksDB COMMENT='a';
XA START 'a';
INSERT INTO t VALUES (-1,0,0,0,0,0,0,0,0);
SELECT * FROM t2 WHERE a=1 FOR UPDATE;
# CLI: ERROR 1296 (HY000): Got error 10 'Operation aborted: Failed to acquire lock due to rocksdb_max_row_locks limit' from ROCKSDB
# ERR: [ERROR] Got error 221 when reading table './test/t2'
