# mysqld options required for replay: --log-bin
INSTALL SONAME 'ha_rocksdb';
SET default_storage_engine=RocksDB;
CREATE TABLE t AS SELECT 0 QUERY;
