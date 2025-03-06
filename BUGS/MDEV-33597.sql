SET sql_mode='';
SET enforce_storage_engine=InnoDB;
SET GLOBAL tx_read_only=1;
SET GLOBAL general_log='ON';
ALTER TABLE mysql.general_log ENGINE=MyISAM;
SHOW WARNINGS;
SET GLOBAL init_slave='SELECT 1';
SET GLOBAL log_output="FILE,TABLE";
CHANGE MASTER TO master_host='127.0.0.1';
START SLAVE SQL_THREAD;

SET sql_mode='', enforce_storage_engine=InnoDB;
ALTER TABLE mysql.general_log ENGINE=MyISAM;
SET GLOBAL tx_read_only=1, general_log='ON', log_output="TABLE";
SET @a= 1;

SET GLOBAL log_output=6;
CREATE TABLE t (a INT);
CREATE OR REPLACE TABLE mysql.general_log (a INT);
CREATE TABLE sbtest (c1 INT);
SET GLOBAL general_log=ON;
SET tx_read_only=1;
SET unique_checks=0,foreign_key_checks=0,autocommit=0;
SELECT * FROM sbtest;
SET SESSION tx_read_only=0;
INSERT t SELECT * FROM seq_1_to_1;
