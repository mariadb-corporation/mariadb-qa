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
