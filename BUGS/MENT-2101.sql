INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE TABLE t (c INT) ENGINE=Spider COMMENT='wrapper "mysql", SOCKET "../socket.sock", user "", database "test"';
INSERT INTO t VALUES (1);

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE TABLE t (c INT) ENGINE=Spider COMMENT='wrapper "mysql", SOCKET "../socket.sock", user "", database "test"' PARTITION BY RANGE (c) (PARTITION p VALUES LESS THAN (10));
INSERT INTO t VALUES (1);

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE TABLE t (c INT) ENGINE=Spider COMMENT='wrapper "mysql", SOCKET "../socket.sock\", user "root", database "test"' PARTITION BY RANGE (c) (PARTITION p VALUES LESS THAN (10));
INSERT INTO t VALUES (1);
DROP TABLE t;
