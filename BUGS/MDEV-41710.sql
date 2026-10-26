# Replication setup required, binlog_format=ROW; run SET GLOBAL time_zone on the replica and restart its SQL thread, the rest on the master; ref bug report for MTR testcase
CREATE TABLE t1 (c DATE) PARTITION BY RANGE COLUMNS (c) INTERVAL 1 DAY (PARTITION p0 VALUES LESS THAN ('2026-04-30'));
SET GLOBAL time_zone='+00:00';
SET time_zone='+13:00';
SET timestamp= UNIX_TIMESTAMP('2026-05-03 01:00:00');
INSERT INTO t1 VALUES ('2026-05-03');
#CLI: - (no error on the master); on the replica, SHOW SLAVE STATUS gives Slave_SQL_Running No and Last_SQL_Errno 1526
#ERR: [ERROR] Slave SQL: Could not execute Write_rows_v1 event on table test.t1; Table has no partition for value from column_list, Error_code: 1526; handler error HA_ERR_NO_PARTITION_FOUND; the event's master log master-bin.000001, end_log_pos 0, Gtid 0-1-2, Internal MariaDB error code: 1526
#ERR: [ERROR] Error running query, slave SQL thread aborted. Fix the problem, and restart the slave SQL thread with "SLAVE START". We stopped at log 'master-bin.000001' position 587; GTID position '0-1-1'
