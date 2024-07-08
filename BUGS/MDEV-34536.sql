SET sql_mode='';
SET SESSION in_predicate_conversion_threshold=2;
SET SESSION enforce_storage_engine=MEMORY;
SET join_cache_level=3;
CREATE TABLE t (c INT,c2 CHAR(20)) ENGINE=MYISAM;
INSERT INTO t VALUES (DEFAULT,DEFAULT);
INSERT INTO t (c) VALUES (1);
SELECT * FROM t WHERE c2 IN ('','');
