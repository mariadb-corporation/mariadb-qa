CREATE FUNCTION spider_direct_sql RETURNS INT SONAME 'ha_spider.so';
SELECT spider_direct_sql ('SELECT * FROM s','a','srv "b"');

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
UNINSTALL SONAME IF EXISTS "ha_spider";
SELECT spider_direct_sql ('','tmp_a','SRV "s",DATABASE "test"');

CREATE FUNCTION spider_bg_direct_sql RETURNS INT SONAME 'ha_spider.so';
SELECT spider_bg_direct_sql ('SET SESSION AUTO_INCREMENT_OFFSET=3','','SRV "s"');

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
UNINSTALL SONAME IF EXISTS 'ha_spider';
SELECT spider_copy_tables ('a','','');

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
UNINSTALL SONAME IF EXISTS "ha_spider";
SELECT spider_bg_direct_sql ('SET SESSION _offset=3','','SRV "s"');

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
UNINSTALL SONAME IF EXISTS "ha_spider";
CREATE TABLE t (a INT DEFAULT 1,b CHAR DEFAULT'',c DATE DEFAULT'') DEFAULT CHARSET=utf8;
SELECT spider_bg_direct_sql ('SET SESSION _offset=1','','SRV "s"');
