SET @@optimizer_switch='semijoin=off,partial_match_table_scan=off';
SELECT x FROM (SELECT * FROM (SELECT 0 AS x) AS x) AS x WHERE x IN (SELECT * FROM (SELECT 0) AS x WHERE x IN (SELECT x IN (0) AS x)) GROUP BY x HAVING NOT x;
