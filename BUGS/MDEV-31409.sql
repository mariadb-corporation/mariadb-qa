INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock',DATABASE'',USER'',PASSWORD'');
CREATE TABLE t (c INT) ENGINE=InnoDB;
CREATE TABLE tm (c INT) ENGINE=InnoDB;
CREATE TABLE t1 (c INT KEY) ENGINE=Spider COMMENT='WRAPPER "mysql",srv "srv",TABLE "t"';
CREATE TABLE t2 (c INT) ENGINE=Spider COMMENT='WRAPPER "mysql",srv "srv",TABLE "tm"';
LOCK TABLES t1 READ;  # Not required, but proves incorrect outcome
CREATE TEMPORARY TABLE t1 (c1 INT);
LOCK TABLES t2 READ;
DROP TABLE t1;
LOCK TABLES non_existing WRITE;
SELECT 1 FROM t1;

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE USER Spider@localhost IDENTIFIED BY 'PWD123';
CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock', DATABASE 'test', USER 'Spider', PASSWORD 'PWD123');
CREATE TABLE t (c INT) ENGINE=InnoDB;
CREATE TABLE tm (c INT) ENGINE=MyISAM;
CREATE TABLE t1 (c INT PRIMARY KEY) ENGINE=Spider COMMENT='WRAPPER "mysql", srv "srv", TABLE "t"';
CREATE TABLE t2 (c INT) ENGINE=Spider COMMENT='WRAPPER "mysql", srv "srv", TABLE "tm"';
CREATE TEMPORARY TABLE t1 (c INT);
LOCK TABLES t2 WRITE, t1 READ;
LOCK TABLES Spider.slow_log READ;
DROP TABLE t1;
SELECT COUNT(*) FROM t1;