INSTALL SONAME 'ha_rocksdb';
SET sql_mode='';
CREATE OR REPLACE TABLE mysql.general_log (c INT) ENGINE=RocksDB;
SET GLOBAL log_output='TABLE', GLOBAL general_log=TRUE;
CREATE TABLE t (c INT) ENGINE=RocksDB;  # Debug crash, i.e. MDEV-24706
XA START 'x';
INSERT INTO t VALUES (1);
XA END 'x';
SET autocommit=0;
XA COMMIT 'x' ONE PHASE;  # Optimized builds crash, i.e. the bug described here
