# Requires a normal m/s replication setup
SET SESSION binlog_format=STATEMENT;
CREATE TEMPORARY TABLE t2 (id INT);
CREATE TABLE t1 (c INT);
CREATE TABLE t (c INT);
CREATE TEMPORARY TABLE t (c INT);
INSERT INTO t SELECT table_rows FROM information_schema.tables LIMIT 1;
SHOW WARNINGS\G  # 1592: Unsafe statement written to the binary log using statement format since BINLOG_FORMAT = STATEMENT
SHUTDOWN;
