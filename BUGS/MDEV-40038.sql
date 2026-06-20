# mysqld options required for replay: --log_bin
INSTALL SONAME 'ha_rocksdb';
CREATE TABLE t (c INT) ENGINE=MEMORY;
SET GLOBAL default_storage_engine=RocksDB;
UNINSTALL SONAME 'ha_rocksdb';
INSTALL SONAME 'ha_mroonga';
INSERT DELAYED INTO t VALUES (1);
SET GLOBAL default_storage_engine=Mroonga;
FLUSH TABLES;
RESET MASTER;
