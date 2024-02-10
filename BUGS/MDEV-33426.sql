# Requires standard m/s setup
CREATE TEMPORARY SEQUENCE SEQ0 ENGINE=Aria ROW_FORMAT=REDUNDANT;
RESET MASTER;
CREATE TABLE t (c INT AUTO_INCREMENT KEY);
INSERT INTO t SELECT * FROM t;
FLUSH LOGS;
INSERT INTO t VALUES (0);

# Requires standard m/s setup
# mysqld options possibly required for replay:  --maximum-transaction_prealloc_size=1M --maximum-sort_buffer_size=1M --maximum-tmp_table_size=1M
CREATE TEMPORARY TABLE IF NOT EXISTS t3(c BLOB,c2 POLYGON,c3 INT(1),KEY (c (1))) ENGINE=InnoDB;
CREATE TEMPORARY TABLE t2(c CHAR (1),c2 DOUBLE (1,1) UNSIGNED,c3 BLOB,KEY (c (1))) ENGINE=Aria;
DELETE a2,a3 FROM t2 AS a1 JOIN t2 AS a2 JOIN t3 AS a3;

# Requires standard m/s setup
CREATE TEMPORARY TABLE t (c INT) ENGINE=Aria;
INSERT INTO t SELECT * FROM t;

# Requires standard m/s setup
CREATE TEMPORARY TABLE t (a INT AUTO_INCREMENT KEY,b FLOAT,c BLOB (1),d CHAR(1),e TEXT) ENGINE=InnoDB;
CREATE TEMPORARY TABLE _dbt2_2 (a INT) ENGINE=Aria;
INSERT INTO t (ro_id,flag) SELECT * FROM seq_1_to_1;
SET SESSION sql_log_bin=0;
CREATE TABLE t2 (c TEXT CHARACTER SET 'latin1' COLLATE 'latin1_bin',c2 DECIMAL(1) UNSIGNED ZEROFILL,c3 DECIMAL(1) ZEROFILL) ENGINE=InnoDB;
SET sql_log_bin=1;
INSERT INTO t2 (c) VALUES (1),(1),(1),(1),(1),(1),(1),(1),(1),(1);

# Requires standard m/s setup
SET @@enforce_storage_engine=InnoDB;
CREATE TEMPORARY TABLE t_temporary_aria (c INT) ENGINE=Aria TRANSACTIONAL=0;
LOAD DATA INFILE''INTO TABLE t;
CREATE TABLE t (a INT) TRANSACTIONAL=0 ENGINE=SEQUENCE;
INSERT INTO t VALUES (0);
