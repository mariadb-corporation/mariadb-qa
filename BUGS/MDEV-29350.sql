SELECT 1 WHERE 1 IN (SELECT 1 FROM (SELECT (SELECT 1 FROM (SELECT 1) AS v1) IN (SELECT 1 FROM (SELECT 1) AS v2) AS v3 FROM (SELECT 1) AS v4) AS v5 GROUP BY v3);

CREATE TABLE t (c INT);
SELECT 1 FROM (SELECT 1 AS c) AS v12 WHERE c IN (SELECT 1 FROM (SELECT 1, (SELECT 1 FROM (SELECT 1) AS v1) IN (SELECT 1 FROM (WITH v2 AS (SELECT 1) SELECT 1 FROM (SELECT 1) AS v3 JOIN (SELECT 1) AS v5) AS v6) AS v7 FROM (SELECT 1) AS v8) AS v9 GROUP BY v7);