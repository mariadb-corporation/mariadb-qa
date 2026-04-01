# mysqld options required for replay:  --thread_handling=pool-of-threads
SELECT x IN (SELECT x IN (SELECT (SELECT 1 AS x FROM (SELECT * FROM (SELECT * FROM (SELECT 1 AS x) AS x WHERE x IN (1) GROUP BY x,x HAVING NOT x) AS x WHERE x IN (1)) AS x GROUP BY x IN (SELECT x IN (SELECT x IN (1) AS x)),x HAVING NOT x))) FROM (SELECT 1 AS x) AS x;
