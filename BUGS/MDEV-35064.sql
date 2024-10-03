INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE SERVER s FOREIGN DATA WRAPPER mysql OPTIONS(HOST '1');
CREATE TABLE t(c INT)ENGINE=Spider COMMENT='WRAPPER "mysql",SRV "s",TABLE "foo"';
INSERT INTO t VALUES(1);   # ERROR 1429 (HY000): Unable to connect to foreign data source: s
INSERT INTO t VALUES(1);   # Hangs
