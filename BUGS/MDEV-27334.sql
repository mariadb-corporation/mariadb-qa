INSTALL PLUGIN spider SONAME 'ha_spider.so';
CREATE TABLE t (c INT PRIMARY KEY) ENGINE=SPIDER PARTITION BY HASH (c) PARTITIONS 2;
CREATE TRIGGER t AFTER INSERT ON t FOR EACH ROW INSERT INTO t VALUES(0);