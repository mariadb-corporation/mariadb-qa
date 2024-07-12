SET SESSION default_tmp_storage_engine=MEMORY, sql_mode=no_auto_value_on_zero;
CREATE TEMPORARY TABLE t (a INT AUTO_INCREMENT KEY);
INSERT INTO t VALUES (2147483647),(-2147483647),(0);  # Will not crash when both values are changed to 2147483646 (MAX_INT-1)
SET sql_mode=traditional;
INSERT INTO t VALUES (1);
INSERT IGNORE INTO t SELECT a FROM t AS t2 ON DUPLICATE KEY UPDATE a=t.a;
