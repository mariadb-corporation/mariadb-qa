INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock',DATABASE'',USER'',PASSWORD'');
create table t2 (c int);
create table t1 (c int) ENGINE=Spider COMMENT='WRAPPER "mysql", srv "srv",TABLE "t2"';
show table status like "t1";
shutdown;

SET sql_mode='';
INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock',DATABASE'',USER'',PASSWORD'');
CREATE TABLE tm (c INT KEY,c1 BLOB,c2 TEXT) ENGINE=InnoDB;
CREATE TABLE t2 (c INT KEY,c1 BLOB,c2 TEXT) ENGINE=Spider COMMENT='WRAPPER "mysql",SRV "srv",TABLE "tm"';
LOCK TABLE t2 READ;
SHUTDOWN;

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock',DATABASE'',USER'',PASSWORD'');
SET GLOBAL wait_timeout=True;
CREATE TABLE t1 (f INT) ENGINE=Spider COMMENT='WRAPPER "mysql",SRV "srv",TABLE "t"';
SHOW TABLE STATUS;
CREATE TABLE t (c INT KEY,c1 BLOB,c2 TEXT) ENGINE=InnoDB;
SELECT SLEEP(2);
SHOW TABLE STATUS;

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock',DATABASE'',USER'',PASSWORD'');
CREATE TABLE t (c INT KEY,c BLOB,c2 TEXT) ENGINE=InnoDB;
SET GLOBAL wait_timeout=True;
CREATE TABLE t2 (f INT) ENGINE=Spider COMMENT='WRAPPER "mysql",SRV "srv",TABLE "t"';
SHOW TABLE STATUS;
SELECT SLEEP(2);