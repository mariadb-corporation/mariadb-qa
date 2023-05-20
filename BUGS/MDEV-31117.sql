INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE TABLE t (c INT) ENGINE=Spider COMMENT='abc';

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
ALTER TABLE mysql.help_topic ENGINE=Spider;
