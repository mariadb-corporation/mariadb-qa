INSTALL PLUGIN spider SONAME 'ha_spider.so';
CREATE TABLE t(c INT) ENGINE=SPIDER PARTITION BY KEY(c) PARTITIONS 2;
INSERT INTO t VALUES(0);
RENAME TABLE t TO `......................................................`;
INSERT INTO t VALUES(0);
