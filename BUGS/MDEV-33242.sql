SET GLOBAL old_mode=4;
INSTALL PLUGIN Spider SONAME 'ha_spider.so';
# Then check error log for SPIDER plugin initialization failed at 'create table if not exists mysql.spider_tables and Warning: Memory not freed: 10720
