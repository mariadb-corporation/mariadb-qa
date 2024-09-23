SET SQL_MODE='';
CREATE TABLE t1 (a int,b varchar(100) GENERATED ALWAYS AS (a));
insert INTO t1 select seq,0 from seq_1_to_71424;
SELECT DISTINCT a,sum(b) FROM t1 GROUP BY a,b WITH ROLLUP; 
