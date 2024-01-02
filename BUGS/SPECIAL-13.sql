BINLOG ' SOgWTg8BAAAAbgAAAHIAAAAAAAQANS42LjMtbTUtZGVidWctbG9nAAAAAAAAAAAAAAAAAAAAAAAA AAAAAAAAAAAAAAAAAABI6BZOEzgNAAgAEgAEBAQEEgAAVgAEGggAAAAICAgCAAAAAAVAYI8=';
INSTALL PLUGIN Spider SONAME 'ha_spider.so';
CREATE TABLE t1(a INT UNSIGNED,b INT,c BINARY,d BINARY,e CHAR,f BINARY,g BLOB,h BLOB,id INT,KEY(b)) ENGINE=Spider;
BINLOG 'wlZOTxMBAAAAKgAAADwCAAAAACkAAAAAAAEABHRlc3QAAnQxAAIDAwAC wlZOTxcBAAAAJgAAAGICAAAAACkAAAAAAAEAAv/8AgAAAAgAAAA=';
# ERROR 1429 (HY000): Unable to connect to foreign data source: localhost
# [ERROR]  BINLOG_BASE64_EVENT: Could not execute Write_rows_v1 event on table test.t1; Unable to connect to foreign data source: localhost, Error_code: 1429; Unable to connect to foreign data source: localhost, Error_code: 1429; Unable to connect to foreign data source: localhost, Error_code: 1429; handler error No Error!; the event's master log FIRST, end_log_pos 610, Internal MariaDB error code: 1429
