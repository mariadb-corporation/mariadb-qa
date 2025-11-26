INSTALL SONAME 'ha_rocksdb';
CREATE TABLE t (c INT KEY) ENGINE=RocksDB;
INSERT t VALUES (1);
SET rocksdb_bulk_load=1;
BEGIN;
DELETE FROM t;
SELECT * FROM t FOR UPDATE;
# CLI: ERROR 1296 (HY000): Got error 1 'NotFound: ' from ROCKSDB
# ERR: [ERROR] Got error 510 when reading table './test/t'
