CREATE TABLE t1 (a INT KEY, b TEXT) ENGINE=InnoDB;
XA START 'a';
SET unique_checks=0,foreign_key_checks=0,@@GLOBAL.innodb_limit_optimistic_insert_debug=2;
UPDATE t1 SET b=1;
CREATE TEMPORARY TABLE t2 (a INT, b INT) ENGINE=InnoDB;
INSERT INTO t1 VALUES (0,0),(1,1),(2,2);
INSERT INTO t2 VALUES (0);
INSERT INTO t1 VALUES (2,2),(3,3);
INSERT INTO t1 VALUES (4,4);
