# mysqld options required for replay:  --max_allowed_packet=33554432
CREATE TABLE t1 ENGINE=ARIA SELECT REPEAT(1,3355443) AS b ;
SET @@session.tmp_disk_table_size=1024;
SELECT STD(b) OVER(ROWS BETWEEN 2 FOLLOWING AND 1 FOLLOWING) as EXP FROM t1;
