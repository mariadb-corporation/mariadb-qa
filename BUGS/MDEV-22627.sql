USE test;
SET SESSION innodb_compression_default=1;
SET GLOBAL innodb_compression_level=0;
CREATE TABLE t(c INT);

USE test;
SET GLOBAL innodb_compression_level=0;
SET SESSION innodb_compression_default=1;
CREATE TABLE t(c INT);

CREATE TABLE tp (a INT)ENGINE=InnoDB ROW_FORMAT=DYNAMIC page_compressed=1;
SET GLOBAL innodb_compression_level=-1;
ALTER TABLE tp ENGINE=InnoDB;

SET GLOBAL innodb_compression_default=1;
SET GLOBAL innodb_compression_level=0;
CREATE TABLE t (c INT);

SET GLOBAL innodb_compression_level=0;
CREATE TABLE t (a INT) ENGINE=InnoDB ROW_FORMAT=DYNAMIC page_compressed=1;
