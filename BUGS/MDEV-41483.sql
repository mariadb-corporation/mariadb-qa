CREATE TABLE t1 (a INT, b INT, c INT, KEY k1 (a, b DESC, c));
INSERT INTO t1 VALUES (7,NULL,1),(8,NULL,2),(9,NULL,3),(7,5,1),(8,5,2),(9,5,3);
SELECT COUNT(*) FROM t1 FORCE INDEX (k1) WHERE a BETWEEN 7 AND 9 AND b = 5 AND c <= 4;
#CLI: 1; expected 3
#ERR: - (no error)

CREATE TABLE t1 (a INT, b INT, c INT, KEY k1 (a DESC, b, c DESC));
INSERT INTO t1 VALUES (7,NULL,9),(8,NULL,8),(9,NULL,7),(7,5,9),(8,5,8),(9,5,7);
SELECT COUNT(*) FROM t1 FORCE INDEX (k1) WHERE a BETWEEN 7 AND 9 AND b = 5 AND c >= 6;
#CLI: 2; expected 3
#ERR: - (no error)

CREATE TABLE t (a INT, b INT, c INT, KEY k (a DESC, c DESC, b));
INSERT INTO t VALUES (9, 1, 1), (5, 5, 2);
SELECT COUNT(*) FROM t WHERE c >= 2 AND b >= 2 AND a >= 5;
#CLI: 0; expected 1 (as with IGNORE INDEX (k))
#ERR: - (no error)

CREATE TABLE t (a INT, b INT, c INT, KEY k (a, b, c DESC));
INSERT INTO t VALUES (5, 2, 5);
SELECT COUNT(*) FROM t WHERE a >= 5 AND b >= 2 AND c >= 2;
#CLI: 0; expected 1 (as with IGNORE INDEX (k))
#ERR: - (no error)
