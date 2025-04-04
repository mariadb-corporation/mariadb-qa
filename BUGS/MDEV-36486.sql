CREATE TABLE t (a CHAR,KEY(a));
INSERT INTO t (a) SELECT /*+ no_range_optimization (t a)*/0 FROM t;
