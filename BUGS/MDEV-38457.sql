CREATE GLOBAL TEMPORARY TABLE t (c INT);
BEGIN;
SELECT * FROM t;
SET pseudo_slave_mode=1;
# CLI: ERROR 1231 (42000): Variable 'pseudo_slave_mode' can't be set to the value of '1'

CREATE GLOBAL TEMPORARY TABLE t (c INT);
BEGIN;
SELECT * FROM t;
SET pseudo_thread_id=0;
# CLI: ERROR 1231 (42000): Variable 'pseudo_thread_id' can't be set to the value of '0'
