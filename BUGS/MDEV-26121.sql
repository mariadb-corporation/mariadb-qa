SET foreign_key_checks=0;
SET SESSION unique_checks=0;
SET GLOBAL innodb_checksum_algorithm=CRC32;
SET SESSION AUTOCOMMIT=OFF;
CREATE TABLE t (c INT) ENGINE=InnoDB;
INSERT INTO t (c) VALUES (0);

SET sql_mode= '';
SET unique_checks=0;
SET GLOBAL innodb_checksum_algorithm=strict_CRC32;
CREATE TABLE t (c DOUBLE KEY,c2 BINARY (1),c3 TIMESTAMP);
SET foreign_key_checks=0;
INSERT INTO t VALUES ('','',''),('','','');
