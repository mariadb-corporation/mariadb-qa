CREATE TABLE t1 (a INT);
BINLOG 'wlZOTxMBAAAAKgAAADwCAAAAACkAAAAAAAEABHRlc3QAAnQxAAIDAwAC wlZOTxcBAAAAJgAAAGICAAAAACkAAAAAAAEAAv/8AgAAAAgAAAA=';
#ERR: [Warning]  BINLOG_BASE64_EVENT: Table structure for binlog event is not compatible with the table definition on this slave: Column 2 missing from table 'test.t1', Internal MariaDB error code: 4254
#CREATE TABLE t1 (a INT, b INT);  # Will work fine (no errors), as per the error message: there is no bug here
