DELIMITER $$
CREATE OR REPLACE PROCEDURE proc_461() 
BEGIN 
  DECLARE c sys_refcursor;
  OPEN c FOR 1 USING fun1_963(); 
  CLOSE c;
END;
$$
DELIMITER ;
CALL proc_461 (1,1,1);
CALL proc_296 (11);
SET max_statement_time=0.0001;
SET SESSION wsrep_retry_autocommit=0;
CALL proc_461;
CALL proc_461;
SELECT SLEEP(2);
CALL proc_461;
