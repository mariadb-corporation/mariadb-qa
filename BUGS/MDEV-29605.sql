SET sql_mode='';
INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE USER Spider@localhost IDENTIFIED BY 'PWD0';
CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock',DATABASE 'test',user 'Spider',PASSWORD 'PWD0');
CREATE TABLE t (a INT) ENGINE=Spider COMMENT='WRAPPER "mysql",srv "srv",TABLE "t"';
SET GLOBAL init_connect='dummy';
CREATE TABLE t0 (a INT) ENGINE=Spider COMMENT='WRAPPER "mysql",srv "srv",TABLE "t"';
XA START 'a';
INSERT INTO t VALUES (1);
SHOW CREATE TABLE t0;
SELECT * FROM t0 JOIN t0 a ON a=a;
INSERT INTO t0 VALUES (1);

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE USER Spider@localhost IDENTIFIED BY 'PWD0';
CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock',DATABASE 'test',user 'Spider',PASSWORD 'PWD0');
SET unique_checks=0,foreign_key_checks=0,autocommit=0;
SET GLOBAL init_connect="dummy";
CREATE TABLE t ENGINE=Spider COMMENT='WRAPPER "mysql",srv "srv",TABLE "t"' AS SELECT 1;
