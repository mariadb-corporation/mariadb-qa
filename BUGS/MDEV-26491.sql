# mysqld options required for replay:  --innodb-fatal-semaphore-wait-threshold=2
CREATE TABLE t (c INT) ENGINE=InnoDB;
SET GLOBAL innodb_disallow_writes=ON;
DROP TABLE t;
