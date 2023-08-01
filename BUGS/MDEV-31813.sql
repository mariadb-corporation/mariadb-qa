# mysqld options required for replay:  --innodb-force-recovery=6
SET GLOBAL innodb_undo_log_truncate=1;
