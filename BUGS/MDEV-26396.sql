WITH t (f) as (SELECT * FROM t1 WHERE b='') SELECT t1.b FROM t1,t1 WHERE t1.a=t2.c;

