INSTALL PLUGIN spider SONAME 'ha_spider.so';
SET spider_internal_sql_log_off=1;
DROP TABLE mysql.spider_link_mon_servers;
CREATE TABLE t1(c DATE) ENGINE=MyISAM;
CREATE TABLE t(c DATE,PRIMARY KEY(c)) ENGINE=Spider COMMENT='socket "../socket.sock",table "t1 t2"' CONNECTION='mkd "1"';
SELECT * FROM t WHERE c=0;

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE TABLE t (c INT KEY,c1 BLOB,c2 TEXT) ENGINE=Spider;
DROP DATABASE mysql;
RENAME TABLE t TO c,v2 TO t;

DROP DATABASE test;
CREATE DATABASE test;
USE test;
INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE TABLE t (a INT) ENGINE=Spider;
SET @@max_statement_time=0.0001;
RENAME TABLE t TO t2,t3 TO t3,t2 TO t;

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE TABLE t (a INT) ENGINE=Spider;
SET @@max_statement_time=0.0001;
RENAME TABLE t TO t2,t3 TO t3,t2 TO t;

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE TABLE t (c INT);
CREATE OR REPLACE TABLE t (a INT);
CREATE TABLE t2 (t2_i INT KEY,t2_j BLOB) ENGINE=Spider;
DROP TABLE Ｔ１;
DROP TABLE t;
SET max_statement_time=0.000001;
RENAME TABLE t2 TO t,t2 TO t3,t TO t3;
