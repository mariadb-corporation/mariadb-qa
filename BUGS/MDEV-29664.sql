INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE USER Spider@localhost IDENTIFIED BY 'PWD1';
CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock',DATABASE 'test',user 'Spider',PASSWORD 'PWD1');
CREATE TABLE t (c INT);
CREATE TABLE t1 (c1 TEXT) ENGINE=Spider COMMENT='WRAPPER "mysql",srv "srv",TABLE "t"';
CREATE OR REPLACE TABLE t2 AS SELECT FORMAT (c1,0) AS c1 FROM t1;  # 'OR REPLACE' is required
# Exit the CLI here to trigger the bug
