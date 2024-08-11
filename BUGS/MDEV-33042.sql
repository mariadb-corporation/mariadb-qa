INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE USER Spider@localhost IDENTIFIED BY 'PWD123';
GRANT ALL ON test.* TO Spider@localhost;
CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock', DATABASE 'test', USER 'Spider', PASSWORD 'PWD123');
CREATE TABLE t (c INT) ENGINE=InnoDB;
SET spider_internal_sql_log_off=0;
CREATE TABLE t1 (a INT PRIMARY KEY) ENGINE=Spider COMMENT='WRAPPER "mysql", srv "srv", TABLE "t"';
SELECT LEFT('a', SUM(a)) FROM t1;
# CLI: ERROR 1227 (42000): Access denied; you need (at least one of) the SUPER privilege(s) for this operation
# ERR: [ERROR] Got error 1227 when reading table './test/t1'

SET sql_mode='';
INSTALL PLUGIN Spider SONAME 'ha_spider.so';
GRANT ALL ON * TO Spider@localhost;
CREATE SERVER srv FOREIGN DATA WRAPPER MYSQL OPTIONS (SOCKET '../socket.sock',DATABASE'',USER 'Spider',PASSWORD'');
CREATE TABLE t (c INT KEY,c1 BLOB,c2 TEXT) ENGINE=InnoDB;
CREATE TABLE t1 (c INT KEY,c1 BLOB,c2 TEXT) ENGINE=Spider COMMENT='WRAPPER "mysql",SRV "srv",TABLE "t"';
ALTER TABLE t DISCARD TABLESPACE;
SELECT COUNT(*)=1 FROM t1;
# CLI: ERROR 1814 (HY000): Tablespace has been discarded for table `t`
# ERR: [ERROR] Got error 1814 when reading table './test/t1'
