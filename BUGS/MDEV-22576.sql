CREATE TABLE t (a INT) ENGINE=MyISAM;
CREATE VIEW v AS SELECT * FROM performance_schema.table_handles ORDER BY INTERNAL_LOCK;
INSERT DELAYED INTO t VALUES (1);
SELECT * FROM v;

USE test;
SET SESSION default_storage_engine=MyISAM;
CREATE TABLE t1 (id INT);
INSERT DELAYED INTO t1 VALUES(69, 31), (NULL, 32), (NULL, 33);
SELECT * FROM performance_schema.table_handles;
