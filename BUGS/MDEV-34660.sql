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

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE TABLE t (cink INT,cvcnk INT) CHARSET utf8mb4 ENGINE=InnoDB;
CREATE OR REPLACE TABLE t (id INT) ENGINE=InnoDB;
CREATE TABLE t2 (c INT KEY,c1 BLOB,c2 TEXT) ENGINE=Spider;
RENAME TABLE t2 TO t.t;

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE SERVER srv FOREIGN DATA WRAPPER mysql OPTIONS (SOCKET'',DATABASE'',USER'',PASSWORD'');
CREATE TABLE t2 (c INT KEY) ENGINE=Spider COMMENT='WRAPPER "mysql",SRV "srv",TABLE "foo"';
RENAME TABLE t2 TO doesnotexist.t;
# CLI: ERROR 1049 (42000): Unknown database 'doesnotexist'
# ERR: [ERROR] mariadbd: Can't find record in 'spider_tables'
# ERR: [ERROR] DDL_LOG: Got error 1032 when trying to execute action for entry 2 of type 'rename table'

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE SERVER srv FOREIGN DATA WRAPPER mysql OPTIONS (SOCKET'',DATABASE'',USER'',PASSWORD'');
CREATE TABLE t2 (c INT KEY) ENGINE=Spider COMMENT='WRAPPER "mysql",SRV "srv",TABLE "tm"';
CREATE OR REPLACE TABLE t (a INT) ENGINE=InnoDB;
RENAME TABLE t2 TO doesnotexist.t;
# CLI: ERROR 1049 (42000): Unknown database 'doesnotexist'
# ERR: [ERROR] mariadbd: Can't find record in 'spider_tables'
# ERR: [ERROR] DDL_LOG: Got error 1032 when trying to execute action for entry 1 of type 'rename table'

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE SERVER srv FOREIGN DATA WRAPPER mysql OPTIONS (SOCKET'',DATABASE'',USER'',PASSWORD'');
CREATE TABLE t (c INT KEY) ENGINE=InnoDB;
CREATE TABLE t2 (c INT KEY) ENGINE=Spider COMMENT='WRAPPER "mysql",SRV "srv",TABLE "tm"';
CREATE OR REPLACE TABLE t (a INT) ENGINE=InnoDB;
RENAME TABLE t2 TO doesnotexist.t;
# CLI: ERROR 1049 (42000): Unknown database 'doesnotexist'
# ERR: [ERROR] mariadbd: Can't find record in 'spider_tables'
# ERR: [ERROR] DDL_LOG: Got error 1032 when trying to execute action for entry 5 of type 'rename table'
