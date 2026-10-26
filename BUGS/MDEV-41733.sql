# Requires two sessions: the SET timestamp and UPDATE after START TRANSACTION run in a second session; ref bug report for MTR testcase
SET timestamp= UNIX_TIMESTAMP('2026-05-02 00:00:00');
CREATE TABLE t1 (a INT) ENGINE=InnoDB WITH SYSTEM VERSIONING PARTITION BY SYSTEM_TIME INTERVAL 1 HOUR AUTO;
INSERT INTO t1 VALUES (1);
START TRANSACTION WITH CONSISTENT SNAPSHOT;
SET timestamp= UNIX_TIMESTAMP('2026-05-02 05:00:00');
UPDATE t1 SET a= 2;
SELECT COUNT(*) FROM t1 FOR SYSTEM_TIME ALL;
#CLI: ERROR 1412 (HY000): Table definition has changed, please retry transaction
#ERR: - (no error)
