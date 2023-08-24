# mysqld options required for replay:  --innodb-force-recovery=6
SET GLOBAL innodb_undo_log_truncate=1;

# mysqld options required for replay:  --innodb-read-only=1
SET GLOBAL innodb_max_purge_lag_wait=1;
