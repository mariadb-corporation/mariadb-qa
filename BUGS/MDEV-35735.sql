INSTALL PLUGIN Spider SONAME 'ha_spider.so';
SELECT spider_direct_sql ('SELECT 1','','SRV "a"');

INSTALL PLUGIN spider SONAME 'ha_spider.so';
SELECT spider_flush_table_mon_cache();

INSTALL SONAME 'ha_spider';
SELECT spider_bg_direct_sql ('SET SESSION _offset=2','','SRV "s"');
