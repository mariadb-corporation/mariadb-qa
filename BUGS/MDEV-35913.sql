CREATE TABLE t (a TEXT UNIQUE);
SELECT 1 FROM t WHERE ROW(a, (a,a)) IN ((1, (1,1)),(2, (2,1)));
