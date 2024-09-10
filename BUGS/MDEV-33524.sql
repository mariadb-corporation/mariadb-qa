SET character_set_connection=ucs2;
CREATE TABLE t1 (d1 date not null, d2 date, gd text as (concat(d1,if(d1 <> d2, date_format(d2, 'to %y-%m-%d '), ''))) );
SELECT (SELECT 1 FROM foo) FROM t1;
INSERT INTO t1 (d1) VALUES ('2009-07-02');

SET GLOBAL mysql56_temporal_format=0;
SET character_set_connection=utf32;
CREATE OR REPLACE TABLE t (c1 INT);
SET sql_mode='ORACLE';
SET STATEMENT max_statement_time=1 FOR LOCK TABLES t WRITE;
CREATE OR REPLACE TABLE t (c1 DATE NOT NULL,c2 DATE NOT NULL,c3 TEXT AS (CONCAT (c1,IF(c1=c2,DATE_FORMAT(c2,'to % y-%m -% d '),0))));
CREATE OR REPLACE TABLE t (c1 INT) ;
