SET log_slow_query=ON;
SET SESSION long_query_time=0;
SET log_slow_disabled_statements=0;
SET GLOBAL slow_query_log=1;
DELIMITER //
BEGIN NOT ATOMIC SELECT 1;END//
DELIMITER ;
