DROP DATABASE test;
INSTALL SONAME 'ha_spider';
SELECT spider_copy_tables ('a','','');

DROP DATABASE test;
INSTALL PLUGIN Spider SONAME 'ha_spider.so';
SET collation_connection=ucs2_general_ci;
SELECT spider_direct_sql ('a','','b');
