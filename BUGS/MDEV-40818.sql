# mysqld options required for replay: --log-bin=binlog --server_id=1
INSTALL SONAME 'ha_duckdb';
CREATE TABLE t1 (id INT PRIMARY KEY) ENGINE=DuckDB;
INSERT INTO t1 VALUES (1);
