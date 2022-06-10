# Keep repeating/looping till it crashes (~2)
# mysqld options required for replay: --log-bin 
DROP DATABASE test;
CREATE DATABASE test;
USE test;
SET GLOBAL binlog_format=1;
SET SESSION default_storage_engine='MEMORY';
SET sql_log_bin=0;
CREATE TABLE t (a INT KEY,b INT);
INSERT DELAYED INTO t VALUES (1,0),(1,0),(1,0);
SET sql_log_bin=1;
SET GLOBAL binlog_format=MIXED;
INSERT DELAYED INTO t VALUES (1,0),(1,0),(1,0);
