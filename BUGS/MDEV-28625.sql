CREATE TABLE t (c INT) ENGINE=InnoDB;
LOCK TABLE t READ;
SELECT * FROM t;
CREATE FUNCTION spider_bg_direct_sql RETURNS INT SONAME 'ha_spider.so';
LOCK TABLES nonexisting READ;
CREATE FUNCTION spider_direct_sql RETURNS INT SONAME 'ha_spider.so';
