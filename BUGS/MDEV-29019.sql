SET sql_select_limit=2;
CREATE TABLE t (a INT);
SET collation_connection=utf32_unicode_ci;
INSERT INTO t VALUES (0);
SELECT * FROM t ORDER BY (OCT(a));
