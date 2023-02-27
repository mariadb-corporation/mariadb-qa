INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE USER Spider@localhost IDENTIFIED BY 'PWD123';
CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock', DATABASE 'test', USER 'Spider', PASSWORD 'PWD123');
CREATE TABLE t (c INT);
CREATE TABLE t_s (c INT) ENGINE=Spider COMMENT='WRAPPER "mysql", srv "srv", TABLE "t"';
SET GLOBAL table_open_cache=10;
CREATE TABLE t1 (a INT) ENGINE=Spider;
SELECT * FROM t1;
SELECT * FROM information_schema.tables;;
