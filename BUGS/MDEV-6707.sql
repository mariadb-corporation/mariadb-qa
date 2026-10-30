CREATE TABLE t1 (f1 INT, f2 VARCHAR(1), KEY(f2,f1)) ENGINE=InnoDB;
INSERT INTO t1 VALUES (7,'v'),(0,'s'),(9,'l'),(4,'c');
SELECT MAX(f1), f2 FROM t1 WHERE f2 LIKE 'c%' AND f1 <> 9 GROUP BY f2;
#CLI: the row (4, c) twice; expected once
#ERR: - (no error)

CREATE TABLE t1 (a INT, b INT, KEY k1 (a, b));
INSERT INTO t1 VALUES (1,1),(1,5),(2,1),(2,5),(3,1),(3,5);
SELECT a, MAX(b) FROM t1 WHERE a = 2 AND b <> 4 GROUP BY a;
#CLI: the row (2, 5) twice; expected once
#ERR: - (no error)

CREATE TABLE t1 (a INT, b INT, KEY k1 (a, b));
INSERT INTO t1 VALUES (1,1),(1,5),(2,1),(2,5),(3,1),(3,5);
SELECT a, MAX(b) FROM t1 WHERE a IN (1, 2) AND b <> 4 GROUP BY a;
#CLI: the rows (1, 5) and (2, 5) twice each; expected once each
#ERR: - (no error)

CREATE TABLE t1 (a INT, b INT, KEY k1 (a, b));
INSERT INTO t1 VALUES (1,1),(1,5),(2,1),(2,5),(3,1),(3,5);
SELECT a, MIN(b) FROM t1 WHERE a = 2 AND (b < 3 OR b > 4) GROUP BY a;
#CLI: the row (2, 1) twice; expected once
#ERR: - (no error)
