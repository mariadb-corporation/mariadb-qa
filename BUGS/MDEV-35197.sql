# mysqld options required for replay: --log_bin
SET GLOBAL binlog_checksum=0;
INSTALL SONAME 'ha_spider';
RESET MASTER;

# ERR: safe_mutex: Found wrong usage of mutex 'LOCK_log' and 'LOCK_global_system_variables'
