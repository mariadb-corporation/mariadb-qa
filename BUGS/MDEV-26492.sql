SET sql_mode='';
SET GLOBAL key_cache_segments=10;
SET GLOBAL key_buffer_size=20000;
CREATE TEMPORARY TABLE t (a INT KEY) ENGINE=MyISAM;
INSERT INTO t VALUES (1),(2);
SET GLOBAL key_cache_block_size=2048;
SELECT * FROM t UNION SELECT * FROM t;
