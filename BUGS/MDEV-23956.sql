SET max_statement_time=0.1;
INSTALL PLUGIN RocksDB SONAME 'ha_rocksdb.so';
SET SESSION default_storage_engine='RocksDB';
CREATE TABLE t (c INT,c2 CHAR(1),c3 INT(1),c4 VARCHAR(1) KEY,c5 INT UNIQUE KEY,c6 DECIMAL(0,0) DEFAULT 3.1);
SELECT *;  # ERROR 1096 (HY000): No tables used
CREATE INDEX t_c2_idx ON t (c2);

SET sql_mode='';
SET SESSION optimizer_switch='semijoin=ON';
INSTALL PLUGIN RocksDB SONAME 'ha_rocksdb.so';
SET max_statement_time=0.1;
SET SESSION enforce_storage_engine=RocksDB;
CREATE TABLE t (c DOUBLE KEY,c2 CHAR,c3 CHAR,c4 DATE,c5 TEXT) ROW_FORMAT=REDUNDANT;
ALTER TABLE t ENGINE MEMORY;
ALTER TABLE t ADD INDEX (c3);

SET max_statement_time=0.1;
INSTALL PLUGIN RocksDB SONAME 'ha_rocksdb.so';
CREATE TABLE t (a INT) ENGINE=RocksDB;
CREATE INDEX i ON t (a);
