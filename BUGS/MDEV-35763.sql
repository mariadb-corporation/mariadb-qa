# mysqld options required for replay:  --log_bin
SET GLOBAL wsrep_max_ws_rows = 2;
CREATE OR REPLACE TABLE t1 (c1 INT) ;
SET AUTOCOMMIT=0;
CREATE OR REPLACE TABLE t1 (a int) select seq from seq_1_to_10;
