INSTALL PLUGIN Spider SONAME 'ha_spider.so';
ALTER TABLE mysql.procs_priv ENGINE=Spider COMMENT='';
CREATE USER a@localhost;

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE OR REPLACE TABLE mysql.procs_priv (id INT) ENGINE=Spider;
FLUSH PRIVILEGES;
