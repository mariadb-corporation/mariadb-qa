# mysqld options required for replay:  --log-bin
SET sql_mode='';
SET GLOBAL key_cache_segments=1;
CREATE TEMPORARY TABLE t (f INT KEY) ENGINE=MyISAM;
INSERT INTO t VALUES (1),(2),(3);
LOAD INDEX INTO CACHE t INDEX (PRIMARY) IGNORE LEAVES;
SELECT * FROM t LIMIT 5;
INSERT INTO t VALUES (4),(5),(6),(7),(8),(9),(10),(11);
DELETE FROM t;
INSERT INTO t VALUES (1);
SET GLOBAL key_cache_segments=1;
SELECT * FROM t;

# mysqld options required for replay:  --log-bin
SET GLOBAL key_cache_segments=1;
CREATE TEMPORARY TABLE t (f INT KEY);
INSERT INTO t VALUES (1);
LOAD INDEX INTO CACHE t INDEX (PRIMARY);
SELECT * FROM t;
INSERT INTO t VALUES (2),(3),(4),(5),(6),(7),(8),(9),(10),(11);  # Note: ALL 10 insert values required
DELETE FROM t;
INSERT INTO t VALUES (1);
SET GLOBAL key_cache_segments=1;
SELECT * FROM t;  # [ERROR] Got error 134 when reading table / ER_KEY_NOT_FOUND (1032): Can't find record in 't'

# mysqld options required for replay:  --log-bin
SET GLOBAL key_cache_segments=1;
CREATE TEMPORARY TABLE t (f INT KEY);
INSERT INTO t VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11);  # Note: ALL 10 insert values required
DELETE FROM t;
INSERT INTO t VALUES (1);
SET GLOBAL key_cache_segments=1;
SELECT * FROM t;  # [ERROR] Got error 126 when reading table / HA_ERR_CRASHED (126): Index for table is corrupt

# mysqld options required for replay:  --log-bin
CREATE TEMPORARY TABLE t (a INT PRIMARY KEY,c CHAR,INDEX sec_index (c)) engine=MyISAM;
INSERT INTO t VALUES (1,1),(2,2);
SET GLOBAL key_cache_segments=1;
SELECT * FROM t LIMIT 1;
DELETE FROM t;
INSERT INTO t VALUES (1,1),(2,2),(3,3),(4,4),(5,5),(6,6),(7,7),(8,8),(9,9),(10,10),(11,11),(1,1);
DELETE FROM t;
INSERT INTO t VALUES (1,1);
DELETE FROM t;
INSERT INTO t VALUES (1,1);
SET GLOBAL key_cache_segments=1;
SELECT * FROM t;
