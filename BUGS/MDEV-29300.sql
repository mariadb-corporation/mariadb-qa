CREATE TABLE t(c INT);
SELECT (SELECT 0 GROUP BY c HAVING (SELECT 0 GROUP BY c)) FROM t GROUP BY c ;

CREATE TABLE t (c INT KEY,c1 BLOB,c2 TEXT) ENGINE=InnoDB;
SELECT (SELECT 0 GROUP BY c HAVING (SELECT 0 GROUP BY c)) FROM t GROUP BY c;
