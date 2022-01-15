SET GLOBAL innodb_limit_optimistic_insert_debug=2;
SET GLOBAL tx_read_only=1;
CREATE TABLE t (c1 INT(1),c2 CHAR(1), KEY A (c1,c2 (1))) DEFAULT CHARSET=latin1;
SET GLOBAL innodb_defragment_stats_accuracy=10;
CREATE TABLE t2 (a INT,b INT,c CHAR(1),d CHAR(1),e VARCHAR(1),f VARCHAR(1),g BLOB,h BLOB,id INT,KEY(b),KEY(e));
