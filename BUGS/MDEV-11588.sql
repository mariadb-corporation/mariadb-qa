SET sql_mode='ONLY_FULL_GROUP_BY';
CREATE TABLE t (a INT, b INT);
INSERT INTO t VALUES (1,2),(3,4);
SELECT COUNT(*),b FROM t WHERE b=2;
#CLI: refused; MySQL returns 1 row (b is fixed to one value by WHERE)
#ERR: 1140 Mixing of GROUP columns (MIN(),MAX(),COUNT(),...) with no GROUP columns is illegal if there is no GROUP BY clause
