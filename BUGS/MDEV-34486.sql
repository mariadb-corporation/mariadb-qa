# mysqld options required for replay: --log_bin
RESET MASTER TO 2147483648;
SET GLOBAL binlog_space_limit=1;
