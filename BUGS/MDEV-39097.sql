SET default_storage_engine=MyISAM;
CREATE TABLE t1 (t1c1 INT PRIMARY KEY, t1c4 INT NULL);
CREATE TABLE t2 (t2c1 INT PRIMARY KEY);
CREATE TABLE t3 (t3c1 INT PRIMARY KEY, t3c2 INT, t3c3 INT, t3c9 BIGINT, KEY (t3c3));
INSERT INTO t1 VALUES (1, NULL), (2, 1), (3, 1), (4, 1);
INSERT INTO t2 VALUES (1), (2), (3), (4);
INSERT INTO t3 VALUES (1, 2, 1,  214), (2, 1, 4, NULL), (3, 2, 2,   57), (4, 4, 4,  237), (6, 4, 3,  135), (7, 3, 1,  116);
UPDATE IGNORE t3 SET t3c9 = (SELECT VARIANCE(t1c4) FROM t1 WHERE t1c1 = t3c2) WHERE t3c3 IN (SELECT t2c1 AS k FROM t2) OR TRUE ORDER BY t3c1 DESC;
SELECT t3c1, t3c9 FROM t3 ORDER BY t3c1;
REPLACE INTO t3 VALUES (1, 2, 1,  214), (2, 1, 4, NULL), (3, 2, 2,   57), (4, 4, 4,  237), (6, 4, 3,  135), (7, 3, 1,  116);
UPDATE IGNORE t3 SET t3c9 = (SELECT VARIANCE(t1c4) FROM t1 WHERE t1c1 = t3c2) WHERE t3c3 IN (SELECT t2c1 AS k FROM t2) ORDER BY t3c1 DESC;
SELECT t3c1, t3c9 FROM t3 ORDER BY t3c1;
#CLI: the second SELECT gives t3c9 0 for t3c1 2; expected NULL, as the first SELECT gives
#ERR: - (no error)

CREATE TABLE t1 (a INT, KEY(a)) ENGINE=InnoDB;
INSERT INTO t1 VALUES (1);
CREATE TABLE t2 (a INT, b INT);
INSERT INTO t2 VALUES (1,10),(1,20);
UPDATE t2 SET b=b+1 WHERE a IN (SELECT a FROM t1) ORDER BY b;
SELECT * FROM t2;
#CLI: (1,21),(1,21); expected (1,11),(1,21)
#ERR: - (no error)

SET SESSION optimizer_switch='orderby_uses_equalities=off';
CREATE TABLE t1 (c1 INT, KEY k1 (c1)) ENGINE=InnoDB;
INSERT INTO t1 VALUES (0),(1),(5);
UPDATE t1 SET c1 = c1 + 1 WHERE c1 IN (SELECT c1 FROM t1) ORDER BY c1;
SELECT * FROM t1 ORDER BY c1;
#CLI: 6, 6, 6; expected 1, 2, 6
#ERR: - (no error)
