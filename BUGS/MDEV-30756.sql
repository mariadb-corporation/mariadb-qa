CREATE TABLE v0 ( v1 INT , v2 CHAR UNIQUE UNIQUE NOT NULL CHECK ( v2 NOT IN ( v1 > 59 OR v1 > 67 AND FALSE NOT LIKE 'x' , 'x' ) ) ) ;
CREATE VIEW v3 AS SELECT DISTINCT 41503055.000000 FROM v0 WHERE v2 ;
UPDATE v0 SET v2 = v2 * 0 WHERE v2 IN ( SELECT DISTINCT v2 FROM v0 WHERE EXISTS ( SELECT v1 FROM v3 WHERE v1 = v2 + -1 GROUP BY ( SELECT v2 FROM v0 AS v4 WHERE v2 = 'x' OR v1 = 'x' OR v1 = 'x' GROUP BY v2 HAVING v1 < 'x' ) BETWEEN 44 AND 0 HAVING 2147483647 ) ) ORDER BY v1 IS NULL ;
DROP TABLE v3 ;
INSERT INTO v0 VALUES ( 15 ) ;

CREATE TABLE t1 (id int);
SELECT * FROM t1 k WHERE 1 IN (SELECT  1 FROM t1 WHERE EXISTS (SELECT id  FROM (SELECT 1 FROM t1) d GROUP BY  (SELECT 1 FROM t1 dt HAVING id) BETWEEN 0 AND 10 HAVING 1)) ;

SELECT (WITH x AS (SELECT ('POINT(180 90)') AS x) SELECT x FROM x WHERE x IN (SELECT 0.200000 FROM x WHERE (SELECT x FROM (SELECT 2 UNION SELECT 3) AS x GROUP BY (SELECT x))));

create table t1 as SELECT 5 x;
SELECT 5 FROM t1 WHERE 4 IN (SELECT (SELECT x FROM (SELECT 2 UNION SELECT 3)dt GROUP BY  (SELECT x) ) FROM t1);

create table t1 (a int);
insert into t1 values (3), (7), (1);
create table t2 (b int);
insert into t2 values (1), (2);
create table t3 (c int);
insert into t3  values (1), (3);
create table t4 (d int);
insert into t4 values (1);
select c from t3 where c in (select (select a from t2 group by (select a from t4)) from t1);

SELECT(WITH x AS(SELECT (0)AS x) SELECT x FROM x WHERE x IN (SELECT 0 FROM x WHERE (SELECT x FROM (SELECT 0 UNION SELECT 0) AS x GROUP BY (SELECT x))));
