# mysqld options required for replay:  --log_bin
CREATE TABLE t1 (a INT) ENGINE=INNODB;
CREATE TABLE t2 (f INT) ENGINE=ARIA;
SET gtid_seq_no=1;
XA START 'a';
INSERT INTO t1 VALUES (1);
SET GLOBAL gtid_strict_mode=true;
INSERT INTO t2 VALUES (1);
