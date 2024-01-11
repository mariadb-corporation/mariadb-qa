INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock',DATABASE'',USER'',PASSWORD'');
CREATE TABLE t (c INT KEY,c1 BLOB,c2 TEXT) ENGINE=InnoDB;
INSERT INTO t VALUES (1,0,0),(2,0,0);
CREATE TABLE t1 (c INT KEY,c1 BLOB,c2 TEXT) ENGINE=Spider COMMENT='WRAPPER "mysql",SRV "srv",TABLE "t"';
SET spider_disable_group_by_handler=1, spider_quick_page_byte=0, spider_bgs_mode=1;
SELECT * FROM t1;
