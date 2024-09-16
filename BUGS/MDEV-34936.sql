SET sql_mode='';
INSTALL PLUGIN RocksDB SONAME 'ha_rocksdb';
CREATE TABLE t (c INT PRIMARY KEY,d INT,KEY (d)) ENGINE=RocksDB;
BEGIN;
INSERT INTO t VALUES (0,0);
SET rocksdb_max_row_locks=0;
SELECT * FROM t FOR UPDATE;
#CLI: ERROR 1296 (HY000): Got error 10 'Operation aborted: Failed to acquire lock due to rocksdb_max_row_locks limit' from ROCKSDB
#ERR: [ERROR] Got error 220 when reading table './test/t'

SET sql_mode='';
INSTALL PLUGIN RocksDB SONAME 'ha_rocksdb';
CREATE TABLE t (c INT PRIMARY KEY,d INT) ENGINE=RocksDB;
BEGIN;
INSERT INTO t VALUES (0,0);
SET rocksdb_max_row_locks=0;
SELECT * FROM t FOR UPDATE;
#CLI: ERROR 1296 (HY000): Got error 10 'Operation aborted: Failed to acquire lock due to rocksdb_max_row_locks limit' from ROCKSDB
#ERR: - (no error)

SET sql_mode='';
INSTALL PLUGIN RocksDB SONAME 'ha_rocksdb';
CREATE TABLE t (c INT PRIMARY KEY,d INT,KEY (d)) ENGINE=RocksDB;
INSERT INTO t VALUES (0,0);
SET rocksdb_max_row_locks=0;
SELECT * FROM t FOR UPDATE;
#CLI: - (no error, expected query output c/d 0/0)
#ERR: - (no error)
