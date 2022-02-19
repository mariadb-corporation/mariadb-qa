SET unique_checks=0, foreign_key_checks=0, autocommit=0;
CREATE TABLE t (c INT PRIMARY KEY) ENGINE=InnoDB;
INSERT INTO t VALUES (0);
INSERT INTO t VALUES (0);
DROP TABLE IF EXISTS t;
CREATE TABLE t (d INT KEY) ENGINE=InnoDB;  # Changing table name 't' to 'e' in last two queries yields same result
INSERT INTO t SELECT s.SEQ FROM seq_1_to_128,seq_1_to_1024 s;

SET sql_mode='', unique_checks=0, foreign_key_checks=0, autocommit=0;
CREATE TABLE t (PRIMARY KEY(a)) (SELECT 1 AS a) UNION ALL (SELECT 1 AS a);
CREATE TABLE t (c INT) ENGINE=InnoDB;
DROP TABLE IF EXISTS t;
CREATE TABLE t2 (c INT) ENGINE=InnoDB;
CREATE TABLE t (pk INT PRIMARY KEY);
INSERT INTO t SELECT b.SEQ FROM seq_1_to_128,seq_1_to_1024 b;

SET unique_checks=0,foreign_key_checks=0,autocommit=0;
CREATE TABLE t (c INT) PARTITION BY KEY(c);
INSERT INTO t VALUES (1),(1);
SET SESSION foreign_key_checks=1;
SHOW CREATE TABLE t;
CREATE TABLE t (d INT);
