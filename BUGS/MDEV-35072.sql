SET SESSION sql_select_limit=1;
SET optimizer_join_limit_pref_ratio=1;
CREATE TABLE t1 (c1 INT, INDEX(c1));
INSERT INTO t1  VALUES (1),(2);
SELECT * FROM t1  ORDER BY c1;
