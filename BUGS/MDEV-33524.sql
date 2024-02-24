SET character_set_connection=ucs2;
CREATE TABLE t1 (d1 date not null, d2 date, gd text as (concat(d1,if(d1 <> d2, date_format(d2, 'to %y-%m-%d '), ''))) );
SELECT (SELECT 1 FROM foo) FROM t1;
INSERT INTO t1 (d1) VALUES ('2009-07-02');
