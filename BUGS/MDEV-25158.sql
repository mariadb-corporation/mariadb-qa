SET SQL_MODE='ORACLE';
CREATE TABLE t (c CHAR(1)) ENGINE=InnoDB;
INSERT INTO t VALUES(0), (1), (1), (1), (1);
SELECT * FROM t UNION SELECT * FROM t INTERSECT ALL SELECT * FROM t;

SET SQL_MODE='ORACLE';
CREATE TABLE t (c CHAR(1)) ENGINE=InnoDB;
SELECT * FROM t UNION SELECT * FROM t INTERSECT ALL SELECT * FROM t;