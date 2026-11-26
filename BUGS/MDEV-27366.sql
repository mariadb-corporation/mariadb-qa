SET sql_mode='';
SET join_cache_level=3;
CREATE TABLE t (c BIGINT, d INT, KEY c(c), KEY d(d)) ENGINE=InnoDB;
INSERT INTO t VALUES (0,0),(1,2),(1,3),(2,0),(3,0),(4,6),(5,0);
SELECT * FROM t,t AS b WHERE t.c=0 AND t.d=b.c AND t.c=b.d;

# Effectively, this is:
SET optimizer_switch='rowid_filter=on'
SET sql_mode='';
SET join_cache_level=3;
CREATE TABLE t (c BIGINT, d INT, KEY c(c), KEY d(d)) ENGINE=InnoDB;
INSERT INTO t VALUES (0,0),(1,2),(1,3),(2,0),(3,0),(4,6),(5,0);
SELECT * FROM t,t AS b WHERE t.c=0 AND t.d=b.c AND t.c=b.d;

SET sql_mode='';
SET JOIN_cache_level=4;
CREATE TABLE t (a INT,b CHAR(1),d CHAR(1),c INT,INDEX (a),INDEX (b),UNIQUE INDEX (d));
REPLACE INTO t (a) VALUES (1),(1);
INSERT INTO t VALUES (0,0,9165,0);
INSERT INTO t VALUES (0,0,6210,0);
INSERT INTO t (b) VALUES (1);
INSERT INTO t VALUES (0,0,2125,0);
SELECT * FROM t NATURAL JOIN (SELECT * FROM t) a WHERE b>'';

CREATE TABLE t1 (b INT) ENGINE=InnoDB;
INSERT INTO t1 SELECT seq FROM seq_1_to_5;
CREATE TABLE t2 (pk INT PRIMARY KEY, b INT, c VARCHAR(10), KEY(b), KEY(c)) ENGINE=InnoDB;
INSERT INTO t2 SELECT seq, seq MOD 6, IF(seq MOD 4 = 0, 'z', 'a') FROM seq_1_to_20;
ANALYZE TABLE t2 PERSISTENT FOR ALL;
CREATE TABLE t3 (a INT) ENGINE=InnoDB;
INSERT INTO t3 VALUES (1),(2);
SELECT /*+ BNL(t2) */ COUNT(*) FROM t3, t1 LEFT JOIN t2 ON t2.b = t1.b AND t2.c <= 'x';

SET join_cache_level=3;
CREATE TABLE t1 (b INT) ENGINE=InnoDB;
INSERT INTO t1 SELECT seq FROM seq_1_to_5;
CREATE TABLE t2 (pk INT PRIMARY KEY, b INT, c VARCHAR(10), KEY(b), KEY(c)) ENGINE=InnoDB;
INSERT INTO t2 SELECT seq, seq MOD 6, IF(seq MOD 4 = 0, 'z', 'a') FROM seq_1_to_20;
ANALYZE TABLE t2 PERSISTENT FOR ALL;
CREATE TABLE t3 (a INT) ENGINE=InnoDB;
INSERT INTO t3 VALUES (1),(2);
SELECT COUNT(*) FROM t3, t1 LEFT JOIN t2 ON t2.b = t1.b AND t2.c <= 'x';
