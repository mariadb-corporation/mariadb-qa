CREATE TABLE t2 (t1_a INT,b INT) ENGINE=InnoDB;
SET SESSION pseudo_slave_mode=1;
CREATE TABLE t1 (a INT KEY,b LONG) ENGINE=InnoDB;
XA START 'a';
INSERT INTO t1 SELECT * FROM t1;
INSERT INTO t2 VALUES (0,0);
XA END 'a';
XA PREPARE 'a';
DROP TABLE t1,t2;

CREATE TABLE ti (a INT) ENGINE=InnoDB;
SET pseudo_slave_mode=1;
CREATE TABLE t (a INT) ENGINE=InnoDB;
XA START 'a';
INSERT INTO t SELECT * FROM t;
INSERT INTO ti VALUES (0);
XA END 'a';
XA PREPARE 'a';
ALTER TABLE t ENGINE=InnoDB;
