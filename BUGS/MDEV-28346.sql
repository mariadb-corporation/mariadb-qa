SET sql_select_limit=1;
CREATE TABLE t (c1 INT,c2 INT,KEY(c2)) ENGINE=InnoDB;
INSERT INTO t VALUES (0,0),(0,1);
SELECT c2 FROM t WHERE (0,c2) in ((0,1),(0,1),(0,2));

CREATE TABLE t (a INT PRIMARY KEY, b INT) ENGINE=InnoDB;
INSERT INTO t VALUES (0,0),(1,1),(2,2);
SET SESSION sql_select_limit=2;
ALTER TABLE t CHANGE COLUMN a a BINARY (216);
SELECT * FROM t x WHERE (a, b) IN ((0, 0),(1,0));
