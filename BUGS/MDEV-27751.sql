# mysqld options required for replay: --log-bin
SET unique_checks=0,foreign_key_checks=0,autocommit=0;
CREATE TABLE t (a INT KEY,b INT,FOREIGN KEY(b) REFERENCES ti1 (b));
INSERT INTO t VALUES (0,0),(0,0),(0,0);
INSERT INTO t VALUES (0,1);
INSERT INTO t SELECT * FROM t;
