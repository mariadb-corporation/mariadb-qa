CREATE PROCEDURE test.p() SQL SECURITY INVOKER CALL test.p();
SET max_session_mem_used=8192;
SHOW PROCEDURE CODE p;
