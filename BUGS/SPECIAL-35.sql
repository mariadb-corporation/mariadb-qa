# mysqld options required for replay:  --plugin_load_add=ha_rocksdb
BINLOG ' O1ZVRw8BAAAAZgAAAGoAAAAAAAQANS4xLjIzLXJjLWRlYnVnLWxvZwAAAAAAAAAAAAAAAAAAAAAA AAAAAAAAAAAAAAAAAAA7VlVHEzgNAAgAEgAEBAQEEgAAUwAEGggAAAAICAgC ';
CREATE TABLE t1 (a INT KEY,b INT,c INT,KEY t1x1 (b),KEY t1x2 (c)) ENGINE=RocksDB;
SET rocksdb_max_row_locks=0;
BINLOG 'wlZOTxMBAAAAKgAAADwCAAAAACkAAAAAAAEABHRlc3QAAnQxAAIDAwAC wlZOTxcBAAAAJgAAAGICAAAAACkAAAAAAAEAAv/8AgAAAAgAAAA=';
# ERR: [ERROR]  BINLOG_BASE64_EVENT: Could not execute Write_rows_v1 event on table test.t1; Got error 10 'Operation aborted: Failed to acquire lock due to rocksdb_max_row_locks limit' from ROCKSDB, Error_code: 1296; Got error 221 'RocksDB status: lock limit reached.' from ROCKSDB, Error_code: 1296; handler error No Error!; the event's master log FIRST, end_log_pos 610, Internal MariaDB error code: 1296
