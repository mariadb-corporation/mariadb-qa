# mysqld options required for replay: --thread-stack=131072
SELECT mysql.a(),mysql.a();

WITH w AS (SELECT *) SELECT * FROM t WHERE c HAVING 1 WINDOW t AS () ORDER BY 1, 1=ANY(SELECT * LIMIT 1), t.t();
