SET GLOBAL mysql56_temporal_format=0;
SET explicit_defaults_for_timestamp=0;
CREATE TABLE t (b TIMESTAMP,a INT AS (1 IN (DAYOFMONTH (b between''AND current_user)=b)));
SELECT * FROM t,t2;
SELECT * FROM t;
