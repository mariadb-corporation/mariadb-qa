# mysqld options required for replay: --log-bin
CREATE TABLE t (a INT) ENGINE=Aria;
SET AUTOCOMMIT=0;
CREATE TABLE t1 (c1 INTEGER);
REPLACE INTO t VALUES ('1');
INSERT INTO t1  VALUES ('1');
ALTER TABLE t ADD c2 INT;
