INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE USER Spider@localhost IDENTIFIED BY 'pwd';
CREATE SERVER s FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET "./socket.sock",DATABASE 'test',user 'Spider',PASSWORD 'pwd');
SET SESSION spider_delete_all_rows_type=0;
CREATE TABLE t2 (c INT);
CREATE TABLE t1 (c INT) ENGINE=Spider
COMMENT='WRAPPER "mysql", SERVER "s",TABLE "t2", delete_all_rows_type "0"';
INSERT IGNORE INTO t1 VALUES (42),(378);
SELECT * FROM t1;
DELETE FROM t1;
