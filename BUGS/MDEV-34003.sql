INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock',DATABASE'',USER'',PASSWORD'');
CREATE TABLE t (c INT KEY,c1 BLOB,c2 TEXT) ENGINE=InnoDB;
INSERT INTO t VALUES (0,1,0),(1,0,0),(2,0,0);
CREATE TABLE t2 (c INT KEY,c1 BLOB,c2 TEXT) ENGINE=Spider COMMENT='WRAPPER "mysql",SRV "srv",TABLE "t"';
SELECT * FROM t2 WHERE c=0;