INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE USER Spider@localhost IDENTIFIED BY 'PWD123';
GRANT ALL ON test.* TO Spider@localhost;
CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock', DATABASE 'test', USER 'Spider', PASSWORD 'PWD123');
CREATE TABLE t (c INT) ENGINE=InnoDB;
SET spider_internal_sql_log_off=0;
CREATE TABLE t1 (a INT PRIMARY KEY) ENGINE=Spider COMMENT='WRAPPER "mysql", srv "srv", TABLE "t"';
SELECT LEFT('a', SUM(a)) FROM t1;

CREATE USER Spider@localhost IDENTIFIED BY 'PWD123';
CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock', DATABASE 'test', USER 'Spider', PASSWORD 'PWD123');
CREATE TABLE t1 (c1 CHAR(3)) DEFAULT CHARSET=sjis ENGINE=Spider COMMENT='WRAPPER "mysql", srv "srv", TABLE "t"';
SET spider_internal_sql_log_off=0;
HANDLER t1 OPEN;
HANDLER t1 READ FIRST;

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
SET sql_mode='', spider_internal_sql_log_off=0, spider_disable_group_by_handler=1;
CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock',DATABASE'',USER'',PASSWORD'');
CREATE TABLE t1 (c INT) ENGINE=InnoDB;
CREATE TABLE t2 (c INT) ENGINE=Spider COMMENT='WRAPPER "mysql",SRV "srv",TABLE "t1"';
CREATE TEMPORARY TABLE t2 (c INT) ENGINE=InnoDB;
DROP TABLE t2;
SELECT 1 FROM t2;
