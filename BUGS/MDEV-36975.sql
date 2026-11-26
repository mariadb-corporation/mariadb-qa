SET tmp_table_size=1024;
CREATE TABLE t1 (id_a INT PRIMARY KEY, id_b INT, id_c INT);
CREATE TABLE t2 (id_d INT PRIMARY KEY, id_c INT);
INSERT INTO t1 VALUES (1, 1234, 1);
INSERT INTO t2 VALUES (1, 1), (2, 1);
SELECT COUNT(DISTINCT t1.id_b) FROM t1 JOIN t2 ON t2.id_c = t1.id_c WHERE t1.id_a = 1;
#CLI: 2; expected 1
#ERR: - (no error)

CREATE TABLE t1 (a INT);
INSERT INTO t1 VALUES (1),(1),(2);
SET tmp_table_size=0;
SELECT COUNT(DISTINCT 5) FROM t1;
#CLI: 3; expected 1
#ERR: - (no error)

CREATE TABLE t1 (a INT);
INSERT INTO t1 VALUES (1),(1),(2);
SET tmp_table_size=0;
SELECT COUNT(DISTINCT 5, 'x') FROM t1;
#CLI: 3; expected 1
#ERR: - (no error)

CREATE TABLE t1 (a INT);
INSERT INTO t1 VALUES (1),(1),(2);
CREATE TABLE t2 (pk INT PRIMARY KEY, b INT);
INSERT INTO t2 VALUES (1,1234);
SET tmp_table_size=0;
SELECT COUNT(DISTINCT b) FROM t1, t2 WHERE pk = 1;
#CLI: 3; expected 1
#ERR: - (no error)

CREATE TABLE t1 (a INT);
INSERT INTO t1 VALUES (1),(1),(2);
SET tmp_table_size=0;
SELECT a, COUNT(DISTINCT 5) FROM t1 GROUP BY a WITH ROLLUP;
#CLI: 2, 1 and 3; expected 1, 1 and 1
#ERR: - (no error)
