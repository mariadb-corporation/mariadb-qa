CREATE TABLE t (t INT);
INSERT INTO t VALUES (0),(t IN (SELECT t IN (SELECT 1 FROM (SELECT 1 AS t) AS t WHERE t IN (SELECT t HAVING NOT t))));

CREATE VIEW t AS SELECT 1 AS a;
SELECT a FROM t WHERE'' IN (SELECT''LIKE a HAVING a LIKE a);
