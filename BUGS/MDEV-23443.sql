CREATE TABLE t (c TEXT);
INSERT INTO t VALUES (0.1111111e0),(1),(1);
SELECT * FROM t q1 except ALL SELECT * FROM (SELECT * FROM t except ALL SELECT * FROM t) q2;