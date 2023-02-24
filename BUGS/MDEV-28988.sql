# mysqld options required for replay: --log-bin
SET sql_mode='';
INSTALL PLUGIN RocksDB SONAME 'ha_rocksdb.so';
CREATE TABLE t1 (c INT) ENGINE=RocksDB;
CREATE TABLE t2 (c INT) ENGINE=MyISAM;
XA START 'x';
INSERT INTO t2 VALUES (0);
INSERT INTO t1 VALUES (0);
SAVEPOINT s;
ROLLBACK WORK TO s;
XA END 'x';
XA PREPARE 'x';
