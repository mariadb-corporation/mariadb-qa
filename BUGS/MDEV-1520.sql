CREATE TEMPORARY TABLE t (d BLOB, UNIQUE (d)) ENGINE=Spider;
SHOW CREATE TABLE t;
SELECT * FROM t;
FLUSH TABLE t FOR EXPORT;
INSERT INTO t VALUES (ST_GEOMFROMTEXT ('POINT(1 1)'));
