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

CREATE OR REPLACE TABLE mysql.general_log (a INT) ENGINE=InnoDB;
SET GLOBAL event_scheduler=ON,general_log=1,log_output='TABLE';
SET sql_log_off=ON;

# Repeat 1-2 times
CREATE OR REPLACE TABLE mysql.general_log (a INT);
SET SESSION sql_log_off=ON;
SET GLOBAL event_scheduler=ON,general_log=1,log_output='TABLE';
CREATE EVENT two_event ON SCHEDULE EVERY 20 SECOND ON COMPLETION NOT PRESERVE COMMENT 'two EVENT' DO SELECT 123;

CREATE EVENT four_event ON SCHEDULE EVERY 1 SECOND DO SELECT 1;
CREATE OR REPLACE TABLE mysql.slow_log (a INT);
SET GLOBAL event_scheduler=ON;
SET GLOBAL log_output='FILE,TABLE';
SET GLOBAL slow_query_log=ON;
SET GLOBAL long_query_time=FALSE;

INSTALL SONAME 'ha_rocksdb';
SET autocommit=0;
SET GLOBAL log_output='TABLE';
SET default_storage_engine=RocksDB;
CREATE OR REPLACE TABLE mysql.general_log (a INT);
SET GLOBAL general_log=1;
CREATE TABLE t1 (a INT) ENGINE RocksDB;
