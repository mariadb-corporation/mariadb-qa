CREATE TABLE t0 (a UUID,b INT) ENGINE=INNODB;
SELECT * FROM t0 WHERE (t0.a,t0.b) IN ( ('',0),('',0));

CREATE TABLE t (a CHAR,b INET6) ENGINE=InnoDB;
SELECT * FROM t WHERE (a,b) IN (('',''),('',''));
