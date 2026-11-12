SET sql_mode= 'NO_UNSIGNED_SUBTRACTION';
CREATE TABLE t1 (a INT UNSIGNED, b INT UNSIGNED) PARTITION BY HASH (a - b) PARTITIONS 5;
INSERT INTO t1 VALUES (1, 2);
FLUSH TABLES;
SET sql_mode= DEFAULT;
SELECT * FROM t1 WHERE a = 1 AND b = 2;
#CLI: ERROR 1690 (22003): BIGINT UNSIGNED value is out of range in '`test`.`t1`.`a` - `test`.`t1`.`b`'; expected 1 row (1, 2)
#ERR: - (no error)
