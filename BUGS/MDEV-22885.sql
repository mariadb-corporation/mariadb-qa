CREATE TABLE t1 (s TIMESTAMP);
INSERT INTO t1 VALUES ('2033-06-06'),('2015-09-10');
SELECT NULLIF( s, NULL ) AS f FROM t1 GROUP BY s WITH ROLLUP;

USE test;
SET SQL_MODE='';
CREATE TABLE t (a TIMESTAMP, b DATETIME, c TIME) ENGINE=InnoDB;
INSERT INTO t VALUES (NULL,NULL,NULL);
SELECT CASE a WHEN a THEN a END FROM t GROUP BY a WITH ROLLUP;