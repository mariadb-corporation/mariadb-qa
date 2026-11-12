CREATE TABLE t1 (g CHAR(4) NOT NULL, v INT NOT NULL, PRIMARY KEY (g, v), KEY idx_asc (g, v), KEY idx_desc (g, v DESC)) ENGINE=InnoDB;
INSERT INTO t1 VALUES ('A',1),('A',2),('A',3);
SELECT g, MAX(v) FROM t1 GROUP BY g;
#CLI: A 1; expected A 3
#ERR: - (no error)

CREATE TABLE t1 (a INT, b INT, c INT, KEY k1 (a, b DESC, c), KEY k4 (a, c, b)) ENGINE=InnoDB;
INSERT INTO t1 VALUES (11,33,1);
SELECT a, MIN(b), MAX(b) FROM t1 WHERE a = 11 AND b BETWEEN 28 AND 39 GROUP BY a;
#CLI: empty set; expected 11 33 33
#ERR: - (no error)
