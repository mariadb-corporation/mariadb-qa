CREATE TABLE t1 (DATA CHAR(4),UNIQUE (DATA) USING HASH) ENGINE=InnoDB WITH SYSTEM VERSIONING;
INSERT INTO t1 VALUES (0);
DELETE FROM t1;
DELETE HISTORY FROM t1;

CREATE TABLE t1 (DATA CHAR(4),UNIQUE (DATA) USING HASH) ENGINE=MyISAM WITH SYSTEM VERSIONING;
INSERT INTO t1 VALUES (0);
DELETE FROM t1;
DELETE HISTORY FROM t1;

CREATE TABLE t (c INT,UNIQUE (c) USING HASH) ENGINE=InnoDB WITH SYSTEM VERSIONING;
INSERT INTO t VALUES (0);
DELETE FROM t;
DELETE HISTORY FROM t;
