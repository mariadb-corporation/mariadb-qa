DELIMITER $$
CREATE PROCEDURE p1()
BEGIN
  DECLARE r ROW TYPE OF t1 DEFAULT 1;
  SELECT r.a, r.b;
END;
$$
DELIMITER ;
CREATE TEMPORARY TABLE t1 (c DECIMAL);
LOCK TABLE t1 READ;
ALTER TABLE t1 CHANGE c CC INT,ALGORITHM=INPLACE;
CALL p1();

