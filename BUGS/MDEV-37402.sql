INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE SERVER srv FOREIGN DATA WRAPPER mysql OPTIONS (SOCKET '../socket.sock',DATABASE'',USER'',PASSWORD'');
CREATE TABLE tm (c INT) ENGINE=InnoDB;
CREATE TABLE t (c INT) ENGINE=Spider;
CREATE TABLE t2 (c INT KEY) ENGINE=Spider COMMENT='WRAPPER "mysql",SRV "srv",TABLE "tm"';
SHOW CREATE TABLE t2;
CREATE TEMPORARY TABLE t2 (c INT) ENGINE=InnoDB;
INSERT INTO t VALUES (1);
SET GLOBAL collation_connection=utf16_vietnamese_ci;
DROP TABLE t,t2;
CREATE TEMPORARY TABLE t (a INT) ENGINE=InnoDB;
INSERT INTO t VALUES (1),(1),(1);
SELECT a FROM t JOIN t2;
CLI: ERROR 1298 (HY000): Unknown or incorrect time zone: '+00:00'
ERR: [ERROR] Got error 1298 when reading table './test/t2'

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE SERVER srv FOREIGN DATA WRAPPER mysql OPTIONS (SOCKET '../socket.sock',DATABASE 'test',user 'Spider',PASSWORD '');
CREATE TABLE t (c INT KEY,c1 BLOB,c2 TEXT) ENGINE=InnoDB;
CREATE TABLE tm (c INT KEY,c1 BLOB,c2 TEXT) ENGINE=MyISAM;
INSERT INTO t VALUES (0,NULL,'a'),(1,'B','b'),(2,0,'c');
CREATE TABLE t1 (c INT KEY,c1 BLOB,c2 TEXT) ENGINE=Spider COMMENT='WRAPPER "mysql",SRV "srv",TABLE "t"';
CREATE TABLE t2 (c INT KEY,c1 BLOB,c2 TEXT) ENGINE=Spider COMMENT='WRAPPER "mysql",SRV "srv",TABLE "tm"';
SHOW CREATE TABLE t2;
INSERT INTO t1 VALUES (3,NULL,'a'),(4,'B','b'),(5,0,'c');
SET GLOBAL collation_connection=utf32_icelandic_ci;
DELETE FROM t1 USING t1,t2;
CLI: ERROR 1298 (HY000): Unknown or incorrect time zone: '+00:00'
ERR: [ERROR] Got error 1440 when reading table './test/t1'
