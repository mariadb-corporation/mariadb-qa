SET GLOBAL aria_encrypt_tables=ON;
CREATE FUNCTION spider_direct_sql RETURNS INT SONAME 'ha_spider.so';
INSTALL PLUGIN spider SONAME 'ha_spider.so';
SELECT spider_direct_sql ('SELECT * FROM s','a','srv "b"');
