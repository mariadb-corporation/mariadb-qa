# Requires m/s setup and --binlog_format=ROW on the master, and --slave_run_triggers_for_rbr=LOGGING on the slave
CREATE TABLE t1 (c1 INT UNSIGNED,c2 INT SIGNED,INDEX idx2 (c2)) ENGINE=InnoDB;
CREATE TRIGGER t1_bd BEFORE DELETE ON t1 FOR EACH ROW DELETE FROM t2;
CREATE TABLE t2 (i INT NOT NULL);
INSERT INTO t2 VALUES (1);
INSERT INTO t1 VALUES (11,REPEAT ('',200)),(12,REPEAT ('',200)),(13,REPEAT ('',200));
CREATE USER a IDENTIFIED BY '';
DELETE FROM t1;
# Leads to: .Warning. Slave SQL: Could not execute Delete_rows_v1 event on table test.t1; Can.t update table .t2. in stored function.trigger because it is already used by statement which invoked this stored function.trigger, Error_code: 1442; At line 1 in test.t1_bd, Error_code: 4094; handler error HA_ERR_GENERIC; the event.s master log binlog.*end_log_pos.*gtid.*Internal MariaDB error code: 1442

# Requires m/s setup and --binlog_format=ROW on the master, and --slave_run_triggers_for_rbr=LOGGING on the slave
CREATE TABLE t1 (c INT);
CREATE TABLE t2 (c INT);
INSERT INTO t1 VALUES(1);
INSERT INTO t2 VALUES(0);
CREATE TRIGGER tr1 BEFORE DELETE ON t1 FOR EACH ROW DELETE FROM t2;
DELETE FROM t1;

# Requires m/s setup and --binlog_format=ROW on the master, and --slave_run_triggers_for_rbr=LOGGING on the slave
CREATE TABLE t1 (c INT);
CREATE TABLE t2 (c INT);
CREATE TRIGGER tr BEFORE INSERT ON t2 FOR EACH ROW INSERT INTO t1 VALUES (new.c);
INSERT INTO t2 VALUES (1);
# Leads to: .Warning. Slave SQL: Could not execute Write_rows_v1 event on table test.t1; PROCEDURE.*does not exist, Error_code: 1305; At line 1 in test.t1_bi, Error_code: 4094; handler error HA_ERR_GENERIC; the event.s master log binlog.*end_log_pos.*gtid.*Internal MariaDB error code: 1305
