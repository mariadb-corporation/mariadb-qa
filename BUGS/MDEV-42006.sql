CREATE TEMPORARY TABLE t (c INT PRIMARY KEY);
SET debug_dbug='+d,ib_create_table_fail_at_create_index';
TRUNCATE TABLE t;
