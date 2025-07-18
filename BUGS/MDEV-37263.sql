SET tx_isolation='SERIALIZABLE';
CREATE TABLE t (c INT) PARTITION BY LINEAR HASH ((c)) PARTITIONS 512;
BEGIN;
SELECT * FROM t;
SET GLOBAL innodb_buffer_pool_size=1;
COMMIT;
SET GLOBAL innodb_buffer_pool_size=1;
DROP TABLE t;


SET tx_isolation='SERIALIZABLE';
CREATE TABLE t (c1 VARCHAR(1) BINARY CHARACTER SET 'latin1' COLLATE 'latin1_bin',c2 YEAR,c3 DATETIME(1)) PARTITION BY LINEAR HASH ((c2)) PARTITIONS 523;
XA START 'a';
SELECT * FROM t;
SET GLOBAL innodb_buffer_pool_size=+1;
XA END 'a';
XA ROLLBACK 'a';
SET GLOBAL innodb_buffer_pool_size=+1;
SET tx_isolation='SERIALIZABLE';
drop table t;
