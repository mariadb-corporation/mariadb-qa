CREATE TEMPORARY TABLE t (a INT KEY) ENGINE=MyISAM;
SET GLOBAL key_cache_segments=1;
INSERT INTO t VALUES (1);
SET GLOBAL key_cache_segments=1;
INSERT INTO t VALUES (1);
SET max_session_mem_used=8912;
ALTER TABLE t CHANGE COLUMN a a CHAR(1);
SELECT * FROM t;