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

CREATE TABLE t (c INT) ENGINE=MyISAM;
INSERT INTO t VALUES (0);
SET GLOBAL key_cache_segments=1;
CREATE TEMPORARY TABLE t (a INT,KEY (a)) ENGINE=MyISAM;
INSERT INTO t VALUES (NULL);
SET GLOBAL key_cache_segments=1;
INSERT INTO t VALUES (0);

SET sql_mode='';
SET GLOBAL key_cache_segments=2;
SET SESSION default_tmp_storage_engine=MyISAM;
CREATE TEMPORARY TABLE t (a INT KEY);
INSERT INTO t VALUES (0x7FFF);
INSERT INTO t VALUES();
SET GLOBAL key_cache_segments=1;
SELECT * FROM t;

# For all of the above testcases: observe '[ERROR] Got error 126 when reading table' in error log, or 'ERROR 126 (HY000): Index for table 'data/#sql-temptable-2d0059-4-0.MYI' is corrupt; try to repair it' in CLI. The testcase below crashes the server

CREATE TABLE t (c INT) ENGINE=MyISAM;
INSERT INTO t VALUES (0);
SELECT * FROM t INTO OUTFILE 'a';
SET GLOBAL key_cache_segments=1;
CREATE TEMPORARY TABLE t (a INT,KEY (a)) ENGINE=MyISAM;
INSERT INTO t VALUES (NULL);
SET GLOBAL key_cache_segments=1;
LOAD DATA INFILE 'a' INTO TABLE t;

# mysqld options required for replay:  --sql_mode=
SET SESSION enforce_storage_engine=MyISAM;
SET GLOBAL key_cache_segments=1;
CREATE TEMPORARY TABLE t (c TIME KEY,c2 TEXT BINARY CHARACTER SET 'BINARY' COLLATE 'BINARY',c3 CHAR(2) CHARACTER SET 'BINARY' COLLATE 'BINARY');
SET sql_select_limit=2;
INSERT INTO t (c) VALUES (7),(8),(9);
SET GLOBAL key_cache_segments=1;
SELECT * FROM t ORDER BY c;

SET GLOBAL key_cache_segments=2;
CREATE TEMPORARY TABLE t (a INT KEY) ENGINE=MyISAM;
INSERT INTO t VALUES (1);
INSERT INTO t VALUES (1+1);
SET GLOBAL key_cache_segments=0;
SELECT * FROM t;

SET @start_global_value=@@GLOBAL.sync_master_info;
SET GLOBAL key_cache_segments=@start_global_value;
CREATE TEMPORARY TABLE t2 (c BINARY,c2 DECIMAL UNSIGNED,c3 REAL(1,0) UNSIGNED ZEROFILL,KEY(c)) ENGINE=MyISAM;
INSERT INTO t2 (c) VALUES (8),(9);
SET GLOBAL key_cache_segments=2;
SELECT 1 FROM t2;

SET GLOBAL delay_key_write=ALL, GLOBAL key_cache_segments=1;
CREATE TABLE t (c1 INT KEY) ENGINE=MyISAM;
INSERT INTO t VALUES (1),(2);
SET GLOBAL key_cache_segments=10;
SELECT 1 FROM t;

SET GLOBAL key_cache_segments=1;
CREATE TEMPORARY TABLE t (c INT,INDEX (c)) UNION=(t,t2) ENGINE=MyISAM;
INSERT INTO t VALUES (1);
SET GLOBAL key_cache_segments=1;
INSERT INTO t VALUES();
ALTER TABLE t CHANGE c c INT FIRST,ALGORITHM=INPLACE;
INSERT INTO t (id,a) VALUES (1);
SHOW TABLES;

CREATE TEMPORARY TABLE t (f INT PRIMARY KEY) ENGINE=MyISAM;
SET GLOBAL key_cache_segments=1;
INSERT INTO t VALUES (1),(1);
SET GLOBAL key_cache_segments=1;
INSERT INTO t VALUES (1);
# CLI: ERROR 126 (HY000): Index for table 'ariadb-11.4.8-linux-x86_64-dbg/tmp/#sql-temptable-28967a-4-0.MYI' is corrupt; try to repair it
# [ERROR] mariadbd: Index for table 'ariadb-11.4.8-linux-x86_64-dbg/tmp/#sql-temptable-28967a-4-0.MYI' is corrupt; try to repair it
# [ERROR] Got an error from unknown thread, /test/11.4_dbg/storage/myisam/mi_write.c:226
# [ERROR] mariadbd: Index for table 't' is corrupt; try to repair it
