USE test;
SET SQL_MODE='';
CREATE TABLE t (a INT PRIMARY KEY) ENGINE=MyISAM;
LOCK TABLE t WRITE;
CREATE TRIGGER t AFTER DELETE ON t FOR EACH ROW SET @log:= concat(@log, "(AFTER_DELETE: old=(id=", old.id, ", data=", old.data,"))");
SHOW TABLE STATUS LIKE 't';

CREATE TABLE t1 (a INT) ENGINE=MyISAM;
LOCK TABLE t1 WRITE;
ALTER TABLE t1 ADD b INT, LOCK=EXCLUSIVE, ORDER BY x;
SHOW TABLE STATUS;

CREATE TABLE t1 (a INT) ENGINE=MyISAM;
CREATE TRIGGER tr AFTER UPDATE ON t1 FOR EACH ROW SET @x=1;
CREATE TABLE t2 (b INT) ENGINE=MyISAM;
CREATE ALGORITHM=MERGE VIEW v2 AS SELECT * FROM t2;
LOCK TABLE v2 WRITE;
CREATE OR REPLACE TRIGGER tr BEFORE DELETE ON t2 FOR EACH ROW SET @x= 1;
SHOW TABLE STATUS;

SET SQL_MODE='';
SET SESSION storage_engine='MyISAM';
CREATE TABLE t (a INT,b INT,KEY(a));
INSERT INTO t VALUES (0,0);
INSERT DELAYED INTO t VALUES (mod (0,0),'test0');
CREATE TABLE t0 (a INT,b BLOB,UNIQUE (b)) IGNORE AS SELECT * FROM t;
CREATE TABLE t0 (a INT);
