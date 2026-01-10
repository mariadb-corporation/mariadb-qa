# mysqld options required for replay:  --log-bin --binlog_format=STATEMENT
# Requires standard m/s replication setup
CREATE TEMPORARY TABLE t (y INT) ENGINE=InnoDB;
CREATE TABLE t (x INT) ENGINE=InnoDB AS SELECT 0 'a';
ALTER TABLE t DISCARD TABLESPACE;
DROP TABLE t;
TRUNCATE TABLE t;
DROP TABLE t;

# mysqld options required for replay:  --log-bin --binlog_format=STATEMENT
CREATE TEMPORARY TABLE t (c INT);
SET SESSION binlog_format='ROW';
TRUNCATE t;
