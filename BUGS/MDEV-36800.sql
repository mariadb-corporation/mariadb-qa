# mysqld options required for replay:  --log_bin=binlog --binlog_format=STATEMENT
CREATE TABLE t1 (c CHAR(1),c2 CHAR(1)) ENGINE=MyISAM;  
CREATE TEMPORARY TABLE t (a INT) ENGINE=InnoDB SELECT+1 a;
XA START 'a';
INSERT t SELECT+1 seq_1_to_1;
SET pseudo_slave_mode=1;
INSERT INTO t1 (c) VALUES (1);
XA END 'a';
XA PREPARE 'a';
