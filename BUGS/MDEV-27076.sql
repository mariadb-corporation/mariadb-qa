SET GLOBAL slow_query_log=ON;
SET GLOBAL log_output='TABLE';
SET slow_query_log=ON;
SET long_query_time=0.000001;
SET @@time_zone="+01:00";
SET TIMESTAMP=1;
SET @@time_zone='+02:00';
SELECT * FROM mysql.slow_log;
