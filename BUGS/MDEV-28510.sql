CREATE TABLE v1071 ( v1072 BOOLEAN NOT NULL ) ;
 ( ( SELECT v1072 FROM v1071 ORDER BY v1072 + v1072 , v1072 + v1072 ) ) ;
 UPDATE v1071 SET v1072 = 'x' WHERE v1072 = CASE WHEN v1072 * ( SELECT 0 FROM v1071 AS v1073 WHERE v1072 BETWEEN 70743860.000000 AND 22 WINDOW v1086 AS ( PARTITION BY v1072 ORDER BY ( SELECT DISTINCT 0 FROM ( SELECT v1072 FROM ( SELECT DISTINCT ( ( NOT ( 87472356.000000 AND v1072 = 0 ) ) = 49 AND v1072 = 30 ) % 0 , ( v1072 = 255 OR v1072 > 'x' ) FROM v1071 WHERE v1072 = 46 AND ( v1072 = 10 OR v1072 = 80 OR v1072 = -1 ) ) AS v1074 NATURAL JOIN v1071 WHERE ( v1072 = 127 OR v1072 = 16 ) NOT LIKE 'x' AND CASE v1072 * 8 = 0 WHEN 2147483647 THEN 'x' WHEN -128 THEN 'x' ELSE 8 END != 4 GROUP BY v1072 , 71777162.000000 / 91619124.000000 WINDOW v1087 AS ( PARTITION BY v1072 ORDER BY ( SELECT DISTINCT 76 FROM v1071 AS v1083 , v1071 AS v1084 , v1071 AS v1085 , v1071 ) DESC RANGE BETWEEN 66948404.000000 FOLLOWING AND 67858344.000000 FOLLOWING ) ) AS v1079 NATURAL JOIN v1071 AS v1080 , v1071 AS v1081 , v1071 AS v1082 JOIN v1071 ) DESC RANGE BETWEEN 26683913.000000 FOLLOWING AND 30593825.000000 FOLLOWING ) ) ^ v1072 THEN 'x' ELSE v1072 END / 16 ;
 INSERT INTO v1071 ( v1072 ) VALUES ( 86 ) , ( -32768 ) ;
 SELECT STDDEV_SAMP ( v1072 ) OVER v1088 , STDDEV_SAMP ( v1072 ) OVER v1088 FROM v1071 WINDOW v1088 AS ( PARTITION BY v1072 ORDER BY v1072 DESC ) ;

CREATE TABLE t1 ( a int );
insert into t1 values (1),(2),(3);
CREATE TABLE t2 ( a int ); 
insert into t2 values (1),(2),(3);
UPDATE t2 SET a = 5 WHERE (SELECT 1 FROM t1 WINDOW w1 AS (ORDER BY (SELECT 1 FROM (SELECT 1 FROM (SELECT a=10 FROM t1) dt1 NATURAL JOIN t1 GROUP BY a WINDOW w2 AS (order by a)) dt )));

CREATE TABLE t(v INT);
UPDATE t SET v=1 WHERE (SELECT 1 FROM (SELECT 1 AS v) AS v2 WHERE 22 WINDOW v3 AS (PARTITION BY v ORDER BY (SELECT 1 FROM (SELECT 1 FROM (SELECT 1 FROM (SELECT 1 AS v) AS v WHERE v=0 AND v=-1) AS v4 JOIN (SELECT 1 AS v) AS v GROUP BY v WINDOW v5 AS(PARTITION BY v)) AS v6)));

SELECT 1 FROM (SELECT 1 AS v) AS v2 WHERE 22 WINDOW v3 AS (PARTITION BY v ORDER BY (SELECT 1 FROM (SELECT 1 FROM (SELECT 1 FROM (SELECT 1 AS v) AS v WHERE v=0 AND v=-1) AS v4 JOIN (SELECT 1 AS v) AS v GROUP BY v WINDOW v5 AS(PARTITION BY v)) AS v6));

CREATE TABLE t0(c INT);
UPDATE t0 SET c= 0 WHERE c LIKE''AND c IN(SELECT * FROM t0 AS c NATURAL JOIN t0 WHERE c % 0=-0 WINDOW c AS(PARTITION BY c AND 0 BETWEEN(SELECT * FROM t0 GROUP BY c WINDOW c AS(PARTITION BY c)) AND 0));

CREATE TABLE t (c INT);
UPDATE t SET c=0 WHERE c LIKE '' AND c IN (SELECT * FROM t AS c NATURAL JOIN t WHERE c=1 WINDOW c AS (PARTITION BY c BETWEEN (SELECT * FROM t GROUP BY c WINDOW c AS (PARTITION BY c)) AND 1));

CREATE TABLE t (c INT);
SET SESSION optimizer_switch='semijoin=off';
UPDATE t SET c=0 WHERE c LIKE '' AND c IN (SELECT * FROM t AS c NATURAL JOIN t WHERE c=1 WINDOW c AS (PARTITION BY c BETWEEN (SELECT * FROM t GROUP BY c WINDOW c AS (PARTITION BY c)) AND 1));
