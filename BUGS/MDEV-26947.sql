SET autocommit=0,foreign_key_checks=0,unique_checks=0;
CREATE TABLE t (c1 INT KEY,c2 INT,UNIQUE (c2)) ENGINE=InnoDB;
INSERT INTO t VALUES (1,0),(2,0);  # Should fail with ERROR 1062 (23000): Duplicate entry '0' for key 'c2'
CREATE TABLE t (c2 INT);
CHECK TABLE t;

SET autocommit=0,unique_checks=0,foreign_key_checks=0;
CREATE TABLE t (i INT UNIQUE);
INSERT INTO t VALUES (0),(0);
CHECK TABLE t;

CREATE TABLE t (c INT AUTO_INCREMENT KEY,c2 CHAR(1) NOT NULL,UNIQUE INDEX uc2 (c2));
INSERT INTO t VALUES(),();
DELETE FROM t;

CREATE TABLE t (c1 INT KEY,c2 INT UNIQUE) ENGINE=InnoDB;
BEGIN;
INSERT INTO t VALUES (1,0),(2,0);
