# Requires m/s setup and --binlog_format=ROW on the master, and --slave_run_triggers_for_rbr=LOGGING on the slave
CREATE TABLE t (c INT);
INSERT INTO t VALUES (0);
CREATE TRIGGER tr BEFORE INSERT ON t FOR EACH ROW CALL p2();
SET SESSION sql_log_bin=0;
DROP TABLE t;
CREATE TABLE t (a INT);
SET SESSION sql_log_bin=1;
INSERT INTO t VALUES (1);
