SET GLOBAL innodb_lru_scan_depth=86400;
SET debug_dbug='+d,page_intermittent_checksum_mismatch';
CREATE TEMPORARY TABLE t (i INT);
SELECT * FROM mysql.transaction_registry;
CREATE TEMPORARY TABLE 龡龡龡 (丌丌丌 INT) DEFAULT CHARSET=utf8;

SET GLOBAL innodb_lru_scan_depth=86400;
SET debug_dbug='+d,page_intermittent_checksum_mismatch';
CREATE TABLE t1 (a INT) ENGINE=InnoDB;
CREATE TABLE t2 (a INT) ENGINE=InnoDB;
CREATE TABLE t3 (a INT) ENGINE=InnoDB;
CREATE TABLE t4 (a INT) ENGINE=InnoDB;
CREATE TABLE t5 (a INT) ENGINE=InnoDB;
