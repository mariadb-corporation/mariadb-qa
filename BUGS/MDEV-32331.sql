SELECT ( WITH x ( x ) AS ( WITH x ( x ) AS ( SELECT json_array_append ( 'x' , ( 'x' % 'x' ) , 1 , 'x' , 1 ) ) SELECT CASE WHEN x * x THEN x END FROM x ) ( SELECT 1 FROM x WHERE x ) ) ;

SELECT 1 FROM (SELECT CASE WHEN x * x THEN x END as a FROM ( SELECT json_array_append ( 'x' , ( 'x' % 'x' ) , 1 , 'x' , 1 ) as x ) dt2 ) dt WHERE a;

SELECT 1 FROM (SELECT CASE WHEN x * x THEN x END as a FROM ( SELECT json_array_append ( 'x' , ( 'x' % 'x' ) , 1 , 'x' , 1 ) as x ) dt2 ) dt WHERE a;
 
SELECT 1 FROM (SELECT CASE WHEN x * x THEN x END as a FROM ( SELECT json_array_insert ( '[1]' , ( 'x' % 'x' ) , 1 , '$[0]' , 9 ) as x ) dt2 ) dt WHERE a;
 
SELECT 1 FROM (SELECT CASE WHEN x * x THEN x END as a FROM ( SELECT json_insert ( '1' , ( 'x' % 'x' ) , 1 , '$.a' , 2 ) as x ) dt2 ) dt WHERE a;
 
SELECT 1 FROM (SELECT CASE WHEN x * x THEN x END as a FROM ( SELECT json_remove ( '[1,2]' , ( 'x' % 'x' ) , '$[0]' ) as x ) dt2 ) dt WHERE a;
 
SELECT 1 FROM (SELECT CASE WHEN x * x THEN x END as a FROM ( SELECT json_replace ( '1' , ( 'x' % 'x' ) , 1 , '$.a' , 2 ) as x ) dt2 ) dt WHERE a;
 
SELECT 1 FROM (SELECT CASE WHEN x * x THEN x END as a FROM ( SELECT json_set ( '1' , ( 'x' % 'x' ) , 1 , '$.a' , 2 ) as x ) dt2 ) dt WHERE a;

SET NAMES utf8;
SELECT x FROM (SELECT 1 AS x UNION SELECT 2) AS t WHERE x IN (  SELECT JSON_REPLACE('1', UPPER(CAST(NULL AS CHAR)), 100));

SELECT ( WITH RECURSIVE x ( x ) AS (WITH RECURSIVE x ( x ) AS ( SELECT 1 UNION SELECT x + 1 FROM x ) SELECT json_array_append ( '[[], [], []]' , NOT ( NULL LIKE 'ABC%' ) , 315 ))  SELECT x FROM x WHERE  x > 10 AND  x < 1) ;

SELECT * FROM (SELECT JSON_REMOVE(46, DATE(NULL)) AS x EXCEPT SELECT 1) AS d WHERE NOT(NOT(x > 10)) AND (x < 1 OR x > 1);

SELECT 1 FROM (SELECT CASE WHEN x * x THEN x END AS a FROM (SELECT JSON_ARRAY_APPEND (0, (0%0),1,0,1) AS x) dt2) dt WHERE a;
