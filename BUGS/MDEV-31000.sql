SET GLOBAL innodb_file_per_table=0;
CREATE TABLE t (c INT) ENGINE=INNODB;
SET GLOBAL innodb_file_per_table=1;
ALTER TABLE t page_compressed=1;
