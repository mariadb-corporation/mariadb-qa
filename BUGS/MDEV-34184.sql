CREATE VIEW v AS SELECT 1;
EXPLAIN SELECT ROUND ((SELECT 1 FROM v)) FROM v GROUP BY ROUND ((SELECT 1 FROM v));