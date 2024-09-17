# mysqld options required for replay: --log-bin 
XA START 'a';
SET GLOBAL rpl_semi_sync_master_enabled=1;
INSERT INTO mysql.columns_priv SET HOST='a';
SET GLOBAL rpl_semi_sync_master_enabled=0;
SET GLOBAL rpl_semi_sync_master_enabled=1;
SELECT foo(bar);

# mysqld options required for replay: --log-bin 
CREATE TABLE t (c1 INT) ENGINE=Aria;
XA START 'a';
SET GLOBAL rpl_semi_sync_master_enabled=1;
INSERT INTO t SELECT 1;
SET GLOBAL rpl_semi_sync_master_enabled=0;
XA END 'a';
LOAD INDEX INTO CACHE t KEY(PRIMARY,inx_b);
SET GLOBAL rpl_semi_sync_master_enabled=ON;

# mysqld options required for replay: --log-bin 
SET GLOBAL gtid_strict_mode=1;
CREATE TEMPORARY TABLE t (i INT);
SET GLOBAL rpl_semi_sync_master_wait_point=AFTER_SYNC;
SET SESSION gtid_domain_id=2;
SET gtid_seq_no=1;
SET gtid_domain_id=0;
SET GLOBAL rpl_semi_sync_master_enabled=1;

# mysqld options required for replay: --log-bin 
SET SESSION gtid_domain_id=1;
ANALYZE TABLE t PERSISTENT FOR ALL;
SET GLOBAL rpl_semi_sync_master_wait_point=AFTER_SYNC;
SET GLOBAL gtid_strict_mode=ON;
CREATE TABLE t (c INT);
DROP TABLE t;
CREATE TABLE t (c INT);
SET gtid_domain_id=11;
SET gtid_seq_no=4;
SET GLOBAL rpl_semi_sync_master_enabled=1;
SET gtid_domain_id=1;
FLUSH TABLES;
