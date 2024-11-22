CREATE TABLE t1 (a INT, b VARCHAR(1), KEY(b,a)) ENGINE=MyISAM;
INSERT INTO t1 VALUES (8,'o'),(5,'g'),(8,'f'),(3,'g'),(4,'j'),(NULL,'j'),(0,'i'),(124,'j'),(6,'l'),(5,'f');
SELECT MIN(a), b FROM t1 WHERE a IS NULL GROUP BY b;

CREATE TABLE t1 (a INT, b INT, c INT, d INT, KEY(d,a,c,b));
INSERT INTO t1 (a) VALUES (0),(0),(1),(0),(1),(1),(0),(0),(1),(1);
SELECT MIN(c), d, a FROM t1 GROUP BY d, a;

CREATE TABLE t (c INT,c2 INT,c3 INT,UNIQUE(c,c2,c3));
INSERT INTO t(c) VALUES (NULL),(0);
SELECT MIN(c2) FROM t GROUP BY c;  
