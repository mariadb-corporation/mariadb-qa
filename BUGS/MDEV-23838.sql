SET sql_mode='';
CREATE TABLE t (a TIME);
INSERT INTO t VALUES (0),(0);
SELECT MAX(ROUND (a,a)) FROM t GROUP BY a;
