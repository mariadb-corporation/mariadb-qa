CREATE VIEW t AS SELECT 1 AS a;
SELECT ROUND ((SELECT 1 FROM t)) FROM t GROUP BY ROUND ((SELECT 1 FROM t));