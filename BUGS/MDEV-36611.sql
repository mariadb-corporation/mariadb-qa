INSTALL SONAME 'ha_rocksdb';
SET sql_mode='';
CREATE OR REPLACE TABLE mysql.general_log (c INT) ENGINE=RocksDB;
SET GLOBAL log_output='TABLE', GLOBAL general_log=TRUE;
CREATE TABLE t (c INT) ENGINE=RocksDB;  # Debug crash, i.e. MDEV-24706
XA START 'x';
INSERT INTO t VALUES (1);
XA END 'x';
SET autocommit=0;
XA COMMIT 'x' ONE PHASE;i

INSTALL SONAME 'ha_rocksdb';
SET autocommit=0;
SET GLOBAL log_output='TABLE';
SET default_storage_engine=RocksDB;
CREATE OR REPLACE TABLE mysql.general_log (a INT);
SET GLOBAL general_log=1;
CREATE TABLE t1 (a INT) ENGINE RocksDB;
INSERT INTO t1 VALUES ();
CREATE TABLE t (n INT,d DATE,KEY(n));
