SET GLOBAL slow_query_log=ON;
SET GLOBAL log_output='TABLE';
SET slow_query_log=ON;
SET long_query_time=0.000001;
SET @@time_zone="+01:00";
SET TIMESTAMP=1;
SET @@time_zone='+02:00';
SELECT * FROM mysql.slow_log;

SET GLOBAL log_output='TABLE', SESSION time_zone='+00:00';
SET GLOBAL log_queries_not_using_indexes=TRUE, GLOBAL slow_query_log=ON, SESSION slow_query_log=ON, SESSION log_slow_filter=DEFAULT;
SET TIMESTAMP=1000;
CREATE TABLE t (c INT) ENGINE=InnoDB;
DELETE FROM t;
SET SESSION time_zone='+01:00';
SELECT * FROM mysql.slow_log;
