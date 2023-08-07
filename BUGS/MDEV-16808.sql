set join_cache_level=3;
CREATE TABLE t1 (col_blob text)engine=innodb;
CREATE TABLE t2 (col_blob text COMPRESSED)engine=innodb;
SELECT * FROM t1 JOIN t2 USING ( col_blob );

SET join_cache_level= 3;
CREATE TABLE t1 (b BLOB);
INSERT INTO t1 VALUES (''),('');
CREATE TABLE t2 (pk INT PRIMARY KEY, b BLOB COMPRESSED);
INSERT INTO t2 VALUES (1,''),(2,'');
SELECT * FROM t1 JOIN t2 USING (b);

USE test;
CREATE TABLE t (c CHAR(0) NOT NULL);
CREATE TABLE u LIKE t;
SET join_cache_level=3;
SELECT t.c,u.c FROM t JOIN u ON t.c=u.c;

SET JOIN_cache_level=8;
CREATE TABLE t (a TEXT COMPRESSED) ENGINE=InnoDB;
INSERT INTO t VALUES (1),(2);
SELECT * FROM t A,t B WHERE A.a=B.a AND A.a IN (1);

CREATE TABLE t (a TEXT COMPRESSED,b TEXT) ENGINE=InnoDB;
CREATE TABLE t4 LIKE t;
SET SESSION JOIN_cache_level=3;
SELECT * FROM (SELECT * FROM t) as t NATURAL JOIN (SELECT * FROM t) AS t1;
