DELIMITER $
CREATE FUNCTION f1() RETURNS SYS_REFCURSOR 
BEGIN 
  DECLARE c SYS_REFCURSOR;
  OPEN c FOR SELECT 1;
  RETURN c;
END;
$
DELIMITER ;
CREATE TABLE t1 AS SELECT f1();
