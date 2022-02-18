SET unique_checks=0, foreign_key_checks=0, autocommit=0;
CREATE TABLE t (c INT PRIMARY KEY) ENGINE=InnoDB;
INSERT INTO t VALUES (0);
INSERT INTO t VALUES (0);
DROP TABLE IF EXISTS t;
CREATE TABLE t (d INT KEY) ENGINE=InnoDB;  # Changing table name 't' to 'e' in last two queries yields same result
INSERT INTO t SELECT s.SEQ FROM seq_1_to_128,seq_1_to_1024 s;
