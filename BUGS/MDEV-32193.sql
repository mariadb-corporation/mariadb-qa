SET GLOBAL gtid_slave_pos= '1-2-3,2-4-6';

# mysqld options required for replay:  --log_bin
SET GLOBAL wsrep_gtid_mode=ON;
SET GLOBAL gtid_slave_pos='1-1-1,2-2-2';

# mysqld options required for replay:  --log_bin
SET GLOBAL wsrep_max_ws_rows = 2;
CREATE OR REPLACE TABLE t1 (c1 INT) ;
SET AUTOCOMMIT=0;
CREATE OR REPLACE TABLE t1 (a int) engine=InnoDB select seq from seq_1_to_10;
