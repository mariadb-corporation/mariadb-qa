CREATE TABLE t(a VARCHAR(1) PRIMARY KEY,INDEX(a DESC)) ENGINE=InnoDB;
INSERT INTO t VALUES('2'),('1'),(''),('6'),('4'),('3');
SET GLOBAL innodb_limit_optimistic_insert_debug=3;
SET GLOBAL innodb_immediate_scrub_data_uncompressed=ON;
INSERT INTO t VALUES('8');
