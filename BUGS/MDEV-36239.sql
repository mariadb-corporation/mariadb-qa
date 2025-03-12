INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE TABLE t (c INT) ENGINE=Spider;
ALTER TABLE t ENGINE=InnoDB;
SET character_set_connection=utf16;
SELECT spider_direct_sql ('DROP TABLE "t2"','','SRV "srv",WRAPPER "odbc"');
