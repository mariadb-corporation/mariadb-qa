INSTALL PLUGIN Spider SONAME 'ha_spider.so';
SET character_set_connection=ucs2;
SELECT SPIDER_DIRECT_SQL('SELECT SLEEP(1)', '', 'srv "dummy", port "3307"');
