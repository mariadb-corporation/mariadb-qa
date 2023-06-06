INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock',DATABASE'test',USER'',PASSWORD'');
CREATE TABLE t (c INT KEY) ENGINE=InnoDB;
CREATE TABLE t1 (c INT KEY) ENGINE=Spider COMMENT='WRAPPER "mysql",srv "srv",TABLE "t"';
DELETE FROM t1;
ALTER TABLE t ENGINE=Spider;  # No COMMENT is present in base table 't', referenced by 't1', so ...
SELECT * FROM t1 WHERE c=1;  # ERROR 1429 (Unable to connect to foreign data source: localhost or similar) is normal

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock',DATABASE'test',USER'',PASSWORD'');
CREATE TABLE t (c INT KEY) ENGINE=InnoDB;
CREATE TABLE t1 (c INT KEY) ENGINE=Spider COMMENT='WRAPPER "mysql",srv "srv",TABLE "t"';
SHOW CREATE TABLE t1;
ALTER TABLE t ENGINE=Spider;  # No COMMENT is present in base table 't', referenced by 't1', so ...
SELECT * FROM t1 WHERE c=0;  # ERROR 1429 (Unable to connect to foreign data source: localhost or similar) is normal
