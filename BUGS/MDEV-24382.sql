CREATE TABLE t (c INT);
LOCK TABLES t READ LOCAL;
CREATE TEMPORARY TABLE t (a INT) SELECT 1 AS a;
DROP SEQUENCE t;
