CREATE TABLE t (a INT,b INT,c INT,d INT,e INT,f INT GENERATED ALWAYS AS (a+b)VIRTUAL,g INT,h BLOB,i INT,UNIQUE KEY(d,h));
INSERT INTO t (a,b)VALUES(0,0), (0,0), (0,0), (0,0), (0,0);