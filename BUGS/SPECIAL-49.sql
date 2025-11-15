INSTALL SONAME 'ha_rocksdb';
CREATE TABLE t (a INT,INDEX (a)) ENGINE=RocksDB;
INSERT t VALUES (0),(0),(0);
XA START 'XA0';
SET rocksdb_max_row_locks=0;
SELECT * FROM t WHERE a IN (0,0,0,0)=0 FOR UPDATE;
# CLI: ERROR 1296 (HY000): Got error 10 'Operation aborted: Failed to acquire lock due to rocksdb_max_row_locks limit' from ROCKSDB
# ERR: [ERROR] Got error 521 when reading table './test/t'
