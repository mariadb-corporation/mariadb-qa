CREATE TABLE t (c INT KEY);
INSERT INTO t VALUES ((c IN (SELECT * FROM (SELECT * FROM t GROUP BY c) AS d NATURAL JOIN (SELECT * FROM t) AS e)));

CREATE TABLE t (c INT KEY);
CREATE TABLE t0 SELECT 0;
INSERT INTO t VALUES ((c IN (SELECT * FROM (SELECT * FROM t GROUP BY c) AS d NATURAL JOIN (SELECT * FROM t) AS e)));
