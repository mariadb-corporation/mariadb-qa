CREATE TABLE t (a BLOB);
INSERT t VALUES ('abcdefghijklmnopqrstuvwz');
SELECT (SELECT MULTILINESTRING (d.a,d.a,d.a) FROM t) FROM t AS d GROUP BY d.a;
