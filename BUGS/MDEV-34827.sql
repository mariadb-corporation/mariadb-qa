# mysqld options required for replay: --log_bin
SET GLOBAL innodb_flush_log_at_timeout=300;
CREATE TABLE t (c INT) ENGINE=InnoDB;
SELECT SLEEP(2);
RESET MASTER;
