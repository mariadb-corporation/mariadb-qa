SET sql_mode='';  # MOD
SET GLOBAL query_cache_type=DEMAND;
CREATE TABLE t1 (c1 SMALLINT NULL, c2 BINARY (25) NOT NULL, c3 TINYINT(4) NULL, c4 BINARY (15) NOT NULL PRIMARY KEY, c5 SMALLINT NOT NULL UNIQUE KEY,c6 DECIMAL(10,8) NOT NULL DEFAULT 3.141592);
SET GLOBAL query_cache_size=81920;
SELECT * FROM t1 WHERE b=1 AND c=1;
SET SESSION query_cache_type=1;
DROP TABLE t1;
CREATE TABLE t1 (c1 INT NOT NULL, c2 CHAR(5)) PARTITION BY LINEAR KEY(c1) PARTITIONS 99;
SELECT * FROM t1 WHERE c1 <='1998-12-29 00:00:00' ORDER BY c1,c2;
SELECT GROUP_CONCAT(a SEPARATOR '###') AS NAMES FROM t1 HAVING LEFT(NAMES, 1)='J';
SELECT * FROM t1;
SELECT COUNT(*) FROM t1;
SELECT C.a, c.a FROM t1 c, t1 C;
SELECT * FROM t1 WHERE c1 <='1998-12-29 00:00:00' ORDER BY c1,c2;
CREATE TABLE bug19145a (e ENUM ('a','b','c') DEFAULT 'b', s SET('x', 'y', 'z') DEFAULT 'y') ENGINE=RocksDB;
SELECT * FROM t1 WHERE c1 <> 0 ORDER BY c1,c6 DESC;
DROP DATABASE test;