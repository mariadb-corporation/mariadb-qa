# [ERROR] mysql_ha_read: Got error 1184 when reading table 't' and [Warning] WSREP: handlerton rollback failed, thd 4 226 conf 0 SQL HANDLER t READ FIRST
INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE USER Spider@localhost IDENTIFIED BY 'PWD1';
CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock',DATABASE 'test',user 'Spider',PASSWORD 'PWD1');
CREATE TABLE t (c INT) ENGINE=Spider COMMENT='WRAPPER "mysql",srv "srv",TABLE "t"';
SET GLOBAL init_connect="dummy";
SELECT c FROM t;
HANDLER t OPEN;
HANDLER t READ FIRST;

# [ERROR] mysql_ha_read: Got error 12719 when reading table 't'
INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE USER Spider@localhost IDENTIFIED BY 'PWD1';
CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock',DATABASE 'test',user 'Spider',PASSWORD 'PWD1');
CREATE TABLE t (c INT) ENGINE=Spider COMMENT='WRAPPER "mysql",srv "srv",TABLE "t"';
SET GLOBAL init_connect="SELECT 1";
SELECT c FROM t;
HANDLER t OPEN;
HANDLER t READ FIRST;
