SET GLOBAL gtid_slave_pos= '1-2-3,2-4-6';

# mysqld options required for replay:  --log_bin
SET GLOBAL wsrep_gtid_mode=ON;
SET GLOBAL gtid_slave_pos='1-1-1,2-2-2';
