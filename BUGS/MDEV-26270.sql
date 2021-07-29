# mysqld options required for replay: --log_bin
SHOW BINLOG EVENTS FROM 120;
# Will produce 'Event invalid' in error log
