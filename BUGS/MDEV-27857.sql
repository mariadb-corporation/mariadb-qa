CREATE OR REPLACE TABLE mysql.general_log (a INT);
SET SESSION sql_log_off=1;
SET GLOBAL init_slave='SELECT 3';
SET GLOBAL log_output='TABLE';
SET GLOBAL general_log=1;
CHANGE MASTER TO master_host='127.0.0.1';
START SLAVE sql_thread;
