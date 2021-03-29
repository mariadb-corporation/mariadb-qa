START SLAVE SQL_THREAD;
SET @@debug_dbug="d,simulate_find_log_pos_error";
CHANGE MASTER TO IGNORE_DOMAIN_IDS=(1), MASTER_USE_GTID=SLAVE_POS;
FLUSH LOGS;
CHANGE MASTER TO master_use_gtid=current_pos;