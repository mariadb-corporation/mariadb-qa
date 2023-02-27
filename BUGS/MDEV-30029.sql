SET GLOBAL wsrep_on=OFF;
SET max_session_mem_used = 50000;
XA START 'a';
CREATE TEMPORARY TABLE t1(a INT) engine=innodb;
SET @@session.query_prealloc_size = 30;
LOAD INDEX INTO CACHE t1;
SET GLOBAL wsrep_on = TRUE;
INSERT INTO t1 VALUES(1);
SHUTDOWN;
