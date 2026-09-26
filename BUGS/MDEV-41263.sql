SET GLOBAL innodb_log_archive=OFF;
SET GLOBAL innodb_log_file_size=4*1024*1024;
CREATE TABLE t (a SERIAL, b CHAR(255) NOT NULL) ENGINE=InnoDB;
SET GLOBAL innodb_log_archive=ON;
SET GLOBAL innodb_log_file_size=8*1024*1024;
INSERT INTO t SELECT SEQ,REPEAT('x',255) FROM seq_1_to_65536;
DROP TABLE t;
