CREATE TABLE t (a INT, KEY(a)) ENGINE=InnoDB;
INSERT INTO t VALUES (1),(2),(3);
SELECT * FROM t, t t2 WHERE (5, t2.a) IN ((t.a,1),(2,t.a));

CREATE TABLE t (a INT, KEY (a)) ENGINE=InnoDB;
DELETE FROM t WHERE (1,a) IN ((a,1),(1,a));
