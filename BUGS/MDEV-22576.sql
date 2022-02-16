# mysqld options required for replay: --performance-schema
CREATE TABLE t (a INT) ENGINE=MyISAM;
CREATE VIEW v AS SELECT * FROM performance_schema.table_handles ORDER BY INTERNAL_LOCK;
INSERT DELAYED INTO t VALUES (1);
SELECT * FROM v;

# mysqld options required for replay: --performance-schema
USE test;
SET SESSION default_storage_engine=MyISAM;
CREATE TABLE t1 (id INT);
INSERT DELAYED INTO t1 VALUES(69, 31), (NULL, 32), (NULL, 33);
SELECT * FROM performance_schema.table_handles;

# mysqld options required for replay:  --performance-schema   
SET SESSION default_storage_engine=MEMORY;
CREATE TABLE t (c BIT KEY);
INSERT DELAYED INTO t VALUES();
SELECT * FROM performance_schema.table_handles;
