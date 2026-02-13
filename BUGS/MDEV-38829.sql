# mysqld options required for replay: --log-bin
SET GLOBAL rpl_semi_sync_master_enabled=1;
SET SESSION gtid_seq_no=1;
SET GLOBAL rpl_semi_sync_master_wait_point=AFTER_SYNC;
SET GLOBAL gtid_strict_mode=1;
CREATE TABLE t (value INT);
