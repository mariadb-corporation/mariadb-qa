SET sql_mode='';
CREATE TABLE t (c INT,c2 INT);
INSERT INTO t VALUES ('-9223372036854775808',0),(0,0);
SELECT * FROM t WHERE c2=IF(@i:=c,EXTRACTVALUE ('<a><b>b1</b><b>b2</b></a>','//b[$@i]'),0);
