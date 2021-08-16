SET sql_mode='NO_ZERO_DATE';
DROP TABLE IF EXISTS t1;
CREATE TABLE t1 (c1 DATE NOT NULL) ENGINE=CSV;
INSERT IGNORE INTO t1 VALUES();
SHOW WARNINGS;
SELECT * FROM t1;

SET sql_mode='no_zero_date';
CREATE TABLE t (a DATETIME NOT NULL) ENGINE=CSV;
CREATE TEMPORARY TABLE t (b INT) ENGINE=InnoDB;
DROP TABLE t;
INSERT INTO t VALUES (1);
SELECT * FROM t;

# Then check error log for:
# [ERROR] mysqld: Table 't' is marked as crashed and should be repaired
