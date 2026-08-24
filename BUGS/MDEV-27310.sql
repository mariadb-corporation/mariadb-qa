SET sql_mode='ONLY_FULL_GROUP_BY';
CREATE TABLE t (a INT, b INT, c INT);
INSERT INTO t VALUES (1,2,3),(4,5,6);
SELECT a, MIN(b) FROM t GROUP BY a ORDER BY c, a;
#CLI: returns 2 rows; expected ERROR 1055 (c is not in GROUP BY)
#ERR: - (no error)

SET sql_mode='ONLY_FULL_GROUP_BY';
CREATE TABLE t (a INT, b INT);
INSERT INTO t VALUES (1,2),(3,4);
SELECT SUM(a) FROM t ORDER BY b;
#CLI: refused; MySQL returns 1 row
#ERR: 1140 Mixing of GROUP columns (MIN(),MAX(),COUNT(),...) with no GROUP columns is illegal if there is no GROUP BY clause
