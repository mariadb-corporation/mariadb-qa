# Use a standard m/s setup
SET sql_mode='',enforce_storage_engine=Aria; 
CREATE TEMPORARY TABLE t1 (c INT) ENGINE=Aria;
CREATE TABLE t2 (c INT) ENGINE=mrg_myisam;
INSERT INTO t2 VALUES (1);
