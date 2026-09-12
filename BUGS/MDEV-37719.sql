# mysqld options required for replay:  --log_bin=binlog --binlog_format=STATEMENT
CREATE GLOBAL TEMPORARY TABLE t1 (c INT);
CREATE TEMPORARY TABLE t2 (d INT);
CREATE OR REPLACE TEMPORARY TABLE t2 LIKE t1;
DROP TABLE t1, t2;  # Cleanup

# mysqld options required for replay:  --log_bin=binlog --binlog_format=STATEMENT
SET binlog_format='MIXED';
CREATE TEMPORARY TABLE t1 (x INT);
CREATE TEMPORARY TABLE t2 (y INT);
SET create_tmp_table_binlog_formats='MIXED';
CREATE OR REPLACE TEMPORARY TABLE t2 LIKE t1;
DROP TABLE t1, t2;  # Cleanup

# mysqld options required for replay:  --log_bin=binlog --binlog_format=STATEMENT
SET binlog_format='MIXED';
CREATE TEMPORARY TABLE t1 (x INT);
CREATE TEMPORARY TABLE t2 (y INT);
SET create_tmp_table_binlog_formats='MIXED';
PREPARE s FROM 'CREATE OR REPLACE TEMPORARY TABLE t2 LIKE t1';
EXECUTE s;
DEALLOCATE PREPARE s;
DROP TABLE t1, t2;  # Cleanup

# mysqld options required for replay:  --log_bin=binlog
CREATE TABLE t (c INT NOT NULL) ENGINE=InnoDB PARTITION BY LINEAR HASH(c) PARTITIONS 2;
INSERT INTO t VALUES (1);
SET max_session_mem_used=8192;
LOCK TABLES t READ NOWAIT;
CREATE TEMPORARY TABLE t (d INT) ENGINE=InnoDB;
RENAME TABLE t TO t2;
LOCK TABLES t WRITE;
CREATE OR REPLACE TABLE t LIKE t2;
DROP TABLE t;  # Cleanup
