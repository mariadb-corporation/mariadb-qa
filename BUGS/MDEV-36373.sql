CREATE TABLE t (c INT) ENGINE=InnoDB;
SET SESSION tx_read_only=1;
ANALYZE TABLE t;
