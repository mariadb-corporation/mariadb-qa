CREATE TABLE t3 (c1 CHAR(1) ,c2 INT) ENGINE=INNODB PARTITION BY LINEAR HASH ((c2)) PARTITIONS 512;
CREATE TABLE t (a INT) ENGINE=INNODB;
XA START 'a';
INSERT INTO mysql.innodb_index_stats SELECT * FROM mysql.innodb_index_stats WHERE table_name='';
SET GLOBAL table_open_cache=10;
INSERT t (a) VALUES (1);
SELECT * FROM t3;
XA END 'a';
XA PREPARE 'a';
SELECT SLEEP (3);
CACHE INDEX tb1,tb2 IN DEFAULT;