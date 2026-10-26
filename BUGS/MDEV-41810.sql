# Requires MTR and a debug build: the CREATE OR REPLACE crashes the server at the debug_dbug point, then restart it; ref bug report for MTR testcase
CREATE TABLE t0 (b INT) ENGINE=InnoDB;
INSERT INTO t0 VALUES (2);
CREATE TABLE t1 (a INT) ENGINE=InnoDB;
INSERT INTO t1 VALUES (1);
SET @@debug_dbug="+d,ddl_log_create_after_revert", @debug_crash_counter=1;
CREATE OR REPLACE TABLE t1 ENGINE=InnoDB SELECT b FROM t0;
SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='test' AND TABLE_NAME='t1';
#CLI: returns 0; expected 1
#ERR: - (no error)

# Requires MTR and a debug build, with mysqld option --binlog-storage-engine=innodb: the CREATE OR REPLACE crashes the server at the debug_dbug point, then restart it; ref bug report for MTR testcase
CREATE TABLE t1 (a INT) ENGINE=InnoDB;
INSERT INTO t1 VALUES (1);
SET @@debug_dbug="+d,ddl_log_create_after_revert", @debug_crash_counter=1;
CREATE OR REPLACE TABLE t1 (b INT) ENGINE=InnoDB;
SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='test' AND TABLE_NAME='t1';
#CLI: returns 0; expected 1
#ERR: - (no error)
