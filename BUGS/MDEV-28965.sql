CREATE TABLE t1 ( a int);
INSERT into t1 values (1),(2),(3);
UPDATE t1 SET a = 1 WHERE a = ( SELECT * FROM (SELECT a FROM t1) dt ) ;
