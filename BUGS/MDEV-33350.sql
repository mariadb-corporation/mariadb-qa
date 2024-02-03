# Requires standard m/s setup
SET sql_mode='',unique_checks=0,foreign_key_checks=0,autocommit=0;
CREATE TABLE t1 (c1 INT UNIQUE KEY) ENGINE=InnoDB;
CREATE TABLE t2 (c1 BINARY (0),c2 INT UNIQUE KEY) ENGINE=InnoDB;
INSERT INTO t2 VALUES (0,0);
INSERT INTO t1 VALUES (0,0);
CREATE TEMPORARY TABLE t1 (c INT);
INSERT INTO t2 VALUES (0,0);
# [ERROR] Slave SQL: Could not execute Write_rows_v1 event on table test.t2; Duplicate entry '0' for key 'c2', Error_code: 1062; handler error HA_ERR_FOUND_DUPP_KEY; the event's master log binlog.000001, end_log_pos 0, Gtid 0-1-6, Internal MariaDB error code: 1062
# [Warning] Slave: Duplicate entry '0' for key 'c2' Error_code: 1062
# [ERROR] Error running query, slave SQL thread aborted. Fix the problem, and restart the slave SQL thread with "SLAVE START". We stopped at log 'binlog.000001' position 1307; GTID position '0-1-5'
