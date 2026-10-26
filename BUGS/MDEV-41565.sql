SET GLOBAL innodb_log_archive=ON;
SET GLOBAL debug_dbug='+d,ib_log_checkpoint_avoid';
CREATE TABLE t(a INT) ENGINE=InnoDB;
SET GLOBAL innodb_log_archive=OFF;
