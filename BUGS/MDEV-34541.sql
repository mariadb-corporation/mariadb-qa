SET sql_mode='', GLOBAL table_open_cache=10;
INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock',DATABASE'',USER'',PASSWORD'');
CREATE TABLE t1 (c INT) ENGINE=InnoDB;
CREATE TABLE t2 (c INT) ENGINE=InnoDB;
CREATE TABLE t3 (c INT) ENGINE=InnoDB;
CREATE TABLE ta (c INT) ENGINE=Spider COMMENT='WRAPPER "mysql",SRV "srv",TABLE "t"';
CREATE TABLE t5 (c INT) ENGINE=Spider COMMENT='WRAPPER "mysql",SRV "srv",TABLE "t"';
CREATE TABLE t6 (c INT KEY) ENGINE=InnoDB PARTITION BY RANGE (c) (PARTITION p VALUES LESS THAN (5));
CREATE TABLE t7 (a INT) ENGINE=Spider COMMENT='WRAPPER "mysql",SRV "srv",TABLE "t"';
CREATE TABLE t8 (c INT) ENGINE=Spider COMMENT='WRAPPER "mysql",SRV "srv",TABLE "t"';
SELECT * FROM t8;
CREATE TEMPORARY TABLE t7 (c INT) ENGINE=InnoDB SELECT * FROM t7;
CALL foo;
CREATE TEMPORARY TABLE t7 (c INT) ENGINE=InnoDB;
SELECT * FROM t7 JOIN t6 ON tc=t0.c;
SHOW TABLE STATUS;

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE USER Spider@localhost IDENTIFIED BY'';
CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS(SOCKET '../socket.sock',DATABASE'',user 'Spider',PASSWORD'');
CREATE TABLE t1(c INT KEY,c1 BLOB,c2 TEXT)ENGINE=InnoDB;
CREATE TABLE t2(c INT KEY,c1 BLOB,c2 TEXT)ENGINE=InnoDB;
CREATE TABLE t3(from_id INT UNSIGNED,to_id INT UNSIGNED,weight FLOAT,KEY(from_id,to_id)) ENGINE=Spider;
CREATE TABLE t4(fid INT KEY,g MULTIPOINT)ENGINE=Spider;
CREATE TABLE t5(a INT UNSIGNED,b INT UNSIGNED,c CHAR(1),d BINARY (1),e CHAR(1),f BINARY (1),g BLOB,h BLOB,id INT,KEY(b),KEY(e)) ENGINE=Spider COMMENT='WRAPPER "mysql",SRV "srv",TABLE "t"';
CREATE TABLE t6(id GEOMETRY,KEY(id (1))) ENGINE=Spider;
CREATE TABLE t7(c1 CHAR(1));
CREATE TABLE t8(c1 DEC,c2 CHAR(1),c3 INT(1),c4 CHAR (1) KEY,c5 DEC UNIQUE KEY,c6 NUMERIC(0,0) DEFAULT 3);
SET GLOBAL wait_timeout=True;
CREATE TABLE t9(a INT,b INT,KEY(a)) ENGINE=Spider;
SET GLOBAL table_open_cache=-1;
CREATE TABLE t10(f INT)ENGINE=Spider COMMENT='WRAPPER "mysql",SRV "srv",TABLE "t"';
SHOW TABLE STATUS;
SELECT SLEEP(1);
SHOW TABLE STATUS;
