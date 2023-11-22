# mysqld options required for replay: --log-bin 
XA START 'a';
CREATE TEMPORARY TABLE t1 (a INT) ENGINE=InnoDB;
SELECT * FROM t1;
