SET SESSION TRANSACTION ISOLATION LEVEL SERIALIZABLE;
INSTALL SONAME 'ha_rocksdb';
BINLOG ' SOgWTg8BAAAAbgAAAHIAAAAAAAQANS42LjMtbTUtZGVidWctbG9nAAAAAAAAAAAAAAAAAAAAAAAA AAAAAAAAAAAAAAAAAABI6BZOEzgNAAgAEgAEBAQEEgAAVgAEGggAAAAICAgCAAAAAAVAYI8=';
SET default_storage_engine=RocksDB;
create TABLE t1(c char,c2 INT);
BINLOG 'wlZOTxMBAAAAKgAAADwCAAAAACkAAAAAAAEABHRlc3QAAnQxAAIDAwAC wlZOTxcBAAAAJgAAAGICAAAAACkAAAAAAAEAAv/8AgAAAAgAAAA=';
# ERROR 4057 (HY000): MyRocks supports only READ COMMITTED and REPEATABLE READ isolation levels. Please change from current isolation level SERIALIZABLE