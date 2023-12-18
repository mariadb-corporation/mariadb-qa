SET default_master_connection='my_slave';
CHANGE MASTER TO master_use_gtid=current_pos;
SET SESSION default_master_connection='@!*/"';
CHANGE MASTER TO master_use_gtid=current_pos;
FLUSH RELAY LOGS;
SHUTDOWN;
