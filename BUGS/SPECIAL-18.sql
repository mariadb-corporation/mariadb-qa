BINLOG 'AMqaOw8BAAAAdAAAAHgAAAAAAAQANS42LjM0LTc5LjEtZGVidWctbG9nAAAAAAAAAAAAAAAAAAAA AAAAAAAAAAAAAAAAAAAAAAAAEzgNAAgAEgAEBAQEEgAAXAAEGggAAAAICAgCAAAACgoKGRkAAYVx w2w=';
CREATE TABLE t1(c INT UNSIGNED KEY)collate ujis_nopad_bin;
SET max_session_mem_used=+ 1;
BINLOG 'wlZOTxMBAAAAKgAAADwCAAAAACkAAAAAAAEABHRlc3QAAnQxAAIDAwAC wlZOTxcBAAAAJgAAAGICAAAAACkAAAAAAAEAAv/8AgAAAAgAAAA=';
# CLI: ERROR 1290 (HY000): The MariaDB server is running with the --max-session-mem-used=8192 option so it cannot execute this statement
# ERR: [ERROR]  BINLOG_BASE64_EVENT: Error executing row event: 'The MariaDB server is running with the --max-session-mem-used=8192 option so it cannot execute this statement', Internal MariaDB error code: 1290

DROP DATABASE test;
CREATE DATABASE test;
USE test;
INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE TABLE t1 (a INT,b INT UNSIGNED,c BINARY,d BINARY,e BINARY,f CHAR,g BLOB,h BLOB,id INT,KEY(b)) ENGINE=Spider;
CREATE TABLE t2 (id INT) ENGINE=Spider;
SET max_session_mem_used=+1;
RENAME TABLE t2 TO t,t TO t2,t3 TO t2;
# CLI: ERROR 1290 (HY000): The MariaDB server is running with the --max-session-mem-used=8192 option so it cannot execute this statement
# ERR: [ERROR] DDL_LOG: Got error 1290 when trying to execute action for entry 2 of type 'rename table'

INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE SERVER srv FOREIGN DATA WRAPPER mysql OPTIONS (SOCKET'',DATABASE'',USER'',PASSWORD'');
CREATE TABLE t (c INT KEY,c1 BLOB,c2 TEXT) ENGINE=Spider COMMENT='WRAPPER "mysql",SRV "srv",TABLE "tm"';
SET SESSION max_session_mem_used=@@max_session_mem_used+1;
CREATE TABLE t2 (c1 INT,c2 CHAR BINARY CHARACTER SET 'utf8' COLLATE 'utf8_bin',c3 BLOB,KEY(c1)) ENGINE=InnoDB;
CREATE OR REPLACE TABLE t2 (x INT);
CREATE TABLE t3 (a INT DEFAULT 1,b CHAR DEFAULT'',c DATE DEFAULT '+1 :1:1',KEY(a)) ENGINE=InnoDB DEFAULT CHARSET=utf8;
ALTER TABLE t2 ADD COLUMN c1 INT COMMENT'';
DROP TABLE t3;
CREATE TABLE t4 (c1 INT);
RENAME TABLE t TO t3,t3 TO t,t3 TO t2;
# CLI: ERROR 1290 (HY000): The MariaDB server is running with the --max-session-mem-used=9223372036854775808 option so it cannot execute this statement
# ERR: [ERROR] DDL_LOG: Got error 1290 when trying to execute action for entry 5 of type 'rename table'
