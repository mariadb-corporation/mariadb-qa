INSTALL PLUGIN spider SONAME 'ha_spider.so';
CREATE TABLE t (c INT) ENGINE=Spider;
HANDLER t OPEN;
HANDLER t READ FIRST;

# Then look for  [ERROR] mysql_ha_read: Got error 12701 when reading table 't'  in the error log
