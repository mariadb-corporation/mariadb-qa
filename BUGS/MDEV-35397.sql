# mysqld options required for replay: --log-bin
SET GLOBAL rpl_semi_sync_master_enabled=1;
CREATE TABLE t (c INT);
FLUSH STATUS;
CREATE OR REPLACE TABLE t (c INT);
START TRANSACTION;
INSERT INTO t (c) VALUES (1);
SET GLOBAL rpl_semi_sync_master_enabled=0;
SET GLOBAL rpl_semi_sync_master_enabled=1;
CALL foo();
