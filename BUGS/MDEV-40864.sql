SET sql_mode='';
INSTALL SONAME 'ha_duckdb';
SET SESSION default_storage_engine=DuckDB;
CREATE TABLE t1 (c1 INT KEY,c2 DEC(1,0) NOT NULL,c3 SET('a','b','c','1'),c4 INT(1) UNSIGNED NOT NULL,KEY(c2)) ENGINE=MyISAM WITH SYSTEM VERSIONING;  # Allowed while it should not be. It gets confused on the ENGINE=. Does not work without SET SESSION default_storage_engine=DuckDB; nor when using ENGINE=DuckDB
INSERT INTO t1 (c3) VALUES (1);
CREATE TABLE t2 (c0 VARCHAR(1) BINARY, c1 FLOAT KEY,c2 FLOAT);
WITH a AS (SELECT * FROM t1),b AS (SELECT * FROM t1),c AS (SELECT * FROM t2) SELECT * FROM a JOIN b ON a.c2=b.c2 LEFT JOIN c ON b.c2=c.c2;
