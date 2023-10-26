INSTALL PLUGIN Spider SONAME 'ha_spider.so';
SHOW CREATE TABLE t;
CREATE TABLE t (c INT, PRIMARY KEY(c)) ENGINE=Spider;
SHOW CREATE TABLE t;
DROP TABLE t;
CREATE TABLE t (c INT) ENGINE=Spider REMOTE_PORT="1 1";
DELETE FROM t;

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
SHOW CREATE TABLE t;
CREATE TABLE t (c INT, PRIMARY KEY(c)) ENGINE=Spider;
SHOW CREATE TABLE t;
DROP TABLE t;
CREATE TABLE t (c INT) ENGINE=Spider COMMENT='port "1 1"';
DELETE FROM t;

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE TABLE t (a INT,PRIMARY KEY(a)) ENGINE=Spider;
SHOW CREATE TABLE t;
DROP TABLE t;
CREATE TABLE t (a INT) ENGINE=Spider COMMENT='PORT "1 1"';
INSERT INTO t VALUES (1),(1);

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE SERVER srv FOREIGN DATA WRAPPER mysql OPTIONS (SOCKET '../socket.sock',DATABASE 'test',user 'Spider',PASSWORD '');
CREATE TABLE t1 (a INT,b VARCHAR(255),PRIMARY KEY(a)) ENGINE=Spider COMMENT="srv 'srv', table 't1', read_only_mode '1'";
INSERT INTO t1 VALUES (1,'aaa'),(2,'bbb'),(3,'ccc'),(4,'ddd');
SHOW CREATE TABLE t1;
DROP TABLE t1;
CREATE TABLE t1 (a INT) ENGINE=Spider COMMENT='port "123 456"';
INSERT IGNORE INTO t1 VALUES (42),(42);

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE SERVER srv FOREIGN DATA WRAPPER mysql OPTIONS (SOCKET '../socket.sock', DATABASE 'test', USER 'Spider', PASSWORD '');
CREATE TABLE t1 (c INT, KEY(c)) ENGINE=Spider COMMENT='WRAPPER "mysql", SRV "srv",TABLE "t2", PK_NAME "f"';
SET GLOBAL general_log=1;
INSERT INTO t1 VALUES (1, "aaa"),(2, "bbb"),(3, "ccc"),(4, "ddd");
SHOW CREATE TABLE t1;
DROP TABLE t1;
CREATE TABLE t1 (a INT) ENGINE=Spider COMMENT='port "123 456"';
SELECT * FROM t1;
INSERT IGNORE INTO t1 VALUES (42),(42);

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock',DATABASE 'a',USER 'a',PASSWORD '');
CREATE TABLE t1 (c INT) ENGINE=Spider COMMENT='WRAPPER "mysql",SRV "srv",TABLE "t2",query_cache_sync "3"';
SHOW CREATE TABLE t1;
DROP TABLE t1;
CREATE TABLE t1 (a INT,b VARCHAR(1),c1 INT,c2 INT,PRIMARY KEY(a),UNIQUE KEY(c1),KEY(c2)) ENGINE=Spider AUTO_INCREMENT_mode=1 bgs_mode=1 bulk_size=41 bulk_update_size=42 connect_timeout="43 44" remote_database=foo63 default_file=foo44 default_group=foo45 delete_all_rows_type=0 DRIVER=foo47 DSN=foo48 FILEDSN=foo49 force_bulk_delete=1 force_bulk_update=NO remote_host=foo52 IDX="f c1 ig PRIMARY u c2" multi_split_read=54 net_read_timeout=" 55 56" net_write_timeout=" 56 " remote_password=foo57 REMOTE_PORT="234 837 " PRIORITY=59 query_cache=2 query_cache_sync=3 read_only=1 REMOTE_SERVER="srv" skip_parallel_search=2 remote_socket=foo67 ssl_capath=foo68 ssl_ca=foo69 ssl_cert=foo70 ssl_cipher=foo71 ssl_key=foo72 ssl_vsc=1 REMOTE_TABLE=foo65 table_count_mode=3 remote_username=foo75 use_pushdown_udf=YES WRAPPER=mysql;
SELECT MAX(a) FROM t1;

INSTALL PLUGIN spider SONAME 'ha_spider.so';
SET SESSION spider_ignore_comments=1;
CREATE TABLE t1 (c int) ENGINE=Spider COMMENT='WRAPPER "mysql",srv "srv",TABLE "t2", MONITORING_KIND "2"';
SHOW CREATE TABLE t1;
DROP TABLE t1;
CREATE TABLE t1 (a INT) ENGINE=Spider REMOTE_PORT="123 456";
DELETE FROM t1;

INSTALL PLUGIN spider SONAME 'ha_spider.so';
SET SESSION;
CREATE TABLE t1 (c int) ENGINE=Spider;
SHOW CREATE TABLE t1;
DROP TABLE t1;
CREATE TABLE t1 (a INT) ENGINE=Spider COMMENT="port '123 456'";
DELETE FROM t1;

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
SET SESSION SPIDER_IGNORE_COMMENTS=1;
CREATE TABLE t1 (c INT, d INT, e INT, PRIMARY KEY(c), KEY(d), UNIQUE KEY(e)) ENGINE=Spider COMMENT='WRAPPER "mysql", SRV "srv",TABLE "t2", idx000 "f PRIMARY", idx001 "u d", idx002 "ig e"';
SHOW CREATE TABLE t1;
DROP TABLE t1, t2;
SELECT * FROM t1;
CREATE TABLE t1 (a INT) ENGINE=Spider REMOTE_PORT="123 456";
SELECT * FROM t1;

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE TABLE t1 (c INT, d INT, e INT, PRIMARY KEY(c), KEY(d), UNIQUE KEY(e)) ENGINE=Spider;
SHOW CREATE TABLE t1;
DROP TABLE t1, t2;
SELECT * FROM t1;
CREATE TABLE t1 (a INT) ENGINE=Spider COMMENT="port '123 456'";
SELECT * FROM t1;
