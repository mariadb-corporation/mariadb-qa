CREATE TABLE t1 (c INT) ENGINE=InnoDB;
SET SESSION sql_mode='TRADITIONAL';
CREATE TRIGGER wl1_trg1 BEFORE INSERT ON t1 FOR EACH ROW INSERT INTO t1 VALUES (CURRENT_USER());
CREATE TEMPORARY TABLE t1 ENGINE=InnoDB AS SELECT 1;
SET GLOBAL slave_run_triggers_for_rbr=YES;
BINLOG ' SOgWTg8BAAAAbgAAAHIAAAAAAAQANS42LjMtbTUtZGVidWctbG9nAAAAAAAAAAAAAAAAAAAAAAAA AAAAAAAAAAAAAAAAAABI6BZOEzgNAAgAEgAEBAQEEgAAVgAEGggAAAAICAgCAAAAAAVAYI8=';
BINLOG 'wlZOTxMBAAAAKgAAADwCAAAAACkAAAAAAAEABHRlc3QAAnQxAAIDAwAC wlZOTxcBAAAAJgAAAGICAAAAACkAAAAAAAEAAv/8AgAAAAgAAAA=';
# CLI: ERROR 1366 (22007): Incorrect integer value: 'root@localhost' for column `test`.`t1`.`1` at row 1
# ERR: [ERROR]  BINLOG_BASE64_EVENT: Could not execute Write_rows_v1 event on table test.t1; Incorrect integer value: 'root@localhost' for column `test`.`t1`.`1` at row 1, Error_code: 1366; At line 1 in test.wl1_trg1, Error_code: 4094; handler error HA_ERR_GENERIC; the event's master log FIRST, end_log_pos 610, Internal MariaDB error code: 1366

CREATE TABLE t1 (c INT) ENGINE=InnoDB;
SET SESSION sql_mode='TRADITIONAL';
CREATE TRIGGER wl1_trg1 BEFORE INSERT ON t1 FOR EACH ROW INSERT INTO t1 VALUES (CURRENT_USER());
SET GLOBAL slave_run_triggers_for_rbr=YES;
BINLOG ' SOgWTg8BAAAAbgAAAHIAAAAAAAQANS42LjMtbTUtZGVidWctbG9nAAAAAAAAAAAAAAAAAAAAAAAA AAAAAAAAAAAAAAAAAABI6BZOEzgNAAgAEgAEBAQEEgAAVgAEGggAAAAICAgCAAAAAAVAYI8=';
BINLOG 'wlZOTxMBAAAAKgAAADwCAAAAACkAAAAAAAEABHRlc3QAAnQxAAIDAwAC wlZOTxcBAAAAJgAAAGICAAAAACkAAAAAAAEAAv/8AgAAAAgAAAA=';
# CLI: ERROR 1442 (HY000): Can't update table 't1' in stored function/trigger because it is already used by statement which invoked this stored function/trigger
# ERR: [ERROR]  BINLOG_BASE64_EVENT: Could not execute Write_rows_v1 event on table test.t1; Can't update table 't1' in stored function/trigger because it is already used by statement which invoked this stored function/trigger, Error_code: 1442; At line 1 in test.wl1_trg1, Error_code: 4094; handler error HA_ERR_GENERIC; the event's master log FIRST, end_log_pos 610, Internal MariaDB error code: 1442
