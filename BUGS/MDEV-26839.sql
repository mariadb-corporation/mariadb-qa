CREATE TABLE t (a INT) ENGINE=Aria;
INSERT INTO t VALUES();
ALTER TABLE t ADD b GEOMETRY NOT NULL,ALGORITHM=copy;
ALTER TABLE t ADD INDEX i (b(1));

SET SQL_MODE='';
CREATE TABLE t (c INT,d BLOB (1) NOT NULL,INDEX (c,d(1))) ENGINE=Aria;
INSERT INTO t (c) VALUES (0);

SET sql_mode='';
CREATE TABLE t (c BLOB, PRIMARY KEY(c(1))) ENGINE=Aria;
INSERT INTO t VALUES (0);
UPDATE t SET c=NULL;

SET sql_mode='';
CREATE TABLE t (a INT,b BLOB NOT NULL,INDEX sk (b)) ROW_FORMAT=DYNAMIC ENGINE=Aria;
INSERT INTO t (a) VALUES (0);

SET sql_mode='';
CREATE TABLE t (c BLOB,c2 INT(1),c3 CHAR(1) BINARY,PRIMARY KEY(c (1))) ENGINE=Aria;
INSERT INTO t (c2) VALUES (1);

SET sql_mode='';
CREATE TABLE t1 (a INT,b BLOB NOT NULL,INDEX sk (b)) ROW_FORMAT=compact ENGINE=Aria;
INSERT INTO t1 SELECT @p,@p FROM seq_0_to_0;

CREATE TABLE t AS SELECT 0 AS c;
ALTER TABLE t ADD b GEOMETRY NOT NULL;
SELECT * FROM t UNION SELECT * FROM t;
