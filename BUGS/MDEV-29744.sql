# mysqld options required for replay: --log-bin
SET GLOBAL max_binlog_size=98304;  # A valid and arbritary setting
START TRANSACTION WITH CONSISTENT SNAPSHOT;
# Then check error log for: safe_mutex: Found wrong usage of mutex 'LOCK_commit_ordered' and 'LOCK_global_system_variables'

# mysqld options required for replay: --log-bin
START TRANSACTION WITH CONSISTENT SNAPSHOT;
SET GLOBAL max_binlog_size=98304;  # A valid and arbritary setting
# Then check error log for: safe_mutex: Found wrong usage of mutex 'LOCK_global_system_variables' and 'LOCK_log'
