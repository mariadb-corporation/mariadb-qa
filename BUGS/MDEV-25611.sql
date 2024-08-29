# mysqld options required: --log-bin
SET GLOBAL innoDB_flush_log_at_timeout=600;
CREATE TEMPORARY TABLE t (c INT) ENGINE=InnoDB;
RESET MASTER;  # Always "hangs" here

# mysqld options required: --log-bin
SET GLOBAL innoDB_flush_log_at_timeout=600;
CREATE TABLE t (c INT) ENGINE=InnoDB;
RESET MASTER;  # Occassionally "hangs" here, though often completes immediately and then...
RESET MASTER;  # ...occassionally "hangs" here, or...
RESET MASTER;  # ...here
# If it still does not hang, wait one second, and retry the command: it will hang
