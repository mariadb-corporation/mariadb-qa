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
