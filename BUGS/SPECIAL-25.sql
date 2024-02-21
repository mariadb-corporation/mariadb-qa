CREATE TABLE t (c INT KEY);
SET sql_log_bin=0;
DROP TABLE t;
CREATE TABLE t (c INT);
SET sql_log_bin=1;
ALTER TABLE t ADD COLUMN d INT;
INSERT INTO t VALUES (0,0),(0,0);
# 2024-02-19  8:53:08 17 [Warning] Slave SQL: Could not execute Write_rows_v1 event on table test.t; Duplicate entry '0' for key 'PRIMARY', Error_code: 1062; handler error HA_ERR_FOUND_DUPP_KEY; the event's master log binlog.000001, end_log_pos 0, Gtid 0-1-6, Internal MariaDB error code: 1062
