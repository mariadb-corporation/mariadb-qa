CREATE TABLE t1 (id int, a int, KEY (a), KEY (id)) engine=innodb;
INSERT INTO t1 VALUES  (1, 1), (2, 1), (3, 1), (4, 1), (5, 2),  (6, 2), (7, 2), (8, 2);
CREATE TABLE t2 (id2 int,  b TEXT) engine=innodb;
INSERT INTO t2 VALUES (1,'F'),( 2,'D'),( 5,'F'),( 6,'Q');
SELECT id, a FROM t1 JOIN t2 ON id = id2 WHERE t1.id IN (SELECT dt.id FROM  ( SELECT id, avg(a), b  FROM t1 JOIN t2 ON id = id2 )dt);
DROP TABLE t1,t2;
