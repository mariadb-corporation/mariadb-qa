CREATE TABLE t (a INT KEY) ENGINE=Aria;
INSERT INTO t VALUES (1);
DELETE FROM t;
CREATE TABLE t2 (f INT KEY) ENGINE=InnoDB;
LOCK TABLE t WRITE,t2 READ;
SELECT non_existing_function();
OPTIMIZE TABLE t;
INSERT INTO t VALUES (1);