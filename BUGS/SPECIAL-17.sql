SET @@max_statement_time=0.0001;
BINLOG 'AMqaOw8BAAAAdAAAAHgAAAAAAAQANS42LjM0LTc5LjEtZGVidWctbG9nAAAAAAAAAAAAAAAAAAAA AAAAAAAAAAAAAAAAAAAAAAAAEzgNAAgAEgAEBAQEEgAAXAAEGggAAAAICAgCAAAACgoKGRkAAYVx w2w=';
set global binlog_format=mixed;
create table t1(o1 CHAR,o2 int,o3 int,primary key(o1,o2)) engine=MyISAM;
INSERT DELAYED INTO t1 VALUES(0,0||0);
INSERT INTO t1(c)VALUES();
SET lock_wait_timeout=0;
BINLOG 'wlZOTxMBAAAAKgAAADwCAAAAACkAAAAAAAEABHRlc3QAAnQxAAIDAwAC wlZOTxcBAAAAJgAAAGICAAAAACkAAAAAAAEAAv/8AgAAAAgAAAA=';
# [ERROR]  BINLOG_BASE64_EVENT: Error executing row event: 'Lock wait timeout exceeded; try restarting transaction', Internal MariaDB error code: 1205
