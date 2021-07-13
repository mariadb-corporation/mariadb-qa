SET foreign_key_checks=0;
SET SESSION unique_checks=0;
SET GLOBAL innodb_checksum_algorithm=CRC32;
SET SESSION AUTOCOMMIT=OFF;
CREATE TABLE t (c INT) ENGINE=InnoDB;
INSERT INTO t (c) VALUES (0);
