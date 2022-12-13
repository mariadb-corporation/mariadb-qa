SET NAMES utf8,collation_connection=utf16le_general_ci;
SET default_master_connection='MASTER1';
CHANGE MASTER TO master_use_gtid=slave_pos;
SET default_master_connection='MASTER 2';
CHANGE MASTER TO master_use_gtid=current_pos;
FLUSH LOGS;
FLUSH LOGS;
