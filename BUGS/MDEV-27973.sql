SET SESSION innodb_compression_default=1;
CREATE TEMPORARY TABLE t (c INT,c2 INT,c3 INT,KEY(c)) ENGINE=InnoDB;
SET GLOBAL innodb_compression_level=0;
TRUNCATE t;
