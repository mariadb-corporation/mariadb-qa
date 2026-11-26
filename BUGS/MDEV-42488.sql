# mysqld options required for replay: --plugin-load-add=ha_rocksdb.so
CREATE TABLE t1 (id INT NOT NULL, a INT, b INT, PRIMARY KEY (id), KEY ka (a), KEY kb (b)) ENGINE=RocksDB PARTITION BY HASH (id) PARTITIONS 4;
INSERT INTO t1 WITH RECURSIVE s (n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM s WHERE n < 300) SELECT n, n MOD 5, n MOD 7 FROM s;
ANALYZE TABLE t1;
SELECT COUNT(*) FROM t1 FORCE INDEX (ka, kb) WHERE a = 1 AND b = 1;
SELECT COUNT(*) FROM t1 FORCE INDEX (ka, kb) WHERE a = 1 OR b = 1;
#CLI: the first SELECT gives 3; expected 9. The second gives 102; expected 94
#ERR: - (no error)
