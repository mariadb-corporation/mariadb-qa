CREATE TABLE t ( c INT ) ENGINE=MYISAM ;
SELECT *  FROM t WHERE c = 1 AND ( 3 = 0 OR  (SELECT c = 1 OR (SELECT 3 WHERE c = c ) = 3));