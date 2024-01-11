INSTALL PLUGIN spider SONAME 'ha_spider.so';
CREATE TABLE t2(a INT,c DATE);
CREATE TABLE t1(a INT,c DATE,KEY (a)) ENGINE=Spider COMMENT='table "t2"' CONNECTION='socket "../socket.sock"';
DROP TABLE mysql.spider_table_crd;
UPDATE t1 SET c=':1:1' WHERE a>1;

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE SERVER s FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock');
CREATE TABLE t1 (c INT);
CREATE TABLE t2 (c INT) ENGINE=Spider COMMENT='WRAPPER "mysql",SRV "s",TABLE "t1"';
INSERT INTO t2 VALUES (1);
DROP TABLE IF EXISTS mysql.spider_table_sts;
ALTER TABLE t2 ENGINE=Spider;
