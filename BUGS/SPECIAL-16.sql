CREATE VIEW t1 AS SELECT 1 f;
BINLOG ' SOgWTg8BAAAAbgAAAHIAAAAAAAQANS42LjMtbTUtZGVidWctbG9nAAAAAAAAAAAAAAAAAAAAAAAA AAAAAAAAAAAAAAAAAABI6BZOEzgNAAgAEgAEBAQEEgAAVgAEGggAAAAICAgCAAAAAAVAYI8=';
BINLOG 'wlZOTxMBAAAAKgAAADwCAAAAACkAAAAAAAEABHRlc3QAAnQxAAIDAwAC wlZOTxcBAAAAJgAAAGICAAAAACkAAAAAAAEAAv/8AgAAAAgAAAA=';
# [ERROR]  BINLOG_BASE64_EVENT: Error executing row event: ''test.t1' is not of type 'BASE TABLE'', Internal MariaDB error code: 1347
# This happens when t1 is a view

CREATE VIEW t1 AS SELECT 1 a;
SET sql_log_bin=0;
RENAME TABLE t1 TO t2;
CREATE TABLE t1 (a INT,b INT KEY) ENGINE=MEMORY;
INSERT DELAYED INTO t1 SET a=4;
# [ERROR] Slave SQL: Error executing row event: ''test.t1' is not of type 'BASE TABLE'', Gtid 0-1-5, Internal MariaDB error code: 1347
# [Warning] Slave: 'test.t1' is not of type 'BASE TABLE' Error_code: 1347
# [ERROR] Error running query, slave SQL thread aborted. Fix the problem, and restart the slave SQL thread with "SLAVE START". We stopped at log 'binlog.000001' position 1191; GTID position '0-1-4'
