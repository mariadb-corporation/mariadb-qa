SET sql_mode='';
INSTALL PLUGIN Spider SONAME 'ha_spider.so';
GRANT ALL ON * TO Spider@localhost;
CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock',DATABASE'',USER 'Spider',PASSWORD'');
CREATE TABLE t (c INT) ENGINE=InnoDB;
CREATE TABLE t1 (c INT) ENGINE=Spider COMMENT='WRAPPER "mysql",SRV "srv",TABLE "t"';
SET sql_mode=34359738368;  # Any values less than this, even -1, will not crash. Higher values will. This is 2147483648*2*2*2*2
SELECT * FROM t1;
