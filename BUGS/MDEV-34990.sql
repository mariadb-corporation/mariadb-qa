INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock',DATABASE'',USER'',PASSWORD'');
CREATE TABLE t (c INT KEY,c1 BLOB,c2 TEXT) ENGINE=InnoDB;
CREATE TABLE t1 (c INT KEY,c1 BLOB,c2 TEXT) ENGINE=Spider COMMENT='WRAPPER "mysql",SRV "srv",TABLE "t"';
LOCK TABLES t1 WRITE CONCURRENT,t1 AS t2 READ;
SELECT 1 FROM t1;

CLI: ERROR 1099 (HY000): Table 't' was locked with a READ lock and can't be updated
ERR: [ERROR] Got error 1099 when reading table './test/t1'
