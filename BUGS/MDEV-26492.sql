SET sql_mode='';
SET GLOBAL key_cache_segments=10;
SET GLOBAL key_buffer_size=20000;
CREATE TEMPORARY TABLE t (a INT KEY) ENGINE=MyISAM;
INSERT INTO t VALUES (1),(2);
SET GLOBAL key_cache_block_size=2048;
SELECT * FROM t UNION SELECT * FROM t;

CREATE TEMPORARY TABLE t (a INT PRIMARY KEY) ENGINE=MyISAM;
SET GLOBAL key_cache_segments=2;
INSERT INTO t VALUES (0);
SET GLOBAL key_cache_segments=1;
SELECT a FROM t WHERE MATCH (a) AGAINST ('' IN BOOLEAN MODE);

SET GLOBAL key_buffer_size=1000000,key_cache_block_size=200000,key_cache_segments=8;
CREATE TEMPORARY TABLE t (c INT AUTO_INCREMENT KEY,d INT) ENGINE=MyISAM;
INSERT INTO t(d) VALUES (1),(1);
SET GLOBAL key_buffer_size=50000;
SELECT 1 FROM t;

# Observe '[ERROR] Got error 126 when reading table' in error log, or 'ERROR 126 (HY000): Index for table 'data/#sql-temptable-2d0059-4-0.MYI' is corrupt; try to repair it' in CLI
