SET sql_mode=0;
DELIMITER $$
CREATE PROCEDURE p() BEGIN DECLARE b,c INT DEFAULT f(); SELECT b - c; END; $$
DELIMITER ;
SET max_session_mem_used=8192;
CALL p();
SET max_session_mem_used=DEFAULT;
CALL p();
