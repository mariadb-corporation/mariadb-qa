use test
CREATE TABLE t1 (c1 int, UNIQUE INDEX (c1)) engine=innodb;
CREATE TABLE t2 (c1 int);
CREATE TEMPORARY TABLE t1 (c1 INT) ENGINE=MRG_MyISAM UNION=(t1,t2) INSERT_METHOD=LAST;
cache index t1,t2 in default;