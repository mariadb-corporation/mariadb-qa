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

SET sql_mode='';
INSTALL PLUGIN spider SONAME 'ha_spider.so';
CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock', DATABASE 'test', USER 'Spider', PASSWORD '');
CREATE TABLE t1 (a INT, b VARCHAR(255), c1 INT, c2 INT, PRIMARY KEY(a), UNIQUE KEY(c1), KEY(c2) ) ENGINE=Spider AUTO_INCREMENT_MODE=1 DELETE_ALL_ROWS_TYPE=0 IDX="f c1 ig PRIMARY u c2" MULTI_SPLIT_READ=54 WRAPPER=mysql;
ALTER TABLE t1 READ_ONLY=0;
DELETE FROM t1;
DELETE FROM t1; # Crashing statement
SHUTDOWN;

SET sql_mode='';
INSTALL PLUGIN spider SONAME 'ha_spider.so';
CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock', DATABASE 'test', USER 'Spider', PASSWORD '');
CREATE TABLE t1 (a INT, b VARCHAR(255), c1 INT, c2 INT, PRIMARY KEY(a), UNIQUE KEY(c1), KEY(c2)) ENGINE=Spider AUTO_INCREMENT_MODE=1 DELETE_ALL_ROWS_TYPE=0 WRAPPER=mysql;
ALTER TABLE t1 READ_ONLY=0;
DELETE FROM t1;
DELETE FROM t1; # Hanging statement
SHUTDOWN;

CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock', DATABASE 'test', USER 'Spider', PASSWORD '');
CREATE TABLE t1 (a INT) ENGINE=MyISAM;
DROP TABLE t1;
INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE TABLE t1 (a INT, b VARCHAR(255), c1 INT, c2 INT, PRIMARY KEY(a), UNIQUE KEY(c1), KEY(c2)) ENGINE=Spider remote_database=foo63 default_file=foo44 default_group=foo45 delete_all_rows_type=0 DRIVER=foo47 DSN=foo48 FILEDSN=foo49 force_bulk_delete=1 force_bulk_update=NO remote_host=foo52 IDX="f c1 ig PRIMARY u c2" multi_split_read=54 net_read_timeout=" 55 56" net_write_timeout=" 56 " remote_password=foo57 REMOTE_PORT="234 837 " PRIORITY=59 query_cache=2 query_cache_sync=3 read_only=1 REMOTE_SERVER="srv" WRAPPER=mysql;
SELECT * FROM t1;
ALTER TABLE t1 read_only=0;
CREATE TABLE t2 (c INT) ENGINE=Spider COMMENT='WRAPPER "mysql", SRV "srv", TABLE "tm"';
SHOW CREATE TABLE t1;
INSERT INTO t1 VALUES (1, "aaa"),(2, "bbb"),(3, "ccc"),(4, "ddd");
SELECT * FROM t2;
DELETE FROM t1;
