# mysqld options required for replay: --log_bin
CREATE OR REPLACE TABLE t (a INT);
SET GLOBAL rpl_semi_sync_master_wait_no_slave=0;
SET GLOBAL rpl_semi_sync_master_enabled=ON;
INSERT DELAYED INTO t VALUES ();
CREATE OR REPLACE TABLE t (a INT);
SET GLOBAL rpl_semi_sync_master_enabled=0;
