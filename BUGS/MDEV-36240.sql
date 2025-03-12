INSTALL PLUGIN Spider SONAME 'ha_spider.so';
SET SESSION default_storage_engine=Spider;
CREATE TEMPORARY TABLE t (c INT);
SET NAMES latin1;
INSERT INTO t VALUES (-1);
SELECT * FROM t WHERE EXTRACTVALUE (c,'a')='a';
