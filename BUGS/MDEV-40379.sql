# mysqld options required for replay: --plugin-maturity=alpha
INSTALL SONAME 'ha_duckdb';
CREATE TEMPORARY TABLE t (c INT KEY) ENGINE=DuckDB;
