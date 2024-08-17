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

CREATE TABLE t(id int key)engine=MEMORY;
SET @@GLOBAL.binlog_format=STATEMENT;
SET SQL_LOG_BIN=0;
INSERT DELAYED INTO t VALUES(0);
SET @@GLOBAL.binlog_format=ROW;
SET SQL_LOG_BIN=1;
INSERT DELAYED INTO t VALUES(1);

# mysqld options required for replay: --log_bin 
SET GLOBAL binlog_format=1;
CREATE TABLE t (a CHAR(1),FULLTEXT (a)) ENGINE=MyISAM;
CALL sys.statement_performance_analyzer (1,1,1);
INSERT DELAYED INTO t VALUES (2);
SET GLOBAL binlog_format=MIXED;
SET sql_log_bin=1;
INSERT DELAYED INTO t VALUES (1);
