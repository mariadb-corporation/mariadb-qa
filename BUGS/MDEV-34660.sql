DROP DATABASE test;
CREATE DATABASE test;
USE test;
INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE TABLE t1 (c INT) ENGINE=Spider;
CREATE TABLE t2 (c INT) ENGINE=Spider;
RENAME TABLE t2 TO doesnotexist.t;

DROP DATABASE test;
CREATE DATABASE test;
USE test;
INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE TABLE t2 (c INT) ENGINE=Spider;
RENAME TABLE t2 TO doesnotexist.t;

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE TABLE t1 (c INT) ENGINE=Spider;
CREATE TABLE t2 (c INT) ENGINE=Spider;
RENAME TABLE t2 TO doesnotexist.t;
