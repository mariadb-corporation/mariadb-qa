CREATE TABLE t(c INT KEY) ENGINE=InnoDB;
INSERT INTO t VALUES(c IN (SELECT * FROM (SELECT (1 AND c=1)OR c=c FROM t ORDER BY c) AS v4 GROUP BY''HAVING c=c WINDOW v2 AS (ORDER BY c),v3 AS (v2)));