set max_statement_time=0.0001;
CREATE OR REPLACE TABLE t1(c int primary key, c2 int);
CREATE TEMPORARY TABLE t2(c INT);
explain format=json update t2,(SELECT * FROM t1)t (a, c) set t2.c=t.c+10 where t2.c = t.c and t.a >= 3;
explain format=json update t2,(SELECT * FROM t1)t (a, c) set t2.c=t.c+10 where t2.c = t.c and t.a >= 3;
explain format=json update t2,(SELECT * FROM t1)t (a, c) set t2.c=t.c+10 where t2.c = t.c and t.a >= 3;
explain format=json update t2,(SELECT * FROM t1)t (a, c) set t2.c=t.c+10 where t2.c = t.c and t.a >= 3;
