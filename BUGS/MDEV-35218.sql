CREATE PROCEDURE proc_1() LOAD INDEX INTO CACHE new_t7 IGNORE LEAVES;
DROP TABLE IF EXISTS t;
SET max_session_mem_used=8192;
CREATE TABLE t (id INT KEY);
SELECT * FROM t;
SET GLOBAL wsrep_on=OFF;
BEGIN;
CALL proc_1();
SET GLOBAL wsrep_on=ON;
SELECT * FROM t;
CALL proc_1();
