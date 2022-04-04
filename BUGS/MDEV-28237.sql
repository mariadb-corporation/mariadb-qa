# mysqld options required for replay: --log-bin 
CREATE TABLE t0 (c0 YEAR UNIQUE);
SET unique_checks=0,foreign_key_checks=0,autocommit=0;
INSERT INTO t0 VALUES (0),(0),(0),(0),(0),(0),(0);
DELETE FROM t0;

SET unique_checks=0,foreign_key_checks=0,autocommit=0;
CREATE TABLE t (a INT KEY,b INT UNIQUE);
INSERT INTO t SELECT SEQ,1 FROM seq_1_to_16;
DELETE FROM t ORDER BY a DESC;
