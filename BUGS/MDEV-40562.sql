CREATE TABLE en (id INT PRIMARY KEY, e ENUM('b','a','C','ab'));
INSERT INTO en VALUES (1,'b'),(2,'a'),(3,'C'),(4,'ab'),(5,'a'),(6,'b');
SELECT 'no index' AS state, MIN(e) AS min_e, MAX(e) AS max_e FROM en;
CREATE INDEX ix_e ON en (e);
SELECT 'index added' AS state, MIN(e) AS min_e, MAX(e) AS max_e FROM en;
SELECT 'IGNORE INDEX' AS state, MIN(e) AS min_e, MAX(e) AS max_e FROM en IGNORE INDEX (ix_e);
SELECT (SELECT MAX(e) FROM en) AS agg_max, (SELECT DISTINCT MAX(e) OVER () FROM en LIMIT 1) AS window_max, (SELECT MIN(e) FROM en) AS agg_min, (SELECT DISTINCT MIN(e) OVER () FROM en LIMIT 1) AS window_min;
#CLI: with the index, b and ab; expected a and C, as without it. agg_max ab and window_max C
#ERR: - (no error)

CREATE TABLE t0 (c0 ENUM('b','a','C','ab') PRIMARY KEY);
INSERT INTO t0 VALUES ('b'),('a'),('C'),('ab');
SELECT MIN(c0) AS min_c0, MAX(c0) AS max_c0 FROM t0;
#CLI: b and ab; expected a and C (as with IGNORE INDEX (PRIMARY))
#ERR: - (no error)

CREATE TABLE t1 (a INT, e ENUM('b','a','C','ab'), KEY (a, e));
INSERT INTO t1 VALUES (1,'b'),(1,'a'),(1,'C'),(1,'ab'),(2,'b'),(2,'a');
SELECT a, MAX(e) FROM t1 GROUP BY a;
SELECT a, MIN(e) FROM t1 GROUP BY a;
SELECT MAX(e) FROM t1 WHERE a = 1;
#CLI: MAX(e) ab and a, expected C and b; MIN(e) b and b, expected a and a; MAX(e) WHERE a = 1 ab, expected C (as with IGNORE INDEX (a))
#ERR: - (no error)

CREATE TABLE t1 (e ENUM('b','a','C','ab') PRIMARY KEY);
INSERT INTO t1 VALUES ('b'),('a'),('C'),('ab');
SELECT MAX(e) FROM t1 WHERE e < 'b';
#CLI: NULL; expected ab (as with IGNORE INDEX (PRIMARY))
#ERR: - (no error)

CREATE TABLE t1 (s SET('y','x','z'), KEY (s));
INSERT INTO t1 VALUES ('y'),('x'),('z'),('x,y');
SELECT MIN(s), MAX(s) FROM t1;
#CLI: y and z; expected x and z (as with IGNORE INDEX (s))
#ERR: - (no error)
