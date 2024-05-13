# mysqld options required for replay: --log-bin 
XA START 'a';
SET GLOBAL rpl_semi_sync_master_enabled=1;
INSERT INTO mysql.columns_priv SET HOST='a';
SET GLOBAL rpl_semi_sync_master_enabled=0;
SET GLOBAL rpl_semi_sync_master_enabled=1;
SELECT foo(bar);
