SET GLOBAL query_cache_type=ON;
SET GLOBAL query_cache_size=1024*64;
USE test;
CREATE TABLE t (a INT) PARTITION BY KEY(a) PARTITIONS 99;
SET SESSION query_cache_type=DEFAULT;
SELECT COUNT(*) FROM t WHERE c1=2;