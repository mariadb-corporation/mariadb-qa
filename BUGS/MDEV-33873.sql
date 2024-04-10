CREATE TABLE t (b INT) ENGINE=INNODB ;
INSTALL PLUGIN test_sql_service soname 'test_sql_service';
XA START 0x7465737462;
SET @@global.default_storage_engine=MEMORY;
INSERT INTO t VALUES(1);
SHUTDOWN;
