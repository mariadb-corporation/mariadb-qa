CREATE TABLE t1 (pk INT NOT NULL, c1 VARCHAR(1)) ENGINE=InnoDB;
INSERT INTO t1 VALUES (1,NULL),(15,'o'),(16,'x'),(19,'t'),(35,'k'),(36,'h'),(42,'t'),(43,'h'),(53,'l'),(62,'a'),(71,NULL),(79,'u'),(128,'y'),(129,NULL),(133,NULL);
CREATE TABLE t2 (i1 INT, c1 VARCHAR(1) NOT NULL, KEY c1 (c1), KEY i1 (i1)) ENGINE=InnoDB;
INSERT INTO t2 VALUES (1,'1'),(NULL,'1'),(42,'t'),(NULL,'1'),(79,'u'),(NULL,'1'),(NULL,'4'),(NULL,'4'),(NULL,'1'),(NULL,'u'),(2,'1'),(NULL,'w');
INSERT INTO t2 SELECT * FROM t2;
SELECT * FROM t1 WHERE t1.c1 NOT IN (SELECT t2.c1 FROM t2, t1 AS a1 WHERE t2.i1=t1.pk AND t2.i1 IS NOT NULL);
