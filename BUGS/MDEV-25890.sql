# mysqld options required for replay: --log_bin
CREATE TABLE a (c INT) ENGINE=InnoDB;
SET GLOBAL expire_logs_days=11;
SET GLOBAL innodb_disallow_writes=ON;
SET GLOBAL binlog_checksum=CRC32;
