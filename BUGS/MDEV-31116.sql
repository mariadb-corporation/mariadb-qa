SET sql_select_limit=1;
CREATE TABLE t (a BINARY (2),b BINARY (1),KEY(a));
INSERT INTO t (a) VALUES (''),(''),(''),(''),(''),(''),(''),(''),(''),(''),(''),(''),(''),('');
SELECT * FROM t WHERE a IN (SELECT a FROM t WHERE a >'') ORDER BY a;
