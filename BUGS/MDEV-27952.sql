CREATE TABLE t (a INT,b INT,KEY(a,b));
ALTER TABLE t DISCARD TABLESPACE;
SELECT * FROM t;

CREATE TABLE t (c INT) ENGINE=InnoDB;
ALTER TABLE t RENAME foo.t;
