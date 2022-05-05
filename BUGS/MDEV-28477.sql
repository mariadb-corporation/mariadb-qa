CREATE TABLE t (a DATE);
INSERT INTO t VALUES();
SELECT ROW(a, (a,a)) IN ((1, (1,1)),(2, (2,2))) FROM t;

