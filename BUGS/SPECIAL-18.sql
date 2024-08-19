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
