CREATE TABLE t (c INT,d TIME(6));
INSERT INTO t VALUES (NULL,0.1),(NULL,0.1);
SELECT c FROM t WHERE c>ALL (SELECT d FROM t);

CREATE TABLE t (a INT,b INT);
CREATE TABLE t2 (a TIME(6));
INSERT INTO t VALUES (NULL,NULL);
INSERT INTO t2 VALUES (1+0.1);
INSERT INTO t2 VALUES (1+0.1);
SELECT a FROM t WHERE a>ALL (SELECT * FROM t2);