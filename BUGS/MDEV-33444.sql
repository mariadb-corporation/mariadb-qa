SET GLOBAL delay_key_write=ALL;
CREATE TABLE t (c INT KEY) ENGINE=MyISAM;
SET GLOBAL key_cache_segments=10;
INSERT INTO t VALUES (1);
SET GLOBAL key_cache_segments=10, GLOBAL table_open_cache=1024;
INSERT INTO t VALUES (1);
