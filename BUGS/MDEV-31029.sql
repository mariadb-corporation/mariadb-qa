# mysqld options required for replay:  --binlog_format=ROW
CREATE TABLE t (c INT,KEY(c)) ENGINE=Aria;
INSERT INTO t VALUES (0);
INSERT INTO t VALUES (0);
LOCK TABLES t WRITE;
REPAIR TABLE t;
DELETE FROM t;
