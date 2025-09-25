# mysqld options required for replay:  --log_bin=binlog --binlog_format=STATEMENT
CREATE GLOBAL TEMPORARY TABLE t1 (c INT);
CREATE TEMPORARY TABLE t2 (d INT);
CREATE OR REPLACE TEMPORARY TABLE t2 LIKE t1;
DROP TABLE t1, t2;  # Cleanup
