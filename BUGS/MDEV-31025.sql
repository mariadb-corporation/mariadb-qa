SET GLOBAL innodb_default_row_format=0;
SET sql_mode='',unique_checks=0,foreign_key_checks=0;
CREATE TABLE t (pk INT,c CHAR(255),c2 CHAR(255),c3 CHAR(255),c4 CHAR(255),c5 CHAR(255),c6 CHAR(255),c7 CHAR(255),c8 CHAR(255),PRIMARY KEY(pk)) ENGINE=InnoDB CHARACTER SET utf32;
INSERT INTO t(c) VALUES (10);
