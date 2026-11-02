CREATE TABLE t1 (c1 INT);
SET debug_dbug='+d';
CREATE TABLE t5 (c1 FLOAT);
select * from (t1 natural join t1 t3) natural right join t5;
