# mysqld options required for replay: --log_bin 
CREATE TEMPORARY TABLE t1 (a INT);
CREATE TABLE t2 (a INT);
DELETE FROM t2 LIMIT 0;
SET SESSION sql_log_bin=0;
CREATE TABLE t3 ENGINE=INNODB SELECT 1 ;

# mysqld options required for replay: --log_bin 
SET sql_log_bin=0;
CREATE TEMPORARY TABLE t (a INT);
LOAD DATA INFILE '' INTO TABLE t SET a=a;
CREATE TABLE t ENGINE=INNODB SELECT 1;
