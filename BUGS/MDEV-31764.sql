SET sql_mode='',in_predicate_conversion_threshold=2, max_heap_table_size=16384;
CREATE TABLE t1 (a INT) ENGINE=MyISAM;
INSERT INTO t1 VALUES (ST_GEOMFROMTEXT ('POINT(1 1)'));
ANALYZE FORMAT=JSON (SELECT * FROM t1 tbl1 WHERE a<5) UNION (SELECT * FROM t1 tbl2 WHERE a IN (2,3));
