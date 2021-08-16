CREATE OR REPLACE TABLE mysql.slow_log (a INT);
CREATE EVENT one_event ON SCHEDULE EVERY 10 SECOND DO SELECT 123;
SET GLOBAL slow_query_log=ON;
SET GLOBAL event_scheduler= 1;
SET GLOBAL log_output=',TABLE';
SET GLOBAL long_query_time=0.001;
SELECT SLEEP (3);

CREATE OR REPLACE TABLE mysql.slow_log (a INT);
DROP EVENT one_event;
CREATE EVENT one_event ON SCHEDULE EVERY 10 SECOND DO SELECT 123;
SET GLOBAL slow_query_log=ON;
SET GLOBAL event_scheduler= 1;
SET GLOBAL log_output=',TABLE';
SET GLOBAL long_query_time=0.001;
SELECT SLEEP (3);

SET sql_mode='';
CREATE OR REPLACE TABLE mysql.general_log (a INT) ENGINE=InnoDB;
CREATE TABLE t (c INT);
SET GLOBAL general_log=1;
SET GLOBAL log_output='TABLE,TABLE';
SET SESSION tx_read_only=1;
