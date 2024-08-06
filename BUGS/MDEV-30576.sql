INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock',DATABASE'test',USER'',PASSWORD'');
CREATE TABLE t (a INT) ENGINE=Spider COMMENT='WRAPPER "mysql",SRV "srv",TABLE "t"';
INSERT INTO t VALUES (1);
# ERROR 12719 (HY000): An infinite loop is detected when opening table test.t
