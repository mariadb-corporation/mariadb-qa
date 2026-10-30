SET timestamp= UNIX_TIMESTAMP('2026-06-15 00:00:00');
CREATE TABLE t1 (c DATE) PARTITION BY RANGE COLUMNS (c) INTERVAL 1 MONTH (PARTITION P1 VALUES LESS THAN ('2026-03-01'));
INSERT INTO t1 VALUES ('2026-06-01');
SHOW WARNINGS;
#CLI: ERROR 1517 (HY000): Duplicate partition name p1
#CLI: Warning 4268 Range partition table %s.%s: adding INTERVAL partition(s) failed; expected `test`.`t1` in place of %s.%s
#ERR: - (no error)
