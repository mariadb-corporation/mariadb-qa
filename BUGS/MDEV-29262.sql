CREATE TABLE c(c INT);
UPDATE c SET c=0 ORDER BY(SELECT c,c BETWEEN(SELECT c AS c GROUP BY c WINDOW c AS(PARTITION BY c AND 0 BETWEEN(SELECT c FROM c GROUP BY'',c,c HAVING c IS NULL WINDOW c AS(PARTITION BY c)) AND 0)) AND 0);

CREATE TABLE x (x INT);
SELECT (x=(SELECT x FROM x WHERE (x,x) IN (SELECT 0,0)) IN (0,0)) AS x FROM x WINDOW x AS (PARTITION BY x ORDER BY (SELECT 0 FROM (SELECT x FROM x WHERE (x,x) NOT IN (SELECT (''=(x IN (SELECT x FROM x WHERE x=CASE WHEN x ^ (SELECT 0 FROM x AS x WHERE x GROUP BY (TRUE,x) NOT IN (SELECT x, (SELECT x FROM (SELECT x, (NOT ((+ 1 AND (x NOT IN (NOT (NOT (x=0))) AND (x,x) NOT IN (SELECT 0,0))=0) *'')) FROM x) AS x NATURAL JOIN x) AS x FROM x),x WINDOW x AS (PARTITION BY x ORDER BY (0))) ^ x THEN''END / 0))) FROM x) LIMIT 0) AS x));
