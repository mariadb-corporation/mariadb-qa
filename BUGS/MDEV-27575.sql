INSTALL PLUGIN spider SONAME 'ha_spider.so';
SET GLOBAL default_tmp_storage_engine=spider;
SHUTDOWN;

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
SET GLOBAL default_storage_engine=Spider;
SHUTDOWN;
