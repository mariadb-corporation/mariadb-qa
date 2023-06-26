SET sql_mode='',unique_checks=0,foreign_key_checks=0,GLOBAL innodb_default_row_format=0;
CREATE TABLE t (a CHAR CHARACTER SET utf8,FULLTEXT KEY(a)) ENGINE=InnoDB;
INSERT t SELECT * FROM seq_1_to_100000;
