INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE TABLE t (c INT) ENGINE=Spider COMMENT='abc';

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
ALTER TABLE mysql.help_topic ENGINE=Spider;

SET sql_mode='';
INSTALL PLUGIN Spider SONAME 'ha_spider.so';
SET SESSION enforce_storage_engine=Spider;
CREATE TABLE t (c BINARY KEY) COMMENT='ENGINE "Spider"';
