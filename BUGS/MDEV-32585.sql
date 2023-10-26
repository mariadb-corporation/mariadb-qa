INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE TABLE t (c INT) ENGINE=Spider DEFAULT_GROUP=none;
SELECT * FROM t;

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE TABLE t (c INT) ENGINE=Spider COMMENT='default_group "none"';
SELECT * FROM t;
