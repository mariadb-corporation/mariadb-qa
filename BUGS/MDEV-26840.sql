CREATE TABLE t (a INT) ENGINE=InnoDB;
INSERT INTO t VALUES();
ALTER TABLE t ADD b GEOMETRY NOT NULL,ALGORITHM=copy;
