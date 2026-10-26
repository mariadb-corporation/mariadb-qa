# Requires MTR & Galera (two nodes); the last SELECT and the error log are on node 2; ref bug report for MTR testcase
SET timestamp= UNIX_TIMESTAMP('2026-05-02 00:00:00');
CREATE TABLE t1 (a INT, c DATE, PRIMARY KEY (a, c)) ENGINE=InnoDB PARTITION BY RANGE COLUMNS (c) INTERVAL 1 DAY (PARTITION p0 VALUES LESS THAN ('2026-04-30'));
INSERT INTO t1 VALUES (1, '2026-05-01');
SELECT COUNT(*) FROM t1;
#CLI: ERROR 1047 (08S01): WSREP has not yet prepared node for application use
#ERR: [ERROR] Slave SQL: Could not execute Write_rows_v1 event on table test.t1; Table has no partition for value from column_list, Error_code: 1526; handler error HA_ERR_NO_PARTITION_FOUND; the event's master log FIRST, end_log_pos 0, Internal MariaDB error code: 1526
#ERR: [ERROR] WSREP: Inconsistency detected: Inconsistent by consensus on 479bd8d1-c1ef-11f1-8ff8-bf53ffcace64:4
#ERR: [ERROR] WSREP: Failed to apply write set: gtid: 479bd8d1-c1ef-11f1-8ff8-bf53ffcace64:4 server_id: 479b2e84-c1ef-11f1-9138-ea055e1fd101 client_id: 12 trx_id: 55 flags: 3 (start_transaction | commit)
