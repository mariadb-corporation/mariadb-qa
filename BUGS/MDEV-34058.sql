CREATE  TABLE t1(c1 INT) ENGINE=INNODB;
SET @@unique_checks=0;
CREATE  TABLE t2(c1 INT) ENGINE=INNODB;
CREATE  TRIGGER t2_trg BEFORE INSERT ON t2 FOR EACH ROW UPDATE t1 SET c1=c1+1;
SET @@foreign_key_checks=0;
INSERT INTO t2 VALUES (1),(2);