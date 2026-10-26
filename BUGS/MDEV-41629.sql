SET time_zone='+00:00';
SET timestamp= UNIX_TIMESTAMP('2026-05-02 00:00:00');
CREATE TABLE t1 (ts TIMESTAMP) ENGINE=InnoDB PARTITION BY RANGE COLUMNS (ts) INTERVAL 1 DAY (PARTITION p0 VALUES LESS THAN ('2026-04-30 12:00:00'));
INSERT INTO t1 VALUES ('2026-04-30 11:00:00');
FLUSH TABLES;
SET time_zone='+05:00';
SELECT COUNT(*) FROM t1 WHERE ts = '2026-04-30 16:00:00';
CHECK TABLE t1;
#CLI: 0; expected 1
#CLI: CHECK TABLE t1: Found a misplaced row; Partition p0 returned error; Upgrade required. Please do "REPAIR TABLE `t1`" or dump/reload to fix it!
#ERR: - (no error)
