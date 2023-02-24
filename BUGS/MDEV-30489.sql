SET unique_checks=0,foreign_key_checks=0;
CREATE TABLE t1 (c INT) ENGINE=InnoDB;
CREATE TABLE t2 (c INT) ENGINE=InnoDB;
SELECT 0 INTO OUTFILE 'a';
SET autocommit=0;
INSERT INTO t2 VALUES (0);
LOAD DATA INFILE 'a' INTO TABLE t1;
SET autocommit=ON;
