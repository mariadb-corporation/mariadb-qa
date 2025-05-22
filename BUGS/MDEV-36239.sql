INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE TABLE t (c INT) ENGINE=Spider;
ALTER TABLE t ENGINE=InnoDB;
SET character_set_connection=utf16;
SELECT spider_direct_sql ('DROP TABLE "t2"','','SRV "srv",WRAPPER "odbc"');

CREATE SERVER srv FOREIGN DATA WRAPPER mysql OPTIONS (SOCKET '../socket.sock',DATABASE'',USER'',PASSWORD'');
INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE TABLE t1 (c INT) PARTITION BY LIST COLUMNS (c) (PARTITION p DEFAULT ENGINE=Spider);
CREATE TABLE t2 (c INT) ENGINE=Spider COMMENT='WRAPPER "mysql",SRV "srv",TABLE "t1"';
XA START 'a';
INSERT INTO t1 VALUES (0);
INSERT INTO t2 VALUES (0);
SET SESSION collation_connection=utf32_estonian_ci;
SELECT spider_direct_sql('CREATE TABLE t2 (c INT)','','filedsn "$dsn_file",WRAPPER "odbc",DATABASE "test",user "root",SRV "srv"');
SHUTDOWN;
