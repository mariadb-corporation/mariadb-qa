CREATE TABLE t (id INT,val INT) ENGINE=INNODB;
SET sql_select_limit=3;
SET optimizer_search_depth=1;
SET optimizer_join_limit_pref_ratio=1;
SELECT * FROM t AS ta LEFT JOIN (SELECT * FROM t AS tb1 JOIN t AS tb2 USING (id,val)) AS tb ON tb.id>ta.id ORDER BY ta.val;
