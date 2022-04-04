INSTALL PLUGIN spider SONAME 'ha_spider.so';
DROP TABLE IF EXISTS mysql.spider_tables;

# Can cause thread hang due to CREATE TABLE mysql.spider_tables from the INSTALL PLUGIN conflicting with the DROP of the same thereafter (INSTALL PLUGIN will return before the CREATE is complete)
