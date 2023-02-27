SET GLOBAL log_output='TABLE';
SET SESSION sql_mode='no_auto_value_on_zero';
SET SESSION enforce_storage_engine=InnoDB;
ALTER TABLE mysql.general_log ENGINE=MyISAM;
SET GLOBAL general_log=1;
SELECT 1;

SET GLOBAL wsrep_forced_binlog_format=STATEMENT;
CREATE TABLE t (a INT UNIQUE) REPLACE SELECT 1 AS a,2 AS b UNION SELECT 1 AS a,3 AS c;
