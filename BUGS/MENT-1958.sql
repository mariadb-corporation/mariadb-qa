# Main bug: no testcase yet

CREATE TABLE t1 (f1 LONGTEXT) ENGINE=InnoDB;
DROP DATABASE mysql;
INSERT INTO t1 VALUES ('');
DROP TABLE t1;