# Requires MTR: 8 sessions, each with this SET timestamp, run the INSERT at the same time; ref bug report for MTR testcase
SET timestamp= UNIX_TIMESTAMP('2026-05-02 00:00:00');
CREATE TABLE t1 (c DATE) ENGINE=InnoDB PARTITION BY RANGE COLUMNS (c) INTERVAL 1 DAY (PARTITION p0 VALUES LESS THAN ('2026-04-30'));
INSERT INTO t1 VALUES ('2026-04-25');
SELECT COUNT(*) FROM information_schema.PARTITIONS WHERE TABLE_SCHEMA='test' AND TABLE_NAME='t1';
#CLI: returns 25 (varies by run); expected 4
#ERR: - (no error)
