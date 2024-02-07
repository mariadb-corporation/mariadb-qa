RENAME TABLE mysql.gtid_slave_pos TO mysql.old_gtid_slave_pos;
# or
DROP DATABASE mysql;
# [ERROR] Slave SQL: Error during XID COMMIT: failed to update GTID state in mysql.gtid_slave_pos: 1146:  Table 'mysql.gtid_slave_pos' doesn't exist, Error_code: 1146; the event's master log binlog.000001, end_log_pos 17703, Gtid 0-1-68, Internal MariaDB error code: 1942
# Or similar 1942 errors or warnings
