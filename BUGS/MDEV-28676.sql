INSTALL PLUGIN spider SONAME 'ha_spider.so';
CREATE TABLE t (c INT) ENGINE=Spider;
HANDLER t OPEN;
HANDLER t READ FIRST;

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE TABLE t (c INT KEY,c2 INT) ENGINE=Spider PARTITION BY LIST (c) (PARTITION p VALUES IN (1,2));
LOCK TABLES t AS a1 WRITE,t AS a4 READ,t3 AS a0 READ;
HANDLER t OPEN;
HANDLER t READ NEXT;

# Then look for  [ERROR] mysql_ha_read: Got error 12701 when reading table 't'  in the error log
