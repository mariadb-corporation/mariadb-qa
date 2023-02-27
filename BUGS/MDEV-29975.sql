SET unique_checks=0,foreign_key_checks=0,autocommit=0;
CREATE TABLE t (c INT KEY) ENGINE=InnoDB;
INSERT INTO t VALUES (0,0);
SAVEPOINT a;
INSERT INTO t VALUES (0),(0);
SAVEPOINT a;
