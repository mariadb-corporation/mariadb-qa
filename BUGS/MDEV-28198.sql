SET GLOBAL log_output='TABLE';
SET SESSION sql_mode='no_auto_value_on_zero';
SET SESSION enforce_storage_engine=InnoDB;
ALTER TABLE mysql.general_log ENGINE=MyISAM;
SET GLOBAL general_log=1;
SELECT 1;
