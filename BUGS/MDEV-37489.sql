DELIMITER //
CREATE PROCEDURE p0 (x INT DEFAULT func()) 
BEGIN 
  SELECT x;
END;
//
DELIMITER ;
SET SESSION max_session_mem_used=8192;
CALL p0();
SET @@max_session_mem_used=DEFAULT;
CALL p0();
SELECT * FROM information_schema.PARAMETERS;
